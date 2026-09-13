local ADDON = ...
local VERSION = "1.0.0"
local LIMIT, PRE_LIMIT, POST_LIMIT, INCIDENT_LIMIT = 3000, 500, 300, 8
local frame = CreateFrame("Frame")
local db, session, pending

-- Only plain scalars enter SavedVariables. Restricted values remain opaque.
local function scalar(value)
    if issecretvalue and issecretvalue(value) then return "<restricted>" end
    local kind = type(value)
    if kind == "string" then return value:sub(1, 240) end
    if kind == "boolean" or kind == "number" then return value end
    return nil
end

local function read(fn, ...)
    if type(fn) ~= "function" then return "<unavailable>" end
    local ok, result = pcall(fn, ...)
    if not ok then return "<denied>" end
    return scalar(result)
end

local function method(object, name, ...)
    if issecretvalue and issecretvalue(object) then return "<restricted>" end
    if not object then return nil end
    local ok, result = pcall(function(...) return object[name](object, ...) end, ...)
    if not ok then return "<denied>" end
    return scalar(result)
end

local function unit(token)
    return {
        exists = read(UnitExists, token),
        role = read(UnitGroupRolesAssigned, token),
        dead = read(UnitIsDeadOrGhost, token),
        friendly = read(UnitCanAssist, "player", token),
        isTarget = read(UnitIsUnit, token, "target"),
        isPlayer = read(UnitIsUnit, token, "player"),
    }
end

local function snapshot(withFocus)
    local result = {
        mouseover = unit("mouseover"), target = unit("target"),
        combat = read(InCombatLockdown), targeting = read(SpellIsTargeting),
        casting = read(UnitCastingInfo, "player"),
        channeling = read(UnitChannelInfo, "player"),
        speed = read(GetUnitSpeed, "player"),
        shift = read(IsShiftKeyDown), ctrl = read(IsControlKeyDown), alt = read(IsAltKeyDown),
    }
    if not withFocus then return result end
    result.flashHealUsable = read(C_Spell and C_Spell.IsSpellUsable, 2061)
    result.flashHealRange = read(C_Spell and C_Spell.IsSpellInRange, 2061, "mouseover")
    result.foci = {}
    local ok, foci = pcall(GetMouseFoci)
    if not ok or (issecretvalue and issecretvalue(foci)) or type(foci) ~= "table" then
        result.focusUnavailable = true
        return result
    end
    for i = 1, math.min(#foci, 3) do
        local object = foci[i]
        local chain = {}
        result.foci[#result.foci + 1] = chain
        for depth = 1, 6 do
            if issecretvalue and issecretvalue(object) then
                chain[#chain + 1] = { restricted = true }; break
            end
            if not object then break end
            if method(object, "IsForbidden") ~= false then
                chain[#chain + 1] = { forbidden = true }; break
            end
            chain[#chain + 1] = {
                name = method(object, "GetName"), kind = method(object, "GetObjectType"),
                clicks = method(object, "IsMouseClickEnabled"),
                motion = method(object, "IsMouseMotionEnabled"),
                unit = method(object, "GetAttribute", "unit"),
                type1 = method(object, "GetAttribute", "type1"),
                type2 = method(object, "GetAttribute", "type2"),
            }
            local parentOK, parent = pcall(function() return object:GetParent() end)
            if not parentOK then break end
            object = parent
        end
    end
    return result
end

local function append(event, details, state)
    if not session or not db.enabled then return end
    local row = { t = GetTime(), event = event, details = details, state = state }
    session.next = session.next % LIMIT + 1
    session.rows[session.next] = row
    session.count = math.min(session.count + 1, LIMIT)
    if pending then
        if row.t <= pending.untilTime and pending.postCount < POST_LIMIT then
            pending.rows[#pending.rows + 1] = row
            pending.postCount = pending.postCount + 1
        else
            pending = nil
        end
    end
end

local function say(text)
    print("|cff69c0b1EUI Click Trace:|r " .. text)
end

local function mark(label)
    if not db.enabled then say("Logging is off. Use /euict on first."); return end
    local now = GetTime()
    pending = nil
    local incident = {
        label = label:sub(1, 120), wallTime = time(), t = now,
        sessionStart = session.wallTime, rows = {}, postCount = 0, untilTime = now + 20,
    }
    local start = math.max(1, session.count - PRE_LIMIT + 1)
    for n = start, session.count do
        local index = (session.next - session.count + n - 1) % LIMIT + 1
        local row = session.rows[index]
        if row and row.t >= now - 60 then incident.rows[#incident.rows + 1] = row end
    end
    db.incidents[#db.incidents + 1] = incident
    if #db.incidents > INCIDENT_LIMIT then table.remove(db.incidents, 1) end
    pending = incident
    append("MARK", { label = incident.label }, snapshot(true))
    say("Marked incident " .. #db.incidents .. ". Capturing 20 more seconds; continue your recovery tests.")
end

local EVENTS = {
    "GLOBAL_MOUSE_DOWN", "GLOBAL_MOUSE_UP", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED",
    "UI_ERROR_MESSAGE", "CURRENT_SPELL_CAST_CHANGED", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT",
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
}

local function onEvent(_, event, ...)
    if event == "ADDON_LOADED" then
        if (...) ~= ADDON then return end
        EUIClickTraceDB = EUIClickTraceDB or {}
        db = EUIClickTraceDB
        if db.version ~= VERSION then db = { version = VERSION }; EUIClickTraceDB = db end
        if db.enabled == nil then db.enabled = true end
        db.incidents = db.incidents or {}
        session = { wallTime = time(), monotonicStart = GetTime(), rows = {}, next = 0, count = 0 }
        db.previous = db.current
        db.current = session
        local build, buildNumber, _, interface = GetBuildInfo()
        session.build = { scalar(build), scalar(buildNumber), scalar(interface) }
        session.unavailableEvents = {}
        for _, name in ipairs(EVENTS) do
            local ok
            if name:sub(1, 15) == "UNIT_SPELLCAST_" then
                ok = pcall(frame.RegisterUnitEvent, frame, name, "player")
            else
                ok = pcall(frame.RegisterEvent, frame, name)
            end
            if not ok then session.unavailableEvents[#session.unavailableEvents + 1] = name end
        end
        append("LOADED", { version = VERSION })
        say(db.enabled and "Logging ON. /euict mark when a click fails; /euict status to check." or "Logging OFF. /euict on to start.")
        return
    end
    if not db or not db.enabled then return end
    local details = {}
    if event:sub(1, 15) == "UNIT_SPELLCAST_" then
        if scalar((...)) ~= "player" then return end
        -- SENT's second argument is a target name and is deliberately omitted.
        local castIndex = event == "UNIT_SPELLCAST_SENT" and 3 or 2
        details.cast = scalar(select(castIndex, ...))
        details.spell = scalar(select(castIndex + 1, ...))
    elseif event == "GLOBAL_MOUSE_DOWN" or event == "GLOBAL_MOUSE_UP" then
        -- A missing mouseover is the failure under investigation, so clicks
        -- remain observable even when no unit can be resolved at all.
        details.button = scalar((...))
    elseif event == "UI_ERROR_MESSAGE" then
        details.id, details.message = scalar((...)), scalar(select(2, ...))
    end
    append(event, details, snapshot(event == "GLOBAL_MOUSE_DOWN" or event == "GLOBAL_MOUSE_UP"))
end

-- Errors in observational code never propagate to the normal UI event path.
frame:SetScript("OnEvent", function(...)
    local ok = pcall(onEvent, ...)
    if not ok and session then session.observerErrors = (session.observerErrors or 0) + 1 end
end)
frame:RegisterEvent("ADDON_LOADED")
SLASH_EUICLICKTRACE1 = "/euict"
SlashCmdList.EUICLICKTRACE = function(message)
    if not db or not session or not session.unavailableEvents then return end
    local command, label = message:match("^(%S*)%s*(.-)$")
    command = command:lower()
    if command == "mark" then
        local ok = pcall(mark, label ~= "" and label or "failed click")
        if not ok then say("Marker failed; check /euict status."); session.observerErrors = (session.observerErrors or 0) + 1 end
    elseif command == "off" then
        append("LOGGING_OFF"); db.enabled = false; pending = nil; say("Logging OFF. Existing evidence retained.")
    elseif command == "on" then
        db.enabled = true; append("LOGGING_ON"); say("Logging ON.")
    else
        say((db.enabled and "ON" or "OFF") .. "; " .. session.count .. " recent events; "
            .. #db.incidents .. " incidents; " .. (session.observerErrors or 0) .. " observer errors; "
            .. #session.unavailableEvents .. " unavailable events. /euict mark [note], on, off.")
    end
end

"""Run with Python and lupa installed; no live WoW or account files are read."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

SOURCE = Path(__file__).parent / "EUIClickTrace" / "EUIClickTrace.lua"
MOCK = r'''
now = 100
messages = {}
SECRET = {}
function issecretvalue(v) return rawequal(v, SECRET) end
function GetTime() return now end
function time() return 1800000000 + now end
function print(s) messages[#messages + 1] = s end
function GetBuildInfo() return "12.1", "12345", "date", 120100 end
function CreateFrame()
    observer = { events = {}, unitEvents = {} }
    function observer:SetScript(_, fn) self.handler = fn end
    function observer:RegisterEvent(e) self.events[e] = true end
    function observer:RegisterUnitEvent(e, u) self.unitEvents[e] = u end
    return observer
end
function emit(e, ...) observer.handler(observer, e, ...) end
function UnitExists() return false end
function UnitGroupRolesAssigned() return "TANK" end
function UnitIsDeadOrGhost() return false end
function UnitCanAssist() return true end
function UnitIsUnit() return false end
function InCombatLockdown() return true end
function SpellIsTargeting() return false end
function UnitCastingInfo() return SECRET end
function UnitChannelInfo() return nil end
function GetUnitSpeed() return 0 end
function IsShiftKeyDown() return false end
IsControlKeyDown = IsShiftKeyDown
IsAltKeyDown = IsShiftKeyDown
C_Spell = { IsSpellUsable = function() return SECRET end,
    IsSpellInRange = function() error("restricted") end }
focus = {}
function focus:IsForbidden() return false end
function focus:GetName() return "EUIRaidButton1" end
function focus:GetObjectType() return "Button" end
function focus:IsMouseClickEnabled() return true end
function focus:IsMouseMotionEnabled() return true end
function focus:GetAttribute(k) if k == "unit" then return "party1" end return "macro" end
function focus:GetParent() return nil end
function GetMouseFoci() return {focus} end
SlashCmdList = {}
'''


class ClickTraceTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        self.lua.execute(SOURCE.read_text(), "EUIClickTrace")
        self.lua.execute('emit("ADDON_LOADED", "EUIClickTrace")')

    def check(self, code):
        self.lua.execute(code)

    def test_click_without_mouseover_and_secret_safety(self):
        self.check('''
emit("GLOBAL_MOUSE_DOWN", "RightButton")
local s = EUIClickTraceDB.current
local r = s.rows[s.next]
assert(r.event == "GLOBAL_MOUSE_DOWN" and r.details.button == "RightButton")
assert(r.state.mouseover.exists == false)
assert(r.state.casting == "<restricted>")
assert(r.state.flashHealRange == "<denied>")
assert(r.state.foci[1][1].unit == "party1")
assert(not s.observerErrors)
''')

    def test_spell_argument_positions_and_player_scope(self):
        self.check('''
assert(observer.unitEvents.UNIT_SPELLCAST_SENT == "player")
emit("UNIT_SPELLCAST_SENT", "player", "PRIVATE TARGET", "cast-1", 2061)
local s = EUIClickTraceDB.current
assert(s.rows[s.next].details.cast == "cast-1")
assert(s.rows[s.next].details.spell == 2061)
local before = s.count
emit("UNIT_SPELLCAST_FAILED", "party1", "cast-2", 17)
assert(s.count == before)
emit("UNIT_SPELLCAST_FAILED", "player", "cast-3", SECRET)
assert(s.rows[s.next].details.spell == "<restricted>")
assert(s.rows[s.next].details.cast == "cast-3")
''')

    def test_bounded_ring_and_marker_survives_wrap(self):
        self.check('''
for i=1,3100 do now=now+0.01; emit("UI_ERROR_MESSAGE", i, "failure") end
local s = EUIClickTraceDB.current
assert(s.count == 3000 and #s.rows == 3000)
SlashCmdList.EUICLICKTRACE("mark tank stuck")
local incident = EUIClickTraceDB.incidents[1]
assert(#incident.rows == 501)
assert(incident.rows[1].details.id == 2601)
assert(incident.rows[500].details.id == 3100)
for i=1,4000 do emit("UI_ERROR_MESSAGE", i, "later") end
assert(#incident.rows == 800)
assert(incident.rows[1].details.id == 2601)
for i=1,12 do SlashCmdList.EUICLICKTRACE("mark another") end
assert(#EUIClickTraceDB.incidents == 8)
''')

    def test_post_window_pause_and_reload_retention(self):
        self.check('''
SlashCmdList.EUICLICKTRACE("mark fail")
local incident = EUIClickTraceDB.incidents[1]
local count = #incident.rows
now = now + 21
emit("UI_ERROR_MESSAGE", 1, "too late")
assert(#incident.rows == count)
SlashCmdList.EUICLICKTRACE("off")
local s = EUIClickTraceDB.current
count = s.count
emit("GLOBAL_MOUSE_DOWN", "LeftButton")
assert(s.count == count)
emit("ADDON_LOADED", "EUIClickTrace")
assert(EUIClickTraceDB.previous == s)
assert(#EUIClickTraceDB.incidents == 1)
assert(EUIClickTraceDB.enabled == false)
''')

    def test_forbidden_focus_and_observer_error_containment(self):
        self.check('''
function focus:IsForbidden() return true end
function focus:GetName() error("must not inspect") end
emit("GLOBAL_MOUSE_DOWN", "LeftButton")
local s = EUIClickTraceDB.current
assert(s.rows[s.next].state.foci[1][1].forbidden == true)
assert(not s.observerErrors)
function GetTime() error("simulated failure") end
emit("GLOBAL_MOUSE_DOWN", "LeftButton")
assert(s.observerErrors == 1)
''')


if __name__ == "__main__":
    unittest.main()

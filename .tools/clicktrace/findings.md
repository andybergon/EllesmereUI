# Priest click-casting investigation

## Current status

On 2026-09-13 the user reported that the problem no longer occurs. The investigation is dormant, not a confirmed general EllesmereUI fix. No production casting code, tooltip settings or defensive indicators were changed. The standalone observer remains available; `/euict off` pauses collection and retains evidence.

## Captured evidence

- 2026-09-08 23:51:37 marker: 13 tank left-clicks across 2.22 seconds, roughly 35 seconds before the marker, had `DBT_Bar_1` as top mouse focus with mouse clicks enabled. Tank mouseover existed, but no spell attempt or UI error appeared during that sequence. This supports DBM timer-bar interception for that incident.
- 2026-09-09 01:18:19 marker: the preceding 30 seconds contain no sustained tank-click burst over two seconds without a successful spell event. Twelve tank left-clicks from -2.744 to -0.930 seconds span 1.814 seconds. Success events occur at -2.094 and -0.777 seconds, mixed with `Spell is not ready yet.` errors. The first right-click after the marker returns `Can't do that while moving`. Top focus is the Ellesmere party unit button with valid tank mouseover.
- Those twelve clicks report spell ID `33076` in the explicit event field. An earlier suggestion that successes were Shield because their cast identifiers contain `17` was unsupported. Treat cast identifiers as opaque; prefer the explicit spell field and do not claim a recipient from this trace.
- Both captures had zero observer errors and unavailable event registrations. The logger does not observe secure handler execution or healing received.

## DBM change

The user ran `/run DBT:SetOption("ClickThrough", true)` in game. SavedVariables at 2026-09-09 01:58:53 confirmed `Default.DBM.ClickThrough = true`; the separate Jods timeline skin still had `false`. This is a historical verification, not a guarantee of every current profile.

## Resume and evidence location

Use the [checklist](click-tests-with-checkboxes.html) on recurrence. Capture the expected spell and spec explicitly. The observer retains at most 500 prior events within 60 seconds and 300 following events within 20 seconds, so busy periods or late markers can miss the failure.

Private copies of the original traces are retained under the repository's common Git directory at `codex/evidence/clicktrace/`, named `eui-clicktrace-2026-09-09-002852-evidence.lua` and `eui-clicktrace-2026-09-09-013516-evidence.lua`. They are intentionally not committed or published. Live logs are in Retail `WTF/Account/<account>/SavedVariables/EUIClickTrace.lua`.

The two HTML checklist filenames preserve the user's existing links and currently contain equivalent content. Checkbox results live in browser localStorage, separately from WoW logs. Prior JavaScript mock checks passed; actual browser rendering was not verified.

## Wrap-up review

Fable 5.1 post-implementation review found no blocking defects and affirmed observer containment, retention arithmetic, spell-event argument positions, restricted-value handling and checkbox persistence. Codex added a readiness guard for slash commands after incomplete initialization and a regression test; this low-severity fix was locally verified after review, not independently re-reviewed. Size, schema-reset and absent-field limits are documented in the README. The repository guard was not installed into the live addon during wrap-up.

Deferred coverage, only if diagnostics need further development: unavailable or secret focus tables, secret objects mid-chain, pre-window age trimming and logging resume/off-marker cases. The mixed section-letter styling is cosmetic and retained to preserve the user's section C reference. Browser/print rendering and further in-game reproduction remain unverified.

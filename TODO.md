# TODO

- 🔍 Reopen priest tank click-casting investigation only if it recurs.
  - Status, 2026-09-13: user no longer sees the problem. DBM click-through was enabled and verified saved on 2026-09-09; this is not proof that every reported failure had the same cause.
  - No EllesmereUI casting fix was applied. Keep the standalone diagnostic addon and [recovery checklist](.tools/clicktrace/click-tests-with-checkboxes.html) available.
  - On recurrence: mark immediately with `/euict mark tank stuck`, note spec, expected spell, error text and recovery test, then `/reload` to save. Codex inspects the preceding clicks and spell events before changing settings.
  - Evidence, limits and prior conclusions: [investigation notes](.tools/clicktrace/findings.md). Ordinary future follow-up, no action needed while it remains absent.

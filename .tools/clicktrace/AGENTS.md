# Click trace diagnostics

- This standalone observer is not an official EllesmereUI component or a click-casting fix. Keep secure frame scripts, attributes and spell execution untouched.
- Inspect mouse-focus ancestry alongside mouseover and explicit spell events. Global clicks alone do not prove secure button delivery or the recipient of a successful cast.
- Treat cast identifiers as opaque. Do not identify a spell by parsing numbers from a cast identifier when they disagree with the explicit event spell field.
- Keep raw SavedVariables evidence private and outside version control. Save a copy before analysis; WoW writes the live file on reload/logout rather than continuously.
- Run `python .tools/clicktrace/test_clicktrace.py` with Lua 5.1 support from `lupa`. Mock tests do not replace in-game verification.

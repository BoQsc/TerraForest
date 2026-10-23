# Automatic two-word world names

2026-10-23. Create world assigns a name when the field is blank or whitespace only.
Sixteen first words and sixteen second words provide 256 base combinations, e.g.
`Misty_Grove` and `Silver_Meadow`. Underscores match the existing save-name rules.
The generated name is shown in the field before the normal launch validation and
generation handoff. Entered names and saved-world opening remain unchanged.

Naming scans directory names once on this UI action. Existing data, backups and
preparation locks reserve their case-insensitive base names; collisions append
`_2`, `_3`, etc. It never writes a save or acquires a lease. Normal command and
native publication checks still guard creation. An independent RNG leaves the
world seed and generation random stream untouched.

The headless `world_browser` check passes, including the actual blank-name Create
action (observing its preparation handoff without starting an unnecessary bake),
explicit-name preservation, selected seed preservation, case-insensitive backup,
model-folder and preparation-lock collision handling, and existing browser policy.
No world-generation or visual-quality acceptance is claimed by this naming check.

```powershell
python tools/run_godot_check.py world_browser --headless --timeout 25 --require 'failures=0' -- --developer-worlds
```

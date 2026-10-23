# First owned tool when gameplay has no selection

2026-10-23. On the existing ready-to-play transition, gameplay selects the first
owned tool in the ten belt slots if no slot is selected. Returning from development
mode uses the same fallback when there is no prior gameplay slot. It never pulls
items from the backpack or grants missing tools. A belt without tools stays
unselected. A player-selected empty slot remains selected, as does any other
existing slot. Development tools and old saved brush modes are not auto-equipped.

The helper runs only at these transitions; there is no per-frame inventory scan.
Existing selection, inventory, tool activation and highlight paths are reused.
Native inventory ownership and save formats are unchanged.

The actual `player_hud_smoke` check passes: development-to-gameplay fallback,
explicit empty hands, preserving a selected hatchet, existing movement/UI/input
behavior, and loading a restored pose with the first remaining belt tool. That
restored loadout has an empty slot zero: the hatchet in slot one is chosen, without
moving the pickaxe from slot five. This replaces the old empty-hands-on-load
expectation while retaining the saved-pose readiness gate.

```powershell
python tools/run_godot_check.py player_hud_smoke --timeout 90 --require 'failures=0'
```

An earlier invocation incorrectly added `--gameplay-construction` to this legacy
fixture. That adds starter materials into slots which it assumes are empty and
produced 11 failures, including focus-sensitive movement/tool-mode checks. The
retained failed log includes passing startup/default-selection checks. The
documented original invocation above passes without weakening its assertions.
This finite interaction check is not a world-scale performance qualification.

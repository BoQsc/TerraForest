# Separate development toolbelt

2026-10-11: developer_belt 19 checks passed; input_surface_regression 27 checks
passed; player_hud_smoke passed with zero failures. Graphical fixtures ran at
1920x1080 fullscreen with a 60 FPS cap. This is functional and visual evidence,
not sustained performance or thermal qualification. Development screenshot
inspected for readable labels, selected slot and layout.

The development belt exposes editor actions without occupying gameplay inventory
slots. Switching restores each mode's selection. Tests cover brush mappings,
blocks, objects, vegetation, road/world workspace routing, wheel wrap, held
movement, rejected developer-item drags and byte-identical gameplay inventory.
Roads/World tools require Esc to open settings so wheel traversal is nonmodal.

The legacy HUD smoke fixture now explicitly enters gameplay before exercising
item tools; Objects navigation therefore expects the assembly tool. Its remaining
inventory, placement, save/restore and player-input checks pass.

Reproduce from project root:

```powershell
python tools/run_godot_check.py developer_belt --timeout 60 --require 'failures=0' -- --gameplay-construction --ground-cover
python tools/run_godot_check.py input_surface_regression --timeout 60 --require 'failures=0' -- --gameplay-construction
python tools/run_godot_check.py player_hud_smoke --timeout 55 --require 'failures=0'
```

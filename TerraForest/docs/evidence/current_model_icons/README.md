# Static icons from current models — 2026-10-24

Pickaxe (1) and hatchet (2) now bake the actual R11 equipment meshes used by
the held tools. Vehicle (501) bakes the current car scene's 32 visible meshes,
including its wheels and accessories; its runtime SVG placeholder override is
removed. Geometry and materials are copied into an offline studio viewport.
The player/vehicle animation and physics rigs are not included in the images.

The offline bake renders at 512px with MSAA and downsamples to transparent 128px
tiles. `--current-models` preserves every other atlas tile and never writes pickup
meshes. The atlas stays 1024×640 RGBA (2.5 MiB decoded), using a previously empty
tile for the vehicle. Runtime inventory, toolbelt, drag previews and resource
notifications retain the shared static texture/region cache. No real-time model
rendering, camera or viewport is added to these interfaces.

Source and exported UI checks each pass seven assertions: actual HUD preparation,
toolbelt/backpack texture identity, shared vehicle atlas/cache, populated transparent
tiles, exact comparison showing only keys 1/2/501 changed, and absence of live 3D
viewports/cameras. `before.png` is the original atlas used for that comparison.
The captured inventory/toolbelt images and all three icon PNGs were visually
inspected. This is icon correctness evidence, not a frame-time benchmark.

Retained evidence:

- `bake/`: successful model bake, geometry counts and run provenance.
- `source/`: successful source UI check and provenance.
- `pack/`: successful exported-resource UI check, provenance and screenshots.
- `fixture_failure/`: initial standalone HUD test omitted the production
  `prepare()` call, accessed a nil inventory, and timed out. Correcting test setup
  and teardown resolved it; game initialization was not changed for the test.
- `export.log`, `pack_smoke.log`: export and packaged startup logs.
- `1.png`, `2.png`, `501.png`: final transparent thumbnails.

Reproduce from the project directory:

```powershell
python tools/run_godot_check.py bake_item_icons --timeout 60 --require 'ICON_BAKE failures=0' -- --current-models
python tools/run_godot_check.py current_item_icons --timeout 20 --require 'CURRENT_ITEM_ICONS checks=7 failures=0' -- --icon-before=res://docs/evidence/current_model_icons/before.png
python tools/export_pack.py --godot 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\Godot Engine.exe'
python docs/evidence/current_model_icons/check_pack.py
```

Restart the game to replace textures already cached by an earlier running process.
Pickup geometry, item behavior, world saves and the existing world/navigation
acceptance gates are outside this image-only update.

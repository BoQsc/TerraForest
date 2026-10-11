# Item icons and durability presentation

0BSD. Verified 2026-10-11 on the current machine; this is UI correctness evidence, not a world-performance baseline.

- `inventory.log`: 33 checks, including actual mouse drag, swap, split/merge, all carried item IDs, wear transfer, green/amber/red bars and developer presentation reset.
- `character_drag.log`: 25 checks, including character equipment and releasing a dragged item outside the UI.
- `atlas.log`: 3 checks; all 29 tiles have visible pixels, unknown IDs return null, and atlas dimensions/transparency are valid.
- `catalog_tooltip.png`: graphical 1920x1080 icon catalog with an actual hover tooltip. `inventory.png`: in-world inventory after real drag tests.

Runtime loads one 1024x512 RGBA texture (2 MiB uncompressed, no mip chain); region textures are cached. Slots update on inventory events, with no live 3D viewports or idle icon rendering. Transparent PNG payload is stored as `.trtex` using the project's existing raw-image convention (246 KB on disk).

Rebake: `python tools/run_godot_check.py bake_item_icons --timeout 35 --require 'failures=0'`. This is an offline authoring operation, run with the game closed. The baker uses existing tools, vegetation, furniture meshes and the default TerraForest block textures. Ore uses tinted stone geometry; clothing uses provisional folded silhouettes because those items have no world garment meshes yet. Those icons should be rebaked when art changes.

All current carried items are covered in backpack, toolbelt, chest and character slots. Furniture remains recipe-based placement, with icons in the object picker; this change does not convert furniture into new inventory item types. Developer action slots remain text controls. Tooltips show item name and exact durability; bars use red at <=25%, amber at <=60%, green above 60%. Decorative controls and drag previews ignore mouse input.

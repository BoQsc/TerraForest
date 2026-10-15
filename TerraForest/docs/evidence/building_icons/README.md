# Building object icons

The shared offline atlas now includes the actual window, hinged door and
guardrail meshes. Production catalog titles resolve to non-null icons, and all
tiles contain visible pixels. Rendered catalog.png was visually inspected.

Reproduce: `python tools/run_godot_check.py bake_item_icons --timeout 60 --require "ICON_BAKE failures=0" -- --icons-only`, then run `item_icons` with marker
`ITEM_ICONS failures=0`. The icons-only option avoids rewriting dropped models.

Atlas storage is 1024x640 RGBA8 (2.5 MiB uncompressed), up from 1024x512
(2 MiB). Existing tile positions are preserved. This is object chooser coverage,
not new carried-item identities, recipes or a GPU frame-time measurement.

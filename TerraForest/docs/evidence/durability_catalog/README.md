# Immediate dismissal and initial durability catalog

2026-10-23. The hit panel clears synchronously when the accepted result reaches
zero, including a destroyed hit region or dead zombie. Surviving targets retain
the existing refresh and fade behavior. No extra health or world queries.

`addons/player_runtime/durability_catalog.gd` holds current world-class, block,
ground-cover, model and tool-wear maxima. Target picking reads those definitions;
the NPC wooden-door damage callback reads the same model row as player attacks.
Inventory and pickup schemas share the tool maxima. Existing numbers and native
snapshot formats are unchanged. Known models now show descriptive HUD names.
Modded model keys preserve their existing fallback.

[The review table](../../DURABILITY_TABLE.md) lists every registered model,
terrain/vegetation/entity category and carried tool, references standalone zombie
anatomy, and explicitly identifies unsupported damage coverage. Provisional shared
model maxima are not a completed balancing pass.

## Verification

- `world_attack`: 79 checks, zero failures. Checks immediate hidden/idle state on
  fatal block, tree, furniture, actor, vehicle and ground-cover hits, all registered
  models present in the catalog, surviving-hit values and expiry, protected
  furniture, tool wear/drop/recollection and existing excavation/interaction paths.
- `character_world`: 20 checks, zero failures. Checks live-region feedback and
  synchronous dismissal on death through the actual world attack adapter.
- `zombie_door_interaction`: 14 checks, zero failures. The shared wooden-door
  profile still permits validated NPC destruction, persistence and subsequent
  player pursuit without granting player salvage or consuming player tool wear.
- Rendered evidence uses 1920x1080 fullscreen at a 60 FPS cap. The fatal-hit
  assertion runs before yielding a frame; the screenshot records the hidden panel
  immediately after accepted destruction, before block mesh publication catches up.

Commands:

```powershell
python tools/run_godot_check.py world_attack --timeout 90 --require 'failures=0' -- --gameplay-construction --ground-cover
python tools/run_godot_check.py character_world --timeout 90 --require 'failures=0' -- --gameplay-construction --zombies
python tools/run_godot_check.py zombie_door_interaction --timeout 90 --require 'failures=0' -- --gameplay-construction --zombies
```

These are finite interaction and presentation checks. They do not qualify world
scale, sustained frame times, thermal behavior or the unsupported systems listed
in the table. Earlier implementation failures remain in the linked initial
[target durability evidence](../target_durability/README.md).

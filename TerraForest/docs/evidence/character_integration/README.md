# Human R11 and Zombie R4 integration — 2026-10-23

The asset-only source checkpoint is `e63a36d8`. Implementation was developed in
the separate `codex/character-integration` worktree while terrain work continued
in the original checkout. No terrain generator, native movement, persistent actor
schema or existing save was rewritten by the character change.

The integrated world was repeated after rebasing onto concurrent terrain commit
`87390a2c`. The final exact implementation commit is `47313035`; all 18 world
checks pass again. `final_world_run.json` retains revision, test and native binary
hashes. The final forest screenshot was re-inspected.

## Passing scoped checks

Godot 4.7.2 Steam, Windows x86-64; rendered checks use Forward+ on the RTX 4050,
fullscreen 1920 × 1080 with a 60 FPS cap. This is functional/rendered evidence,
not a sustained performance qualification.

| Check | Result | Evidence |
| --- | --- | --- |
| Character runtime | 31 checks, zero failures | `20261023T093359471878Z.log` |
| Integrated terrain world | 18 checks, zero failures | `20261023T093808647039Z.log` |
| Character package dependency/provenance | Pass | `python -m unittest discover -s TerraForest/tools -p test_package.py -k character_runtime` |

Runtime coverage includes all 71 human clips, equipment visibility, authored tool
actions, R4 rig/behavior initialization, physical pursuit, actual animated attack
contacts reaching the player adapter, damage, wall occlusion, living leg-loss
crawl, death, corpse retirement, six-resident bound, automatic spawn and collision
readiness/water/missing-ground admission rejection. Integrated coverage includes
actual streamed terrain, belt selection, melee picking/damage/wear, suspension,
world pose restore clearing encounters, unchanged save component schema, and
existing wooden-block damage/destruction with the R11 axe.

The rendered `pickaxe.png`, `pickaxe_swing.png`, `axe.png` and `world.png` were
actually inspected. They show textured human arms/tools and a complete zombie in
the isolated fixture and forest world. They do not certify every frame, clothing
combination, camera angle, crowded encounter or source animation.

## Failed checks retained

The first import overlapped two owned editor processes and produced temporary
DLL-copy errors. A single owned subprocess import resolved that contention.
Default import also requested tangents on surfaces without UVs and extracted
conflicting texture names; the committed import settings retain embedded textures
and existing tangents, at the source 60 Hz. No source GLB was edited.

The initial runtime probes exposed mesh-name normalization, a typed-array query
argument, an incorrect expected physical-bone count and missing-meta queries.
The initial world check exposed the movement capsule occluding its own fitted hit
areas. Their failing logs are retained here; the final probes pass those paths.
The first rendered FP crop was rejected because the combined body mesh put its
own head in front of the camera. Dedicated head/mouth surfaces are now discarded
only in the FP presentation, with eyes/hair hidden; the later captures were
inspected again. Successful script checks alone did not close that visual defect.

The existing `world_attack.gd` regression suite still fails **20 of 51 checks**.
Running it with the original `world.gd`, `world_attack.gd`, `tool_view.gd` and
`package.py` bytes from `e63a36d8` produces the exact same 20 failure labels.
Both logs and `baseline_comparison.json` are retained. The existing packaging
suite likewise has five baseline failures: missing `demo/world.tscn` in four
addon bundles, and an undeclared terrain dependency in world generation.
The new character-specific package check passes. These baseline failures remain
open; this change does not claim a green complete regression suite.

## Remaining acceptance

The [runtime contract](../../../addons/characters/README.md) and
[foundation status register](../../WORLD_FOUNDATION_STATUS.md) retain the next
requirements: survival health/death, persisted encounters/loot, obstacle routing,
automatic traversal, third-person/outfit integration, authored empty-hand and
construction actions, draw/stow transitions, tool-wall clipping and sustained
performance qualification. Contacts currently provide damage feedback and a
session counter; they cannot kill or respawn the player. Original source-package
validation remains separate from validation of this new host integration.

# Regular walking hitches — 2026-10-25

## Diagnosis and change

The supplied RTX 4050 laptop reproduces the reported regular walking pauses.
In a 45-second native-player walk through seed 1703/profile 21, each of the 15
large pauses coincides with admitting a new resident zombie. Initialization
repeatedly extracts mesh surface arrays, skins vertices in GDScript, creates
temporary ArrayMeshes, and fits identical convex collision geometry.
Admission takes 98.79–146.67 ms; complete frame intervals reach 229.745 ms.
GPU time is substantially below those intervals; adding a GPU compute dispatch
and readback to CPU physics would not address the measured repeated work.

`NativeZombieAnatomy` now retains validated packed geometry and shared fitted
shapes. The world passes the previous validated template to new residents and
restored corpses. Asset/skin identity, rig names/rests, initial poses, transforms
and morphs guard reuse; resource changes invalidate it. This cache has world
lifetime, no retained scene-node references or chain of prior anatomy owners,
and does not copy health, injuries, missing limbs or population identity.

Native skin/morph sampling replaces script loops and temporary rendered meshes
for collision fitting, pose fitting, attack contacts and hand compound groups.
Contact-shape inverses are calculated once per query rather than per vertex.
Hand group insertion order and seam vertices are preserved. Attack timing,
occlusion, reach, damage, physics ownership and residency rules are unchanged.
The same six-resident budget, terrain, foliage, collision and graphics remain.
This removes redundant work rather than concealing it behind lower quality,
larger frame budgets, more actors or arbitrary timed spawning.

## Matched source measurement

Core i5-12450H (8 cores/12 threads), RTX 4050 Laptop GPU, 1080p Vulkan,
60 FPS cap, 8 seconds idle, 45 seconds held-W walking, 8 seconds
recovery. The player uses normal collision/gravity, not flight. Frame traces
are buffered in memory and written only after measurement. Stage timings are
nested and must not be added together; wall intervals include waits, and GPU
and engine monitors can lag. These are warm-renderer tests, not cold shader
compilation benchmarks. Distances differ slightly because normal physics and
frame pacing determine travel.

| Walking metric | Before | Native geometry reuse |
| --- | ---: | ---: |
| Distance | 246.54 m | 247.08 m |
| Frames | 2593 | 2700 |
| p95 | 20.456 ms | 17.249 ms |
| p99 | 26.342 ms | 17.558 ms |
| Maximum | 229.745 ms | 24.909 ms |
| Frames > 33.4 ms | 15 | 0 |
| Frames > 50 ms | 15 | 0 |
| Subsequent zombie initialization | 98.79–146.67 ms | 2.72–3.27 ms |

The first after-run precedes the additional attack-contact and corpse-cache
changes. Final packaged measurements are recorded separately in `summary.json`;
do not substitute them silently for this matched source comparison.

## Verification and retained failures

- Geometry cache regression: 30 checks, including independent script reference
  positions for idle/attack/bite/crawl, contact geometry and mouth masks, palm/
  finger groups and order, invalid input, retired-node lifetime, asset/rig
  invalidation, retry after a rejected partial mesh set, and injury isolation.
- Clean imported fixture loads release world/player DLLs only: all 30 geometry
  and 39 anatomical hit/detach/physical-rest checks pass. Source-rendered region
  checks, actual world attack/damage checks, anatomy and population checks are
  retained with their exact source/native fingerprints.
- The integrated player-strike/forest-corpse check passes 40 of 41 assertions,
  but fails its requirement that every body sleeps within six seconds on this
  terrain. A comparison fixture using the HEAD `zombie.gd` geometry/skin/hand
  implementation at the same admitted location also fails that assertion.
  That fixture retains the current native library (its ragdoll solver is
  unchanged), so it is not represented as a complete historical build. Both
  current failures and the legacy comparison are retained. Do not call this
  whole suite green or weaken its rest requirement to hide the failure.
- The first saved-world probe copied only the `.trw` root and failed archive
  acquisition because companion regional stores were missing. The complete
  clone probe then loaded correctly but hit a boulder after 39.29 m, failing
  the unchanged >80 m traversal gate. Its idle attack opportunities exposed
  the remaining script contact bake, now replaced by native sampling. These
  failed fixtures are retained, not counted as successful traversal.
- The final saved-world route uses a complete, read-only Hidden_Grove clone
  and normal teleport to `(800, 0, 1310)` before floor readiness and measurement.
  Original and cloned canonical roots plus companion stores are hashed before
  and after. No user save is intentionally altered or replaced.

## Reproduce and remaining scope

Build both native variants with `python tools/build_native.py --addon
world_runtime --target all`. Use `tools/run_godot_check.py` with
`zombie_geometry_cache`, `zombie_combat_regions`, `zombie_world_combat`,
`zombie_population_world` and `zombie_combat_world`; exact arguments and
fingerprints are in the corresponding run manifests. The travel fixture is
`tests/runtime_travel_profile.gd`, accepting `--profile-dir` and optional
`--profile-origin=x,y,z`; see the saved and fresh package manifests for complete
commands. Re-export with `tools/export_pack.py` after changing native/scripts.

Final exported PCK and its 14 external libraries pass startup. The final fresh
world walk covers 247.18 m (p99 23.920 ms, maximum 30.352 ms); the read-only
Hidden_Grove route covers 247.08 m (p99 17.543 ms, maximum 26.034 ms). Both have
zero frames above 33.4 ms across idle, walking and recovery. Walking admissions
are 2.728–3.783 ms fresh and 2.573–3.163 ms saved. Both original and copied saved
world files are byte-identical after the run. Inspecting the saved arrival
image confirms the forest, terrain, shadows, held tool and HUD remain present;
this is not an art-quality acceptance claim.

This closes the measured regular resident-admission hitch, not every possible
stutter. Cold first asset load still happens once during initial loading;
actual severed visual meshes still use the existing script mesh-bake path.
Mining/placement performance, lower-end hardware, long travel, larger saved
populations and cold shaders require separate measurements. CPU/GPU worker
scheduling elsewhere is unchanged: this bottleneck was eliminated by native
data reuse, not by adding unnecessary parallel work. Terrain corpse-rest
qualification remains open and requires a separate physical-support fix plus
the original unrelaxed integrated gate.

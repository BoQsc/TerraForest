# Three boulder fracture stages — 2026-10-24

The revised request uses three breaks: **2 → 4 → 8 pieces**. The existing boulder
keeps 240 durability and grants 24 stone once on successful final harvest. Damage
thresholds are 80, 160 and 240: with the existing 30-damage pickaxe, these occur on
the third, sixth and eighth contact. Partial damage uses the existing native binary
durability save; no extra fragment save format is needed. Fresh-process restoration
selects the matching cached mesh. Full inventory leaves the depleted quarters
available until space permits the final transaction, without granting duplicate stone.

The first implementation's shape and motion were rejected by the user. Its third
cut could create thin horizontal plates, and its animation brought every centre
toward a common height. That version's images, logs and manifests remain under
`rejected_initial/`; passing engineering checks did not establish visual acceptance.
The next short uniform ease-out version was also rejected as too static; its
image and engineering records remain under `rejected_stiff_revision/`.

The revised native cutter builds closed textured fragments from the actual stone
mesh once per renderer initialization. Cuts choose the longer horizontal axis with
a small irregular tilt, preserving tall chunks through the third break. It keeps
polygon faces through successive cuts, then triangulates the finished faces.
Four shared, fixed-capacity MultiMesh groups
cover intact, halves, quarters and eighths, with at most 512 boulder roots. There
are no per-hit mesh builds, per-piece nodes, rigid bodies or GPU readbacks. GPU
vertex animation rolls each chunk about its own bottom pivot. The struck side
releases first; per-piece timing varies over roughly 0.44–0.60 seconds after a
0.025–0.21 second delay. A short angular impulse and a small sliding recoil damp
away after contact. Every intermediate hit produces a brief reaction without
resetting the settled pose. Child chunks inherit their parent's settled pose at
the next fracture, eliminating the snap back to the unbroken silhouette.
Target rotations range roughly 5–26 degrees with a brief damped overshoot;
outward translation is 0.010/0.018/0.035 source units, plus displacement caused by
rolling and a short recoil. At a typical 10x scale the last translation is 0.35 m.
Baked support corrections preserve volume and set the final chunks on the ground;
one sampled ground normal supplies a local plane for the piece footprint and
nearby displacement. This cosmetic approximation does not collide against detailed
uneven terrain or other bodies. The eight cosmetic pieces fade and retire
after 2.6 seconds. They are not independent loot containers or persistent obstacles.
Partial rocks retain the original stable picker identity and solid collider;
successful final harvest removes collision through the existing transaction.

The new gray granite base-color map was generated with the built-in image tool
through the imagegen skill. The exact final prompt is in [texture_prompt.txt](texture_prompt.txt).
The unchanged output is saved as
`addons/world_ecosystem/art/boulder_granite_v1.png` and consumed by the shared
`boulder_material.tres`. Godot imports it with mipmaps and VRAM compression.
Local triplanar sampling gives the exterior and cut faces a consistent scale
without stretched pole UVs. Small ground stones keep their existing material.

## Verification and inspected images

- `source/`: 8 live mining/save checks and 14 fresh-process restoration/completion
  checks, using actual pickaxe animations and their contact frame.
- `packaged/`: the same 22 checks against exported resources and native libraries.
  Covers exact restored damage/inventory/tool wear, blocked inventory, retry,
  single stone reward, duplicate-harvest rejection and debris retirement.
- `cache/`: 11 checks, including exactly 2/4/8 fragments with every geometric edge
  paired twice, minimum upright chunk height, damage-driven stage selection and
  bounded terminal lifetime.
- `build/`: both debug/release native builds and export/startup logs. The exported
  pack starts with fourteen external native libraries. Package manifests record
  its hash and the source/native/test provenance; unrelated concurrent tool edits
  are identified in their worktree snapshots.
- `motion/`: sampled rendered frames and their actual capture times; the optional
  motion fixture passes nine setup/stage checks. `boulder_roll.gif` is the encoded
  36-frame preview with measured timing, not a performance sample. Screenshot
  readbacks happen only in this test driver, outside the runtime path.

The revised isolated halves, quarters and early/middle/settled roll positions
and final exported in-world halves/eighths, including the settled forest-floor
capture, were inspected. Cuts stay upright, exposed faces use the new granite texture,
and pieces remain near the original footprint. User review of the revised
appearance remains open; engineering checks do not replace that review.
These are feature captures, not a sustained frame-time or settlement-quality
qualification. Existing world-quality, navigation and performance requirements
remain open. Test saves have unique `fracture_check_` identities and reopening is
read-only; existing user saves were not used.

## Retained failures

Logs/manifests remain under `retained_failures/`, with their original timestamps.

- The first cache fixture assumed an indexed mesh; Godot returned a null index
  array for the nonindexed source. The fixture now synthesizes sequential indices.
- Earlier cutters triangulated caps between successive cuts. Strict edge-pair
  checks rejected the third stage for slivers/T junctions; welding and a repair
  attempt did not close it. The final cutter retains full face polygons until
  the final bake. All three stages now pass the same closure requirement.
- One native build used an ArrayMesh-only count method through Mesh. The compiler
  rejected it; vertex counting now reads the normal surface arrays.
- One binary install met a transient Windows DLL lock during another Godot import.
  The process had exited by inspection; retry installed the same built binary.

Reproduce from the project directory using the configured Godot executable:

```powershell
python tools/run_godot_check.py boulder_fracture_cache --timeout 20 --require 'BOULDER_FRACTURE_CACHE checks=11 failures=0'
python tools/check_boulder_fracture.py
python tools/export_pack.py --godot $env:GODOT_EXE
python tools/check_boulder_fracture.py --pack
```

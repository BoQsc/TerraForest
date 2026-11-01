# Town names beside approach roads

- Status: Ordinary source generation and fresh-process restore pass; final UV/photo and installed verification pending.
- Updated: 2026-11-01. Source commit: `2c0de278`. Main integration pending coordinated mine/vehicle source commits.
- User review: Requested one or two town/city name signs; appearance not reviewed.
- Request: Identify towns from their roads without blocking driving or walking.

## Behavior and ownership

New worlds using the normal **Connected countryside** recipe and other integrated
settlement recipes receive one or two signs per town (maximum six). Deterministic
names are shared by all districts of a town, the map and its signs. Existing worlds
are not renamed or regenerated. Native model ownership retains collisions, damage,
salvage, save/reload and region streaming; lettering follows the resident body and
is removed when that body is destroyed. There is no per-frame sign script.

Approach candidates prefer actual connections between towns, then outer street
ends. The transformed board clears roads, shoulders, pedestrian space and building
lots. Publication uses bounded native rays against the **edited** terrain at the
board corners and both posts; no terrain grading is added for decoration. Generation
requires at least one admitted sign per town and stops rather than publishing a
known unsupported sign. Broader seed admission needs evidence before closure.

The dark painted board, rough timber posts and physical cream lettering use
original 0BSD procedural code plus the approved E2 weathered timber/patinated zinc
image-generated textures. No new imported
bitmap, model or font asset is introduced. Godot's existing fallback font renders
lettering under the engine's retained terms; it is not relabeled CC0. Existing
texture notices and optional legacy materials remain unchanged.

## Changes and verification

`addons/world_runtime/town_sign_plan.gd` plans names and safe approaches;
`town_signs.gd` owns static presentation and native persistence registration.
Original runtime-generated sign geometry is contributed under CC0-1.0 by TerraForest
contributors to the extent they hold rights; its original code is 0BSD. Reused E2
material provenance remains in `addons/structures/textures/expansion_v2/`.
Normal `generate_world_task.gd` publication occurs before ecology reconciliation
and saving; `custom_world_plan.gd` version 38 invalidates old preview metadata.

Parser checks pass. `tests/town_signs.gd` passes 18 checks including native body/name
roundtrips, old empty metadata, destruction without ghost lettering, native salvage,
long-name fit, road clearance and facing incoming traffic. Receipt:
[focused check](../../reports/checks/20261101T173939579713Z/run.json).

## Generated-world evidence

Normal **Generate & play** passed 17 checks, then ordinary **My worlds → Open**
passed 18 checks in a fresh process. Seed 1703 has two Coldwater signs and two
Dunvale signs. The names match the map, both towns stream their bodies/lettering,
physical rays hit the boards and both post feet penetrate the edited terrain.
[Creation/restore receipt](../../reports/town_signs_world/20261101T173151258077Z/run.json).
The owned review world is `TownSigns_1703_8a941a34`; no played save was regenerated.

The first inspected images exposed posts overlapping the board face. Their
geometry/colliders were moved behind the board, followed by another **18 passing
fresh-process checks** in [corrected-post receipt](../../reports/town_signs_world/20261101T173519352892Z/run.json).
Retained comparisons below are not final visual approval. All runs were at 1080p,
60 FPS cap/VSync with concurrent native compilation; timed frame samples were
explicitly skipped. Visible HUD FPS is not a performance acceptance measurement.

![Rejected front-post assembly](images/rejected-front-posts.png)
First generated Coldwater approach: rejected post placement; held tool partly obscures lettering.

![Corrected rear posts, partial review](images/rear-posts-partial-review.png)
Corrected assembly: board in front of posts and feet grounded. Still an incomplete
review view because the held pickaxe covers part of the text. Exact screenshot
sources, settings and hashes are retained in [manifest](images/manifest.json).

## Remaining / resume here

After the corrected-post run, source UVs were aligned so timber grain runs up the
posts, sampling inside one plank, and the flat painted board avoids the zinc
texture's folded roof seams. The driver now selects an ordinary empty belt slot
for unobstructed photos. These final UV/photo changes need the next rendered pass;
18 native checks remain passing. No new texture assets were generated or imported.

Next: reopen the owned fixture with the final driver, inspect corrected close and
road views, integrate the focused source through the coordinator, export the combined
build and run ordinary package creation/reopen. The coordinator confirmed that main `world.gd`, `custom_world_plan.gd` and generation
currently contain active mine/ride edits. Integration waits for those owners
to commit, avoiding overwrite or changed inputs during their checks. The source
render window is released; the next combined export is the return trigger. Keep the field/quest/vehicle changes
and current plan fingerprints on merge. Main integration and installed verification
are completion requirements; the source results do not imply they are done.

```powershell
python TerraForest/tools/check_town_signs_world.py --untimed --restore-report reports/town_signs_world/20261101T173151258077Z
python TerraForest/tools/check_town_signs_world.py --pack --untimed
```

Broader seed/recipe coverage, uncontended frame-cost evidence and user visual
approval remain distinct from the reproduced default-world functional checks.

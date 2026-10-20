# Playable world foundation - current contract

Updated 2026-10-20. This is the current priority and coverage register. Historical
PROJECT_PLAN entries are evidence, not a sequence of remaining instructions.
The objective is a coherent generated, persistent, efficiently represented world
that can be played and explored. No subsystem is accepted solely because its
isolated test passes. Unknown is not complete.

## Delivery order

1. **Generation and prepared loading:** one normal create/open path, seed and
   generator identity, prepared terrain/water/map caches, recoverable publication,
   cancellation and useful progress. Existing saves must remain unchanged.
2. **World representation and storage:** bound resident data as travel distance,
   edits, buildings and props grow. Verify normal default paths, distant edited
   representation, cache invalidation, quotas, disk reserve and recovery. Native
   model paging is still opt-in in demo/world.gd; block paging runs normally.
   Next substantive representation gate: the same populated saved-world route
   with model paging enabled, editing/save/reopen, and resident/arrival bounds.
   Do not enable it by default just because isolated pager tests pass.
3. **Connected world quality and gameplay:** finish regional roads/shoulders,
   entrances, interiors, stairs, basements/mine approaches and lake access in the
   generated world. Rare underground locations belong to POIs. Validate routes
   across multiple seeds, on foot and by vehicle, with real production collision.
4. **Scale and release:** mixed content with stated population/detail/distance;
   1920x1080 fullscreen 60 FPS, bounded CPU/GPU/memory/disk, recovery and endurance,
   followed by a clean-machine distributable build. Tests start short; endurance
   is for resource growth and thermal questions, not basic correctness bugs.

These stages overlap only when a dependency requires it. A visible defect stays
open with evidence; it cannot disappear by renaming the milestone. Stop isolated
visual tuning after unsuccessful bounded cycles and return to the world blocker.

## Current coverage and required completion evidence

| Area | Present in the actual project | Still required |
|---|---|---|
| Generator | Native terrain profiles; offline five-site composition with roads, buildings, POI undergrounds and lakes | Mostly fixed topology/palette; broader seed coverage and coherent landscape/design acceptance |
| Preparation | Staged creation, fresh-process verification, no-overwrite publication, progress and cancellation | Whole-route cache coverage; standalone workflow without local Python/toolchain |
| Player map | M map, native cached 256x256 base survey, roads, public destinations, pan/zoom/tracking | Base survey is not a live edited-world raster; document and verify world-representation requirements separately from this UI |
| Terrain and distant world | Native streaming and derived caches, local edits | Distant edits must remain visible; mining/travel tails and cache/resource growth are not fully qualified |
| Buildings and static props | Native blocks, batched props, furniture, doors/windows, storage, regional block paging | Default bounded model paging and detailed populated-world capacity; mixed interiors/approach acceptance |
| Roads and travel | Regional routes, local streets, normal collision loading, parked/drivable vehicles | All shoulders/junctions and high-speed arrival at declared speed; bounded repeated cross-world travel |
| Underground resources | POI mine/cellar, chambers, ore materials and gathering | Rare authored-location quality, circulation, excavation correctness and persistence on a combined route |
| Vegetation | Native sparse clustered distribution, species, harvesting, near shadows, distant LODs | Distant speckling/continuity, bulk-change continuity and combined resource budgets; density increase superseded by user's sparse direction |
| Water | Static volumetric fixed-unit bucket editing and persistence | Keep existing accepted scope; include in combined saves/travel/recovery checks, no new flow/spillage work |
| Player interaction | Inventory/toolbelt, crafting/storage, tools/durability and building | Connected gather/build/store/explore route, UI/input correctness across modes |
| Entities | Native stores, activation, two prepared residents and local behavior | Representative populations, navigation, animations, effects and bounded activation; stored count is not simulated capacity |
| Storage | Versioned snapshots, regional references, validation, backups and lifecycle barriers | Explicit authoritative/cache limits, disk failure/recovery, growth/compaction and large edited-world capacity |
| Multiplayer readiness | Stable identities and some command/storage boundaries | Authority/ownership audit before expanding systems; actual networking remains later work by user direction |
| Release/performance | Pinned native toolchain, local launchers, published 0BSD project | Clean installation/export, declared support, sustained 60 FPS and older-laptop thermal evidence |

## Explicit scope decisions

- No water flow or spillage; food/vitals remain deferred by user request.
- Networking implementation is later; authoritative ownership and replayable edits
  must still be considered now. No multiplayer capacity claim.
- Preserve sparse vegetation and existing models. Distant visual defects remain
  recorded, but AA experiments no longer displace world-foundation delivery.
- Hardware changes invalidate utilization comparisons. Use time/resource measures;
  unavailable older-laptop thermal testing stays unqualified.

## Evidence required to close a gate

Record the production entry point, world/seed, build, changes, shortest meaningful
check, inspected captures where relevant, save/reopen result, workload counts and
limits. A headless correctness pass is not rendered performance acceptance.
Retain failures. Keep the current human review launcher usable. Never overwrite a
player save to make it match a new generator recipe.

## Current change

Map preparation now uses the same native cartography/cache code as the M map.
New-world preparation requires persistence and readback before proceeding; existing
world cache preparation does the same without changing the canonical save. Cache
headers bind version, seed, generator and resolution to the checksum, so a valid
other-world cache cannot be accepted under a renamed file. This closes a small
prepared-loading gap, not whole-world baking or foundation completion.

## Populated model paging correction - 2026-10-20

Actual-world travel exposed missing prefab-only stair rails: the native history
registry omitted non-UI collections. All world model collections now participate.
995-model baseline, central/north/south/return exact nearby records, native journal
edit, normal save and fresh-process return pass. Original failures retained in
`evidence/populated_model_paging`. No source save changed. Next: destination model
collision/render readiness and measured arrival/frame bounds before default enable.

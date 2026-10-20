## Connected access and tower ground-floor correction - 2026-10-20

New actual-world checks start at the regional arterial, follow saved street
connections, climb entrance steps, open the door and enter a building without
intermediate teleports. Representative western, eastern, northern and southern
routes pass with default model paging. The test splits street segments at joining
points; its initial endpoint-only northern graph failure is retained as a test
limitation, not a generator defect. Old southern/northern entrance tests now wait
for destination residency before discovering doors. All four southern approaches
and entry/exit checks pass with paging.

Inspection exposed a real tower defect: the reusable upper-floor opening also
existed at ground level, exposing terrain and grass inside. Furnished towers now
fill those twelve ground cells with the existing slab material. Upper openings
remain unchanged. Native prefab checks cover 2/3/4/16 storeys. New seed42 world
foundation_42_20261020 was fully prepared and reopened through the ordinary
workflow. Its tower ascent/descent passes, and matching interior imagery confirms
the ground opening is closed. Runtime batching and terrain formats are unchanged.

Play Regional World Review.cmd now uses a separate v11 copy of that new world.
Versions1-10 and source/player saves are preserved; the launcher dry run was checked.
No automatic retrofit of existing edited buildings is attempted. Evidence:
`evidence/connected_world_access` (including pre-fix hole and regenerated interior).

Coverage remains limited: one connected representative entrance per outer location,
all four southern door approaches, and one tower's upper-floor route. This does not
qualify every building, basement/mine circulation, all junctions or multiple seeds.
Location design still needs meaningful interiors/variety and landscape transitions;
the plain tower interior is not art acceptance. Next address those remaining
connected-world and generator requirements, retaining the world-quality standard.

## Continuous vehicle travel with default paging - 2026-10-20

The real native car drove the saved seed42/generator13 central-west arterial at
1920x1080/fullscreen capped60, with default model paging, vegetation, actors and
fleet enabled. No pose corrections after initial staging/entry. A disposable
read-only clone preserves the source save. No collision streaming holds occurred.
Exact distance, speed, frame intervals and final stopping position are recorded
in `evidence/vehicle_default_travel/vehicle_paved_stop`.

The original travel test falsely accepted a stop beyond the road: 104 m braking
from approximately160 km/h overran its 85 m stopping allowance, ending20 m beyond
the arterial endpoint on grass. Retained diagnostic image/data expose the error.
The test now begins braking150 m before the endpoint and requires final corridor
containment plus native saved-surface support validation. Slow frames and collision
hold runs are recorded. Separate saved-terrain sampling passes228 points across
three lanes on each of the four arterials. That root-support check is not a mesh,
road-shoulder or navigability proof for those other three roads.

The corrected final image was inspected: vehicle on asphalt, buildings and vegetation
present. Western location remains visually unfinished: repeated cottage massing,
sparse landscaping and unresolved arrival/road-end design. Do not accept that as
world quality. The drive is one straight arterial, not junctions, turning, all-site
collision coverage, save-during-driving or endurance. Those gaps remain explicit.
Next finish the connected-world approach/entrance checks and generator design
requirements, retaining performance sampling on those actual routes.

## Regional model loading is now the normal world path - 2026-10-20

Native transfer preparation now advances directly into bounded transfer work in
the same tick. Previously it forced another frame even with budget remaining.
The shared operation, 500 us, 256-record and 64 KiB budgets still apply; the new
fall-through explicitly rechecks the operation guard. Both native variants built.
Scheduler (42), focus (24) and real paging lifecycle (23) checks pass. The focus
test's stale 8-operation assertion now matches the existing 16-operation adapter.

On the same 995-model populated world, northern arrival improved from 961 ms to
660 ms, south 684 to 483 ms, return 535 to 401 ms. Subsequent real edit/save and
fresh-process reopen pass, with northern arrivals 694/692 ms. All nearby saved
transforms, 128 m render readiness and local collision remain required at release.
Normal launch now enables paging; --no-model-region-paging remains a diagnostic
fallback. Offline preparation already explicitly uses full residency for complete
signature validation. The default-path four-stop route also passes. Evidence:
`evidence/model_default_arrival`. The source save SHA-256 is unchanged; only the
named disposable clone contains the intentional stairrail edit.

This closes opt-in-only model residency and the short-route arrival blocker. It
does NOT close strict frame-time, high-speed predictive arrival, full resident-memory
bounds, storage growth, or sustained performance gates. Measured post-arrival
frame maxima across the edit/reopen checks were 16.7-20.4 ms; earlier larger spikes
remain in evidence. Selection scans and native work caps still apply. Models pinned
by edit history and retirement in progress can remain resident beyond the radius.

Next: qualify continuous world travel with production player/vehicle collision and
attribute frame outliers, then connected generated-location/multi-seed acceptance.
No world-quality approval follows from this engineering check. Earlier opt-in
statements below describe historical state and are superseded here. To regenerate
the test manifest with full residency, explicitly pass --no-model-region-paging;
normal runs now validate paged data against that manifest.

## Durable saves no longer occupy the terrain worker - 2026-10-20

Compound saves freeze their sections on the ordered terrain worker, then publish
on one bounded background job. New saves receive backpressure while it is pending.
Reload/reset and shutdown join publication before replacing state or releasing the
archive lease. Completion certifies derived caches only if the captured terrain
revision and component epoch still match. Native validation, checkpoint retention,
checksums, verified root publication and backups remain in place.

In the populated-world 360 m flight/save check at 1920x1080/60 FPS, height queries
completed in 17-51 ms and mining published in about 116 ms while disk publication
was still pending. Save-window frame maxima were 16.9/17.0 ms. Controlled publication
barriers pass 15 checks; native model paging's real manual/autosave/reload/reset/
shutdown lifecycle passes 23; combined bucket/mining/building save/reopen passes.
Evidence: `evidence/publication_async`. No player save was modified.

Limits remain explicit: component materialization/validation takes 109-176 ms on
the terrain worker before publication; cold main-thread capture is still around
8-9 ms. Baseline flight had a 33.5 ms frame outlier. These short checks do not prove
sustained 60 FPS, walking/vehicle collision readiness, old-laptop thermals or world
capacity. Publication overlap is verified; all save latency is NOT resolved.

Next foundation gate: populated regional model arrival and repeated travel with
editing/saving, then connected generated-world routes and multi-seed landscape
acceptance. Model paging remains opt-in until its arrival/frame bounds pass. Do
not let optional cosmetic work displace the coverage table below. Historical
sections record previous limitations; this section supersedes the synchronous
publication blocker described immediately below.

## Direct section publication removes temporary archive round-trip - 2026-10-20

The terrain save worker passes sections directly to the regional archive adapter.
The base archive exposes the SAME name/type/count/size validation used by encoding;
validation happens before any region-store changes. The adapter copies the input
mapping, commits checkpoints, and encodes/checksums only the final root. Existing
packed-archive publication remains supported. Final checksum validation, flushed
readback verification, backup retention and atomic root replacement are unchanged.

Cold/warm write phases measured 0.84/1.00 seconds versus 1.14/1.28 seconds before;
the temporary encode (~140 ms) and decode (~137 ms) are removed. Native archive,
87-check regional archive, 34-check retention and actual gameplay compound
save/reopen checks pass. An old catalog test now checks current v2 bytes and explicit
v1 compatibility. Both native variants updated. Evidence:
`evidence/publication_direct_sections`.

Blocking remains OPEN: serialization/validation plus durable publication still
occupy the terrain worker for roughly 0.95/1.09 seconds in this short check. Next
isolate durable publication on a bounded worker with explicit ordering/barriers
for repeated saves, reload and shutdown; verify mining/streaming can progress
while a save is pending. Do not remove integrity work to claim a latency pass.

## Checkpoint retention scans unified - 2026-10-20

Native publication profiling identified pre/post-publication checkpoint cleanup
as 0.94-1.27 seconds of repeated root validation. Block and model checkpoint
references now come from one validated read of each canonical/backup root per
sweep, retaining lease protection, missing-checkpoint and corruption rejection.
Cold/warm archive publication fell from 1.44/1.77 s to 0.97/1.11 s on fresh clones
of the same populated world. Full write stages remain 1.14/1.28 s. Native archive
and checkpoint-retention tests pass, including corrupted backups and partial
resident state. Both native builds updated. Evidence: `evidence/publication_root_scans`.

Publication blocking remains OPEN. Next remove redundant intermediate archive
encoding/decoding or isolate publication while retaining the ordered durable
commit contract. Remaining profile: ~140 ms intermediate encode, ~137 ms decode,
~134 ms final encode, ~200 ms durable root publication and ~620 ms retention scans
on a warm save. Do not treat these short smooth save windows as complete streaming
or mining latency qualification. Baseline frame outlier remains ~35 ms.

## Actual flight-and-save attribution - 2026-10-20

A disposable clone of the populated world travelled 360 m using native player
flight at 1920x1080/60 FPS, with cold and warm normal disk saves. Production
full-resident model settings were used (paging still opt-in). Main dispatch was
7.6/2.1 ms; save-window frame maxima were 16.9/17.0 ms after routine console writes
were made opt-in (`--verbose-world-events`). Errors still log and all status text
still displays. Test callbacks no longer print inside measured frames. The initial
38 ms completion sample included both game and test synchronous logging.

Do not declare global frame stability: baseline maximum was 34.2 ms. More
importantly, archive publication occupies the terrain worker for 1.38/1.79 s;
packing adds ~130 ms and component serialization/validation 84-103 ms. This can
stall streaming or edits even while rendered frames remain smooth. Next inspect
regional/archive publication stages and eliminate unnecessary repeated work or
isolate durable publication from terrain work, preserving atomic roots, backups,
checksums and save ordering. Flight does not qualify walking/high-speed collision
or long-run performance. Evidence: `evidence/world_travel_save`.

## Cold water serialization moved to ordered world worker - 2026-10-20

Normal world capture now freezes native water records and shares immutable
terrain/building contact geometry. The existing terrain worker materializes the
payload before component validation and archive publication; no live water object
is read by that worker. Unchanged captures share the same frozen payload. Copied
records are released on the worker after serialization, retaining immutable bytes.

Actual populated-world main-thread capture is 8.5-9.0 ms cold, 0.46-0.56 ms repeated
(previous cold 19-21 ms). Worker serialization preserves the prior SHA-256. Later
live edits cannot change a queued snapshot. The 128 MiB conservative staging
reservation is finite, fails closed and recovers on release. Existing 64 MiB byte
cache bound remains. Actual compound bucket/mining/building save/reopen and manual
save ordering pass. Both native builds updated; format/gameplay unchanged.
Evidence: `evidence/world_capture_worker`.

This is not a sustained frame-rate guarantee: cold capture still consumes about
half a 60 FPS frame, worker serialization may delay queued work, and world size
scaling remains to qualify. Next measure actual save dispatch while travelling
and address the measured limiting stage. Full foundation coverage remains open.

## Unchanged world captures reuse immutable native snapshots - 2026-10-20

Water snapshot reuse now retains at most 64 MiB including catalog bytes, with
copy-on-write ownership for worker saves. Water quantity edits, mutable-region
access/creation, terrain/building invalidation, accepted occupancy patches and
successful restore invalidate it. Catalog identity must also match. No frame
polling or background simulation was added. The populated-world repeated capture
fell from ~21 ms to 0.46-0.49 ms; first captures remained 19-21 ms. Actual compound
save/reopen with bucket edits, terrain mining and partial buildings passes.

Cold/edited capture is still synchronous and remains unfinished. Next implement
bounded preparation or immutable worker serialization for those captures, then
measure real save dispatch while travelling. This cache alone is not proof of
sustained 60 FPS. Memory retention is explicit in native statistics. No gameplay
or archive format change; paging promotion and other foundation gates stay open.
Evidence: `evidence/world_capture_cache`.

## Save capture attribution and native serialization - 2026-10-20

Actual populated-world captures identified water serialization as the dominant
main-thread cost (59-77 ms for 36.9 MB). Replacing per-field extension API calls
with one writable buffer and explicit little-endian encoding reduces complete
capture from 61-78 ms to 21-22 ms in the paired check. SHA-256 remains identical.
Edited and unchanged snapshots roundtrip exactly; truncated restore is rejected
without changing live data. Both native builds updated. Evidence:
`evidence/world_capture_serialization/summary.json`.

This does NOT close the save-frame budget: 21 ms still exceeds a 60 FPS frame.
Next address bounded capture / unchanged section reuse with explicit mutation
invalidation, and measure actual save dispatch during travel. No water gameplay
or archive format change. Paging stays opt-in; arrival tail latency, the earlier
43.523 ms travel spike, storage growth, world-quality acceptance and sustained
whole-world performance remain open under the foundation register below.

## Startup autosave corrected; paging promotion withheld - 2026-10-20

Default-on compatibility checks passed model edit/save/fresh reopen and browser
create/reopen. Writable startup exposed autosave consuming loading time and then
blocking first travel (1932 ms). Controller now pauses automatic-save timing and
submission during loading; manual/shutdown saves remain. Offline generation
explicitly keeps full model residency for complete signature verification.
Fresh reopen still took 1103 ms north, so the one-second gate is not reliable:
production model paging remains opt-in. Evidence: `evidence/model_default_compatibility`.
Prior frame spike and main-thread save capture remain open. Next assess real
travel/loading and save stalls before promotion; do not weaken readiness.

## Short-route arrival gate passes - 2026-10-20

Native completed reads now advance through local stages within each tick. The
scene permits 16 operations while retaining 500 us/256 records/64 KiB budgets.
Two populated routes reach north in 972/966 ms, south 549/484 ms and return
633/667 ms, with exact nearby data, published pages, collision and retirement.
Evidence: `evidence/model_admission_stages`. This closes the recorded one-second
short-route gate, not a general latency guarantee. Prior 43.523 ms spike remains
open. Next normal-launch/default-paging compatibility and final save/reopen, then
combined travel frame attribution. Keep full world-foundation scope unchanged.

## Model admission scheduling improved - 2026-10-20

Automatic background retirement now occupies at most two of the eight native
transfer slots, preserving foreground admission capacity without larger budgets.
Actual north/south arrivals improved 1.782/1.195 s to 1.215/0.467 s in the first
comparison. Both modified routes preserve readiness/correctness; the repeated
route verifies eventual far-record retirement. Slower background retirement and
its temporary residency increase are recorded in `evidence/model_admission_priority`.
North still fails the one-second gate. Paging stays opt-in; next finish arrival
latency qualification and travel frame timing rather than weakening readiness.

## Nearby visual readiness implemented - 2026-10-20

Loading now waits for native model metadata admission AND published render pages
within the 128 m arrival extent. Actual four-stop populated route has zero missing
nearby models at release and local collision ready. Native edge cases, capture
replay and normal startup pass; both native builds updated. Evidence:
`evidence/model_visual_readiness`. Northern/southern arrivals take 1.745/1.249 s,
exceeding the earlier 1 s gate. Keep paging opt-in; next attribute and reduce native
admission latency without weakening readiness. Sustained performance remains open.

## Arrival collision gap corrected - 2026-10-20

Populated-world paging released the northern loading screen before nearby model
collision existed. Production now waits for native structure and vegetation
collision in a small departure box. Four arrivals pass. Evidence and retained
failure: `evidence/model_arrival_readiness`. Visual admission remains open: some
nearby records are still absent at release even when pending render uploads is
zero. Next add bounded native visual readiness over unloaded metadata and actual
published pages; keep model paging opt-in until that and arrival budgets pass.

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
| Buildings and static props | Native blocks, batched props, furniture, doors/windows, storage, regional block paging | Detailed populated-world residency capacity; mixed interiors/approach acceptance |
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

## Model coverage integrated into the playable map — 2026-10-20

The M-map now draws a lilac model-object layer, using the same sparse native raster,
terrain-visibility worker, checksum cache and publication controller as block/water
cartography. This completes the source-to-live-map integration described below.
The region archive worker decodes model packets into survey objects; gameplay
paging cannot consume their dedicated completion channel. Pending, active and
completed cancellation release the correct model byte reservation and asset-specific
checkpoint reference. One archive request/decoded region is held per survey.

Native projection emits at most 256 samples per step, with continuation even for a
large model. It applies the captured collection transform and clips to map bounds.
Footprints under 4 square metres are omitted at this regional scale; larger objects
use conservative transformed bounding rectangles, not exact silhouettes. Terrain
above suppresses coverage. The 512-square layer is drawn below the block layer so
furnishings do not paint over buildings. These are regional navigation marks, not
an indoor map. Shared mesh bounds and collection transforms participate in runtime
invalidation. The content cache has its own namespace/folder, with 16 entries.

Verification: native projection continuation, transformed height, clipping and small
prop filtering pass. Archive checks cover model survey isolation from both gameplay
channels, worker decode and full reservation release on cancellation. In the actual
1920x1080 fullscreen saved world, model placement changed pixels, removal restored
identical pixels, unchanged reopening reused the layer, and closing an outstanding
survey released its request and lease. All model collections retained their original
storage/residency. The three-state run read 486 archived regions, made four visibility
calls (maximum 0.8163 ms), and wrote two caches. Fresh-process repeat hit all three
states with zero visibility calls. Before/edited images were inspected; the large
placed model appears as a readable lilac mark. Current small furnishings mostly fall
below the regional footprint threshold.

Preparation now requires the model map cached before publication; the saved-world
reopen gate passed with all four map layers cached. The canonical world root SHA-256
remains 872531c6141123460ec06132ffbf1ba2c75de5d0089d420f75220d625602717a.
Debug/release structures and world-runtime DLLs rebuilt using the pinned SDK.
Evidence: `evidence/model_map_integration`.

**Remaining map efficiency work:** content-key computation still scans source records
and reads archived model regions before a cache hit. Replace that repeated work with
validated region/asset identities, retaining exact invalidation for unsaved edits,
prototype changes and collection transforms. Local overlay updates, fine-detail
coverage, ordering by surface height across layers, capacity and large-world
qualification remain open. Current visibility tests concern terrain occlusion, not
exact mutual model/block occlusion. The integrated run also logged a startup receive
hitch around 258 ms; screenshots at 60 FPS are not sustained-performance proof.
The broader world foundation and world-art acceptance remain incomplete.

## Model cartography source verified against the generated world — 2026-10-20

NativeStaticBatch now exposes a revision-guarded survey index for resident and
archived model regions, captured collection transform and mesh bounds. A query
returns at most 32 transformed model bounds, using stable ID continuation rather
than rescanning records. In-flight region transfers explicitly report not ready;
unloaded regions and stale revisions are explicit. Unconfigured collections are
not ready. Metadata capture remains bounded by existing collection limits, not a
per-frame operation.

NativeModelMapRegion verifies the existing packet checksum, internal format and
asset identity, and produces identical bounds without admitting models to gameplay.
It is worker-owned and uses the existing model archive format. Bounds are local to
the collection and conservative axis-aligned extents after placement rotation and
scale, not exact mesh silhouettes. Consumers must also invalidate on prototype
bounds/collection-transform changes; edits to a shared mesh resource in place do
not necessarily advance the collection revision.

Native tests cover 70 rotated/scaled records, bounded continuation, resident/archive
equivalence, unloading, stale revisions, corruption, wrong asset identity and
retirement-in-progress. The actual generated world at 1920x1080 fullscreen yielded
995 models across 162 archived and 64 resident regions, with a maximum measured
batch query of 80 microseconds. Collection storage/residency and revisions remained
unchanged. Test reads used checkpoint leases and exact model tickets; archived
packet decoding ran on a worker. Debug and release DLLs rebuilt with pinned SDK.
Evidence: `evidence/model_map_source`.

**Next required work, not complete:** integrate model bounds with the live map's
native reduction, terrain occlusion and derived cache. Include transformed footprint
coverage and a sensible minimum map size so tiny furnishings do not swamp buildings.
Use the existing archive worker rather than one new thread per region in production.
Then verify actual placement/removal, distant archived coverage, cache reopening,
map closure/cancellation and visual readability. The test currently verifies the
source only; models are not yet drawn by the playable M-map. This is continuation
of the same map task, not acceptance or deferral of its unfinished integration.

## Building coverage integrated into the playable world map — 2026-10-20

This supersedes the source-only limitation below. The M-map now draws constructed
block coverage from both resident and archived regions. A dedicated archive worker
completion channel decodes one checksum-bound region at a time without admitting
it to gameplay residency or constructing meshes/collision. Closing an incomplete
map cancels its request and releases its checkpoint lease; normal paging cannot
consume its replies. Archive cancellation accounting now includes queued requests
cancelled before worker execution.

Water and blocks share a native sparse regional raster and bounded survey
orchestration. Blocks use 512-square coverage (approximately 3.9 metres per pixel),
with terrain occlusion in batches of 16 samples. The raster admits up to 262144
subcell samples and fails explicitly at capacity. Source calls yield cooperatively
after about 1 ms; allocation growth and full pixel publication are not yet qualified
at the maximum capacity. Runtime drawing adds one building texture draw.

Derived block caches are checksum validated, keyed by certified terrain identity
and deterministic block-source content, and limited to 16 entries (about 16 MiB).
Cache hits avoid visibility jobs but still scan/read source data to establish its
identity. Preparation now requires the building layer to be ready and cached.
No authoritative world format changed; tests used a read-only snapshot.

Verification: native archive isolation/cancellation, sparse raster and 256/512 cache
checks passed. In the actual 1920x1080 fullscreen world, archived coverage did not
change block residency; a temporary 144-block platform changed map pixels and
restoring the original region reproduced the original pixels. Fresh-process tests
hit all three block state caches with zero visibility queries. Water regression
also passed with zero visibility queries. The prepared-world reopen passed with
22 archived block reads, a cache hit and zero block visibility queries. Before,
edited and distant-neighborhood screenshots were inspected: useful regional
coverage, not exact building outlines. Evidence: `evidence/building_map_integration`.

**Still open:** model-only structures, finer detail, local incremental overlay
updates, avoiding full source traversal on cache hits, and large-city/capacity
qualification. A startup receive hitch reached about 197 ms in this run; the edited
map capture showed 37 FPS. These checks do not certify steady 60 FPS, old-laptop
thermal behavior, world-art acceptance or a game-ready foundation. The generator,
location variety, complete travel/interior coverage, storage endurance and broader
runtime limits listed in this document remain required work.

## Building-map source includes unloaded world regions — 2026-10-20

Native block cartography now exposes a metadata index covering both resident
chunks and checksum-only unloaded regions. The index carries a mutation revision
and world transform; a live region query rejects a stale revision or explicitly
reports unloaded data instead of treating it as empty. The index is a bounded
metadata capture (existing resident/unloaded store limits), intended for survey
start/invalidation, not every frame.

Each column query visits at most one occupied 16-cube chunk and returns no more
than 256 local-space samples; empty chunk positions are skipped within the
64-chunk region bound. Samples use the highest occupied cell in each chunk column
and the actual shape height at its centre, including slabs, stairs and slopes.
These are cartographic samples, not exact silhouettes or already occlusion-tested
building footprints.

NativeBlockMapRegion decodes one existing checksum-bound archive packet off the
scene thread and exposes the same bounded queries. It neither admits the region
to gameplay storage nor builds rendering/collision. No new authoritative save
format is introduced. Existing archive checkpoint leases retain the requested
versions while a worker reads them.

Verification: signed coordinates, highest columns, cube/slab/stair/slope heights,
resident/archive equivalence, stale revisions, explicit unloaded state and corrupt
packets pass. The actual saved world survey included 22 unloaded and 6 resident
regions, yielding 11096 column samples; maximum measured query was 49 microseconds.
Block storage/residency statistics and mutation revision remained unchanged.
Debug/release structures DLLs rebuilt against the pinned SDK. Evidence:
`evidence/building_map_source`.

**Not yet complete:** this source is not yet drawn on the M-map. Native reduction,
terrain occlusion, cached publication and map invalidation still need integration.
Free-standing model-only structures are not covered by block columns. Existing
building-footprint/finer-map and broader foundation gates remain open. No final
visual or large-city performance acceptance follows from the source checks.

## Actual water integrated into the M-map — 2026-10-20

The playable map now draws a separate native-reduced live-water overlay instead
of painting generated basin circles into terrain. Base survey version 3 invalidates
old blue terrain caches. Actual water removal clears blue coverage; snapshot
restoration reproduces identical coverage. Native reduction keeps the highest
sample per 3.90625 m subcell and filters it against actual terrain above, then
reduces 2x2 coverage to the 256-square map. This is approximate regional coverage,
not exact shoreline geometry. Rendering uses one additional texture draw.

Source orchestration admits at most four four-region calls per frame and yields
after approximately 1 ms. Each visibility job has at most 16 points on the ordered
terrain worker. World epoch, terrain revision, water revision and store identity
invalidate work; stale replies cannot publish. Native raster working storage is
bounded (under 5 MiB excluding Godot images/textures). Completed runtime maps are
reused while these identities remain unchanged; closed maps submit no new work.

The water layer has its own checksum-validated, content-keyed derived cache,
limited to 64 entries (about 16 MiB). Its identity combines certified terrain state
and native compatibility, a water-map version, and the deterministic source-point
hash. Unsaved water cannot overwrite the terrain map cache. Unsaved terrain is
surveyed but does not acquire a certified water-cache entry. Disk I/O runs on a
low-priority worker; corrupt/mismatched data uses the normal recomputation path.
Preparation now requires the actual water map to be cached before publication.

Verification in the saved v14 world at 1920x1080 fullscreen: original water,
complete removal, restoration and unchanged reopen pass. Approximately 103000
source samples reduce to 1199 visibility candidates. The uncached integrated run
recorded a maximum 0.268 ms source call and 3.753 ms visibility job. Fresh-process
cache reuse passed for original/empty/restored states with three cache hits and
zero visibility queries. Preparation reopen passed with both map caches reused
and exact settlement blocks, furnishing, roads, resident and spawn signatures.
Base cache corruption/identity tests and native raster validation pass. Debug and
release DLLs rebuilt with the pinned prebuilt SDK.

Inspected before/after overview images confirm blue lake coverage is removed;
public named basin/destination markers intentionally remain. A first script-name
collision and an empty-buffer hashing diagnostic were caught and corrected;
retained failed run summaries and subsequent clean evidence are in
`evidence/live_water_map`. Original authoritative saved-world bytes are preserved.

**Still open:** finer zoom, building footprints, large-population/world limits and
the broader foundation gates below. Cold water maps still incrementally traverse
stored water once; disk hits avoid terrain visibility queries, not that source
scan. Water edits currently invalidate the whole small map layer rather than only
local map tiles. Highest-sample subcells can miss smaller lower exposed water
beside covered water; this approximation must not be called an exact shoreline
survey. This work does not establish ocean-scale or older-laptop performance,
steady 60 FPS, or final world-art acceptance. Water gameplay remains unchanged.

## Water-map height and terrain occlusion established — 2026-10-20

Native water cartography now has a separate bounded surface-sampling query. It
uses cached contact profiles and stored amounts to locate wet column centres;
occupied voxel upper bounds are not treated as water height. Each call visits
at most four regions (256 samples), with the existing cooperative 500 microsecond
stop after a region. Unready contacts are reported explicitly and mutations
invalidate continuation. This changes neither bucket behavior nor save bytes.

The ordered terrain worker now accepts at most 16 water points per visibility
request, yielding a mask from actual edited density above those points. It checks
roofs/overhangs rather than relying on generated terrain height. It has the same
queue admission guards as terrain-map patches, and returns epoch/revision for
stale-result rejection by the eventual map consumer.

Actual saved-world check: 102728 surface samples; sampled points touch stored
water; maximum native source call 204 microseconds; one integrated 16-point
visibility request 1.1339 ms. Mutation rejection, removal accounting and existing
storage restoration checks pass. Native occlusion test rejects covered/solid
points, admits them after roof excavation, preserves the result through storage
restoration, and rejects invalid/oversized input. Debug/release DLLs rebuilt using
the pinned prebuilt SDK. Evidence: evidence/water_map_visibility.

The first occlusion fixture incorrectly expected a sphere brush to excavate a
segment; the retained failure was corrected by explicitly excavating overlapping
spheres through the roof. No production algorithm was changed to satisfy it.

**Still open:** M-map live-water raster accumulation, live-water cache identity,
removing obsolete generated-water colours, building footprints and finer zoom.
The current visible map remains explicitly labelled as a base-water survey. The
new source samples are cartographic point samples, not an exact mesh silhouette;
thin shore fragments between samples need a deliberate raster coverage policy.
No graphical water-layer quality or whole-world performance acceptance is claimed.

## Native water-map source established - 2026-10-20

The existing native regional water store now exposes a bounded cartographic
column survey independent of visible mesh residency. Each call visits at most
16 regions, with a cooperative 500 microsecond stop checked after each region.
At most 1024 occupied-column records are returned per call. A monotonic store
revision rejects continuation after any authoritative/cache mutation; restart is
explicit rather than silently combining old and new water. This introduces no
water flow, changes to bucket rules or changes to snapshot bytes.

Actual saved v14 world verification traversed all stored regions in 506 calls
at a four-region budget, returning 104588 occupied column records. The maximum
observed native call was 13 microseconds on this machine. Summed quantities exactly
match the stored total. Removing real water invalidates an in-progress cursor;
a fresh survey reports exactly the reduced amount. Saving/restoring reproduces
identical columns and amounts. Invalid budgets/cursors are rejected. Evidence:
evidence/water_map_source. The existing connectivity check also passes.

This is the native source dependency, NOT completed live water on the M map.
Columns describe conservative occupied 0.5 m voxel upper bounds, not exact rendered
surface height or terrain visibility. Next accumulate them into a bounded map
layer, combine with terrain surface visibility, invalidate on water mutations,
and qualify cache identity/reload before removing the base-water disclaimer.
Do not render the raw columns as final lake shapes or reveal underground volumes.
The test intentionally collects columns for equality checking; production must
consume incremental batches rather than rebuilding a full record list per frame.
Building map coverage and existing world-foundation gates remain open.

## Prepared cartography reaches gameplay copies - 2026-10-20

The ordinary complete-world workflow now warms edited terrain cartography during
its fresh-process verification phase, after terrain publication establishes the
exact content identity. It uses the same bounded map pipeline as gameplay and
requires a completed cache hit/write before publishing the playable world. This
moves initial modified-terrain surveying out of the first gameplay map open.

World cloning opportunistically carries the derived map cache to the new slot.
It validates magic, exact length and checksum before copying; runtime still checks
the exact terrain/code identity. Missing/corrupt cache never blocks a valid world
clone. Existing destinations remain untouched, and clone-side retention uses the
same 64-entry dedicated cache bound. Tests cover valid copying, existing-save
preservation, corrupt-cache fallback, retention and unrelated-file preservation;
all three pass. All fifteen preparation/cancellation tests also pass.

Fresh seed42/generator13 preparation of foundation_map_42_20261020 passes creation,
reopen and cache publication (150 patches, one write). A further independent review
copy starts a fresh gameplay process and opens its map with one cache hit, zero
writes and zero native terrain patches. Its pixel digest matches the prepared
terrain survey. Evidence: evidence/prepared_map_cache. Play Regional World
Review.cmd now creates v14 from this prepared source; versions1-13 remain intact.
This changes cache preparation, not world layout, assets or save format.

The remaining map layers are still required: live water coverage and building
footprints, with explicit scale/zoom limits. The world-quality, storage-growth and
sustained-performance gates elsewhere in this document remain open. A cache hit
is not proof of overall runtime performance; world startup still shows loading
hitches. Continue the remaining representation scope before unrelated feature work.

## Persistent edited-map cache - 2026-10-20

Edited terrain map pixels now persist in a disposable checked cache. The ordered
terrain worker supplies the exact certified terrain snapshot digest plus native
compatibility fingerprint; the UI does not guess identity from seed/revision or
read mutable terrain on another thread. Unsaved mutations invalidate certification.
Reads/writes/checksums run on a low-priority file worker, outside the terrain worker.
One in-flight IO job and one entry per slot; the dedicated cache keeps at most 64
completed entries (about 16 MiB), with temporary-file rename publication. Existing
world files are never cleanup targets. Header identity, exact size and SHA256 are
validated; a miss/corruption falls back to the bounded native patch queue.

Checks cover wrong identity, corrupted bytes, truncation, atomic replacement,
invalid input and bounded eviction. Actual combined-world checks use an isolated
copy of v13: cold open surveys 150 patches and writes once; a fresh process reuses
exactly identical pixels with zero native patches. Unsaved excavation changes six
patches but preserves the saved cache; a fresh process recovers the original map.
Then ordinary durable save gives the edited map a new identity, replaces its cache,
and another fresh process recovers exactly those new pixels with zero resurvey.
Pixel hashes are compared in evidence/edited_map_cache/pixel_identity.json.

The first unsaved-edit check exposed a missing in-memory identity reset. Revision
checks already prevented a disk overwrite; the stale identity state is now cleared
on invalidation, and the rerun passes. Failed and successful evidence are retained.
Warm full test process duration is about 19 s including world loading; this is not
map-cache IO latency, a speedup claim or thermal proof. No world-generation, save
format or native terrain algorithm was changed in this pass.

The cache currently warms on first map use, not during offline world preparation.
Continue this map scope with preparation-time warming/clone reuse, live water-field
coverage and useful building footprints. The water overlay remains explicitly the
base survey, and 7.8 m raster resolution still limits visible small changes. Native
surveys for a cache miss remain bounded rather than synchronously surveying the
whole world. Overall world generation/design, storage scale, sustained travel and
remaining gameplay qualification gaps are still open.

## Edited terrain on the player map - 2026-10-20

The M map now overlays native surface surveys of modified terrain on its cached
base landscape. Saved modified-column metadata seeds a bounded 4096-tile dirty
set; published terrain bounds invalidate only intersecting tiles plus a shading
halo. Each worker request covers at most 4x4 pixels (36 columns including halo),
one request in flight. It waits behind existing terrain work and is admitted only
without active edits/brushes and with a small queue. Closing the map stops new
requests. Epoch/revision checks reject obsolete replies; reopening retains the
current image instead of surveying the whole world again. All density sampling
runs in C++; GDScript manages the bounded presentation queue and image upload.

Native tests cover excavation changing pixels, exact reproduction after terrain
serialization/restoration and rejected out-of-bounds/oversized patches. The actual
v13 world initialized 150 patches and updated six after one 24 m excavation, with
no base-map rebuild or streaming-focus movement. The complete check passed in
22.1 seconds including world loading. Native patch microcheck was about 3.1 ms;
maximum observed integrated patch was 7.39 ms on the current laptop. This cost is
bounded work, not a hard millisecond guarantee on older hardware.

Existing map control checks pass: M/Escape, pan/zoom, equipment/input isolation,
public-only destination labels, exact saved road widths and reopen reuse. Short
120-frame samples: map-open p95 16.894 ms/max 17.030 ms, closed-after p95 16.860 ms/
max 17.044 ms at 1920x1080 fullscreen cap60. These are not endurance or thermal
proof. Initial world restoration still has loading hitches. Evidence and inspected
map images: `evidence/edited_world_map`. The excavation is a subtle topographic
change at regional scale, not a detailed excavation diagram.

Still required in this same representation work: persistent edited-patch cache
keyed to authoritative saved content, live water-field coverage, and representation
of constructed building footprints/placed objects where useful at map scale.
Water remains explicitly labelled as the base survey, not current bucket state.
The 256x256 raster resolves roughly 7.8 m per pixel, so subpixel edits cannot be
promised visible; zoom magnifies the survey rather than resampling detail. This
closes the missing terrain-edit update path, not the complete world-map requirement.
Next continue cache identity/persistence and remaining layers before changing scope.

## Connected cellar access and durable-close correctness - 2026-10-20

The combined-world player now has an authored 1.5 m footpath from the western
arterial around the cellar cottage to its entrance. It is prepared in the same
protected plan as the cellar, before building placement, then stored with the
road/path catalog. Seven generator seeds pass connected path geometry and base
terrain height samples at one-metre intervals across centre and edges; native
anchor serialization also passes. This is a fixed location recipe, not a claim
of arbitrary-lot path planning.

The first complete bake exposed a storage mismatch: terrain editing permits narrow
paths but native road-anchor storage only accepted widths >=4 m. The resulting
addon capture failed and fresh-process verification rejected the staged world;
no review world was published. Native anchor validation now accepts widths >=1 m,
matching the existing minimum terrain half-width of 0.5 m. Binary layout is unchanged;
existing road persistence and catalog limits still pass. Debug and release DLLs
were rebuilt against the pinned prebuilt SDK. Invalid/nonfinite/out-of-range widths
remain rejected.

That failure also exposed misleading graceful-close success: shutdown_after_edits
reported settled edits even when its final save failed. It now requires successful
persistent publication as well as settled edits. Disposable/read-only worlds still
close without writing. A 17-check shutdown regression includes deliberately invalid
addon bytes and proves both failure reporting and unchanged canonical file hash.

New foundation_cellar_42_20261020 passes full creation and fresh-process reopen.
Its saved path entries restore exactly. The real player walks from the arterial,
climbs the cottage stairs, opens the door, descends into the cellar, climbs back,
and returns to the street without intermediate teleports. The full route takes
about 58 seconds including loading at 1920x1080/fullscreen capped60. This is not a
frame-time benchmark: initial water restoration still reports a >200 ms loading
hitch and the existing sustained-performance requirements remain open.

Inspected overview, approach and ladder images show the connecting path and intact
entrance/interior surfaces. Cottage repetition, simple materials, sparse interiors
and broader landscape quality remain unfinished; these images are not world art
acceptance. Evidence, including the rejected bake, is in
`evidence/cellar_connected_access`. Play Regional World Review.cmd now creates a
separate v13 copy. Versions1-12 and original player saves are preserved; original
southern_mixed_42_20261018 SHA256 remains 3a76b6fa3e86aecf6c529263d22cf59174d73644dcb67d21b8332c4048ed4995.

Next foundation work remains the edited-world map representation and the broader
world qualification gaps (other road/junction and entrance topologies, multiple
complete seeds, storage growth/failure recovery and sustained populated travel).
Connected mine and cellar circulation now have direct integrated evidence; they
must not be relabelled as finished location design or full gameplay coverage.

## Connected mine route and parking correction - 2026-10-20

A full route from the eastern arterial exposed a real generator defect missed by
entrance-only tests: the parked vehicle overlapped the six-metre mine approach.
Collision diagnostics identified the Car body. The mine recipe now places it ten
metres farther into a widened parking apron, outside the access corridor. No
runtime hot path, storage format or native meshing change was needed.

Seven seed layouts pass transformed-chassis corridor clearance checks. Newly
prepared seed42/generator13 world foundation_access_42_20261020 passes creation
and fresh-process restoration. In that world, the native player walks from the
arterial through the mine entrance, both underground branches, and back to the
arterial: all twelve waypoints pass, with 3796 grounded ticks out of 3801. The
short stall check reports the blocking collider instead of waiting a full minute.
Evidence: `evidence/mine_connected_access`. Raw runner metadata retains a mistaken
completion-token failure; the separate assessment verifies the actual test token,
zero exit, clean diagnostics and complete trace without hiding that mistake.

Play Regional World Review.cmd now opens a separate v12 editable copy. Older
review worlds and original saves remain intact. This fixes newly generated worlds;
existing player vehicle positions are intentionally not overwritten.

Images inspected: entrance overview and underground workings. They establish
neither art acceptance nor an interesting finished mine: the entrance remains a
plain large frame and underground branches need authored purpose/detail. This
walk is a connectivity check at 1920x1080 fullscreen capped60, not a performance
benchmark or sustained-60 claim. Connected cellar access, remaining building and
junction topology, multi-seed integrated qualification, map edit representation,
world storage growth and sustained populated travel remain required foundation
work. Do not replace those with unrelated item or vegetation polish.

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
| Player map | M map, content-checked persistent edited-terrain cache, bounded native patch updates, saved roads, destinations, pan/zoom/tracking | Live water, building footprints and finer zoom detail remain incomplete; see latest evidence above |
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

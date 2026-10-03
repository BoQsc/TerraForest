## Cached spatial preparation preview - 2026-10-03

Surveyed site plans now create a single editor overlay mesh: green flat foundation capsule edges, orange sloped-fill bottom edges and connecting guides, cyan asphalt outlines, and pale vertical clearance guides. Depth testing is disabled deliberately so the intended excavation/fill footprint remains readable through terrain and trees. The outline approximates curved boundaries with 12-segment semicircles; it is a planning aid, not authoritative collision geometry. Safety still uses the full plan bounds and native terrain checks.

The mesh is built once per new plan, never once per frame or terrain cell. At most 256 plan sections are accepted; each emits at most 126 line vertices. Rendering has no shadows and uses one mesh surface. Selection/layout changes, world changes, leaving construction and successful building placement hide invalid/inactive previews. Cached geometry is reused when returning to the same plan.

Twenty-seven graphical editor checks passed at 1920x1080, including a single populated preview surface, unchanged rebuild count over frames, mode-switch hiding/restoration and post-placement invalidation, plus the existing grade/pave/place/guard workflow. The initial mode-switch assertion ran before scene processing; the final fixture waits through frame_post_draw. The unobscured aerial screenshot was inspected and shows the intended colored outlines within the forest. Evidence: evidence/site_preview/. This is not a sustained GPU or thermal benchmark.

## Explicit preparation edit outcomes and idempotent sections - 2026-10-03

TerrainWorld now retains one bounded last_edit_outcome record with world epoch, edit ticket, status and density revision. Native unchanged/rejected results are distinguished from changed edits still building; changed edits become published only after main-thread batch commit. The site coordinator requires its exact ticket/epoch and a published or explicitly unchanged result. Published sections require one density revision increment; no-op sections require the same revision. A failed or incomplete publication cannot be counted as an unchanged success.

Eleven coordinator checks passed, including explicit no-op completion and rejected-edit separation. Six real native-worker checks passed: grading a section twice completes both sections with only one revision increment, and resubmitting the entire already prepared two-section plan completes without any additional revision increment. Twenty-two full graphical editor checks passed at 1920x1080, exercising publication, paving, cancellation/retry and placement. Evidence: evidence/site_edit_outcomes/.

This closes the previously recorded no-op preparation issue. The last-outcome record is in-memory and bounded, not a durable command journal. Cross-reload recovery, terrain undo and sustained 60 FPS remain incomplete.

## Integrated frontage street paving - 2026-10-03

The editor preparation plan now appends asphalt street segments after stone grading for version-1 frontages with valid street-width metadata. It uses the native prefab rotation convention (about the cell centre), validates the corridor against actual foundation columns, divides wide streets into native-width strips and respects the combined 256-section limit. The entire grading/paving envelope participates in existing protection checks and the same sequential stop/resume controller. Ordinary prefabs gain no invented street. Missing/inconsistent metadata rejects with a regenerate-layout message. The built-in four-cottage frontage now carries its actual 8 m street width and 3 m setback metadata.

Sixteen native-backed checks passed, including solid asphalt material samples in all four rotations, stone-before-asphalt ordering, a 64 m street split, and invalid/colliding metadata rejection. Twenty-two full editor checks passed at 1920x1080 using the built-in frontage: survey, grade, pave, cancel/retry validation and exact placement, with player/structure/vehicle guards and a focused 60 FPS cap. The result screenshot is retained; its modal obscures much of the street, so material verification relies on native samples rather than that image. No sustained frame-time/thermal qualification follows.

Road intersections and connections between sites, spatial grading preview, terrain undo and recovery across reload remain incomplete. The preparation coordinator still expects an edit revision increment per accepted section; explicit no-op completion handling needs verification before treating repeated preparation as idempotent. Evidence: evidence/site_paving/.

## Exact placement after editor site preparation - 2026-10-03

Completed preparation now exposes Place prefab on prepared site and the panel can reopen its retained site dialog. Placement uses the captured origin/height/rotation, not the current camera aim. The existing complete foundation, deep support, clearance and final player/vehicle/block checks run before insertion. A changed terrain revision triggers fresh validation; a changed world, layout or survey cannot reuse an old prepared target. Closing the dialog cancels pending validation; reopening allows retry. Results are reported in the dialog and duplicate placement is rejected.

Twenty graphical checks passed at 1920x1080 fullscreen, covering survey and real grading, moved camera aim, cancellation and retry, exact single-prefab insertion, duplicate prevention, actual replacement-survey invalidation and player/structure/vehicle protection. The expanded panel ends at Y=977. Screenshot inspection exposed the main-window focus policy throttling a focused native survey dialog to 15 FPS. Focused survey dialogs now retain the configured foreground cap; dialog focus loss uses the background cap. The test requires actual dialog focus and a 60 FPS cap. This fixes the intentional cap selection, not rendering cost or sustained frame-time headroom.

Street paving, spatial grading preview, terrain undo and preparation recovery across reload remain unfinished. Evidence: evidence/prepared_placement/.

## Editor foundation preparation with guarded stop/resume - 2026-10-03

The survey dialog now offers Prepare stone foundation. It captures the surveyed plan and checks the entire expanded site against the player, the native parked-vehicle envelope, structures and static objects before admission and between edits. A structures addon coordinator submits one graded terrain segment at a time and waits for publication. Accepted mutations are never presented as rolled back. Stop, closing the dialog, mode changes and changed selection stop further submissions after the accepted edit finishes. In-session resume applies only remaining sections and requires the captured epoch/revision and unchanged selection. Unrelated terrain changes reject continuation. Progress and partial completion are shown explicitly.

Nine coordinator checks cover whole-site admission, one outstanding edit, graceful stop, exact remaining-work resume, new obstruction and unrelated terrain revisions. Thirteen graphical editor checks at 1920x1080 passed, including actual terrain publication, exact density-revision increment count, no building insertion, and player/structure/parked-vehicle obstruction. The first editor attempt revealed that a native child dialog owns focus; the Prepare handler now accepts its UI action without requiring main-window focus. Screenshot inspected with readable action and affected-area description. A 127.03 ms startup receive hitch remains recorded; these checks do not establish frame-time or thermal headroom.

Preparation grades the rectangular site including gaps. It does not pave roads, place buildings, guarantee post-grading geological support, or roll back completed terrain mutations. Frontage placement must still pass support/clearance checks. Resume state is in-memory only; interrupted application across reload/crash requires a new workflow. A full spatial preview and terrain-edit undo remain unfinished. Evidence: evidence/site_preparation/.

## Layout-derived foundation grading plan - 2026-10-03

The structures site_plan API converts actual native prefab placement bounds into a bounded set of stone foundation capsules, covering the full rectangular site including space between buildings. It chooses the longer sweep axis, partitions length to at most 120 m and breadth to at most 24 m, and supplies an expanded protection envelope including 8 m fill shoulders, 8 m depth and 12 m clearance. Plans exceeding 256 segments, world margins, grade limits or normalized local base Y=0 reject before application. This is infrequent authoring geometry; terrain evaluation stays native. It does not minimize earthworks or preserve holes in the site's rectangle.

Eighteen focused checks passed, including every native foundation column of a 128-cottage layout in all four rotations, per-segment native limits, enclosing protection bounds, world margins, elevated bases and oversized plans. The full graphical 16-cottage fixture now uses the derived two-segment plan instead of hand-coded row positions; grading, paving and support/clearance-gated placement passed. Validation took 1596.87 ms; the 180-frame post-placement sample had p95 16.699 ms and maximum 53.896 ms. Screenshot inspected. These results do not qualify 128 cottages on live terrain or sustained frame-time headroom.

The planner is an addon API exercised by the integration fixture. Editor preview/application, whole-plan player/vehicle/structure protection, cancellation and partial-application recovery remain required before exposing automatic site preparation. Evidence: evidence/site_plan/.

## Construction editor site survey - 2026-10-03

The construction panel now offers Survey ground for selected prefab. It captures the aimed terrain origin and selected rotation, queries the actual foundation footprint asynchronously, and presents the proposed base Y, feasible grade interval and natural elevation range. Duplicate requests are disabled until completion. Selection/layout changes invalidate the proposal; world/terrain changes remain covered by the survey revision checks. The action is read-only and does not automatically grade, pave or place buildings. Edited-surface reconstruction and automatic site development remain incomplete.

Seven graphical checks passed at 1920x1080 fullscreen: real terrain targeting, asynchronous button dispatch with duplicate prevention, useful proposal display, unchanged terrain and structures, visible panel fit and rotation invalidation, plus world startup. The panel ends at Y=936; screenshot inspected with readable centered result dialog and full construction panel. The first test inspected a hidden unsynchronized panel and failed its fit assertion; the corrected fixture invokes the same palette synchronization used by the game. A 327.48 ms startup terrain receive hitch was recorded in the passing run; this is functional UI validation, not frame-time qualification. Evidence: evidence/site_survey_editor/.

## Bounded multi-page foundation scans - 2026-10-03

Foundation validation now submits up to 4096 points per reservation through request_density_scan. The worker executes at most eight existing native 512-point commands, with no intervening mutation. Every page must match the captured revision; any failed page discards the entire result. Ordinary request_density_batch keeps its 512 limit, and both APIs share the existing one-outstanding reservation through result consumption. No native ABI change or larger individual native command was introduced. Native clearance generation still uses its bounded cursor; infrequent authoring orchestration assembles at most eight pages.

Twenty-three density query checks passed, including the shared reservation, 4096 limit, ordering of samples across pages, and rejection of partial results when the final page contains invalid data. The focused 4096-point worker query measured 937 microseconds; this is a warm point-query fixture, not a universal worst-case bound. Eight scheduling-order checks and sixteen full-world support/editor checks passed, including floating fill, intermediate air and interior obstruction rejection.

The same graphical 16-cottage survey/grade/pave/place fixture completed validation in 864.848 ms, versus roughly nine seconds in the preceding recorded run. The ten-second timeout was unchanged. All 7488 cells published across 56 chunks. The short 180-frame post-placement sample had p95 16.686 ms and maximum 40.248 ms: frame spikes, broader scale and thermal headroom remain unresolved. Evidence: evidence/paged_foundation_scan/.

## Survey settlement grades and service support queries between mesh jobs - 2026-10-03

A new read-only structures site survey samples the actual foundation footprint using native natural-surface queries. It proposes a grade within bounded cut/fill limits and rejects unavailable/stale surfaces; post-edit support and interior checks remain mandatory. The combined 16-cottage fixture surveys 1584 columns, selects Y=44 instead of player-derived Y=52, grades two rows and paves the street. This is an authoring API exercised by a test, not an editor-integrated automatic city planner, and cannot survey arbitrary edited surfaces.

The first surveyed run still timed out because tiny support queries waited behind background mesh jobs. Density batches now use cooperative regional read points and, for every meshing mode, a read point between worker jobs. The one-outstanding reservation remains bounded; the facade no longer rejects admission solely because more than eight background jobs are queued. Eight focused ordering checks verify reads cannot cross edits, saves, loads, resets or unknown work. Sixteen density-batch checks and the native-backed site survey passed.

The graphical default-mesher fixture passed at 1920x1080 fullscreen with 7488 structure cells, 56 published chunks, 20320 triangles and 2014 vegetation roots. Validation still took roughly nine seconds, close to its unchanged ten-second timeout; robust authoring latency is NOT resolved. Over 180 post-placement frames, p95 was 16.68 ms and maximum was 48.798 ms. This is not sustained 60 FPS or thermal/fleet/populated-city qualification. Screenshot inspected; cottages, paved street and surrounding forest are visible. Evidence, including earlier failures: evidence/site_survey/.

## Continuous voxel-layer grading support check - 2026-10-03

Native command 30 checks every voxel layer down through a bounded 0-8 m column and returns the maximum density per point. The existing worker reservation/revision pipeline exposes this through request_density_batch support_depth. Frontage deep support now uses column queries instead of only translated endpoint probes, catching intermediate air pockets. Six native checks, sixteen existing density-batch checks and sixteen full-world authoring checks passed. A 512-column focused query measured 100 microseconds. Initial repair used the exact excavation radius and left zero-density boundary samples; widening repair to 1.5 m supplies the solid margin needed by the conservative check. Both native terrain binaries rebuilt. This proves sampled-column continuity through the grading envelope only; lateral support and deeper geology are not structural guarantees. Evidence: evidence/support_columns/.

## Reject floating graded slabs during frontage placement - 2026-10-03

After immediate foundation support, frontage validation now samples the same columns beneath the maximum 8 m grading fill envelope, clamping toward the protected bottom slab at low altitude. Native packed-array translation and the existing revision-consistent 512-probe worker path handle this extra pass. Thirteen full-world headless checks passed: isolated graded beds at Y=180 reject despite solid surface probes; adding a controlled underlying hill and clearing room space permits placement. Earlier combined-world captures predate this stronger policy and must not be treated as proof their sites pass it. This is a conservative two-depth screen, not continuous-column connectivity or structural analysis; caves/voids between or below probes remain outside its proof. Evidence: evidence/frontage_deep_support/test.log.

## Foundation shoulder editor controls - 2026-10-03

The Roads / Foundations panel exposes a 0-16 m Foundation fill shoulder for Stone foundation. The outline includes the wider bottom perimeter and slope edges. Boundary validation and player, vehicle and structure obstruction envelopes include that extension. Asphalt keeps shoulder zero even when a foundation value is stored. Twenty-six graphical full-world editor checks passed, including a structure outside the flat bed but inside the shoulder rejecting grading, successful expanded foundation publication, unchanged-preview reuse and panel fit at 1920x1080 fullscreen. Screenshot inspected for controls/outline only; the test camera is outside the resident terrain area, so this image does not show finished grading. Evidence: evidence/shoulder_editor/.

## Sloped fill shoulders for graded beds - 2026-10-03

Added optional 0-16 m fill shoulders to construct_graded_bed and a backward-compatible 48-byte command 28 packet. Native fill tapers down from the flat bed to its bounded bottom at the sides and capsule ends; clearance cutting remains within the flat corridor. Admission and dirty bounds include the expanded footprint. Twelve focused checks and all 26 legacy road checks passed. The combined 16-cottage graphical fixture passed eight checks with an 8 m shoulder; inspected screenshot shows sloping side banks replacing abrupt platform walls. Street approach design, uphill cuts outside the corridor and deep-ground connectivity remain unresolved; this is not automatic terrain blending. The option is available through the addon API, not yet the road palette. The short combined sample peaked at 40.775 ms; no performance improvement is claimed. Both native terrain binaries rebuilt. Evidence: evidence/grading_shoulder/.

## Combined terrain, forest and cottage street - 2026-10-03

A graphical 1920x1080 fullscreen Forward+ fixture grades two 93 m stone rows and an asphalt street through the live terrain worker, then places sixteen cottages through normal support/clearance checks. Eight checks passed on the second run with the same 30-second startup deadline; the first run timed out before initialized messages, and its cause remains unresolved (log retained). The successful scene contained 7,488 building cells, 28 mesh chunks and 2,144 vegetation roots with no pending reconciliation at capture. Over 180 post-placement frames, p95 was 16.702 ms and maximum 51.800 ms. Screenshot inspected: grading creates raised platforms with abrupt ends/edges, not a naturally connected road or complete settlement site. Density support screening does not establish deep foundation connectivity. The next settlement geometry work must address site transitions and supported fill, not merely increase cottage count. No vehicle, occupied-city, long-run or thermal qualification is implied. Evidence: evidence/settlement_world/.

## Regional vegetation reconciliation for block edits - 2026-10-03

Native block transactions now emit committed changed-chunk bounds before their ordinary change notification. The structure facade forwards regional vegetation notifications; ecosystem owners cache bounds of their transformed vegetation prototypes, including canopy/wind margin, and skip owners outside the edit bounds. Placement, deletion, undo and redo share this path. Snapshot restores and model changes without reliable bounds retain full reconciliation. Fourteen frontage/vegetation checks passed, including skipping the distant owner, rejected edits emitting nothing, bounded undo/redo and full snapshot fallback. Twelve water-exclusion and four ecosystem-budget checks also passed. Both native structures binaries rebuilt. This still scans cached owner AABBs and uses the union of touched chunks, so widely separated edits can reconcile owners between them; it removes full per-root overlap work for distant owners rather than claiming a spatial notification index. Evidence: evidence/vegetation_regional/.

## Frontage vegetation exclusion integration - 2026-10-03

Ten targeted headless checks passed using the actual vegetation assets, native block overlap queries and native trunk proxy membership. Placing a four-cottage frontage removed only two intersecting roots, retaining a street root and a distant root with unchanged transform. Removed roots also disappeared from trunk proxy records. Removing the buildings restored all deterministic candidate roots and proxy records. This verifies membership, not rendered foliage or live physics contacts. Inspection also identifies remaining scheduling inefficiency: structures.changed marks every resident vegetation owner for reconciliation, although resulting removals are selective. Regional change notifications are still needed to bound that scheduling work. Evidence: evidence/frontage_vegetation/test.log.

## Streamed settlement camera traversal - 2026-10-03

A 720-frame 1920x1080 fullscreen Forward+ camera traverse covered 1,480 m out/back along 128 cottages in 12.000 s (123.34 m/s). Streaming used a 192 m radius, 128-chunk cap and separate 16 MiB mesh/cache budgets. Observed zero roadside collision-readiness gap frames, 104 peak mesh chunks, 8,183,200 peak mesh payload bytes and 16,764,928 peak cache capacity bytes. Frame p95 was 16.730 ms, maximum 17.311 ms. There were 104 cache hits and 276 mesh evictions; collision pieces were retired/rebuilt during travel. Exit status gates residency limits; collision gap count is reported separately. This is isolated structure traversal without vehicle dynamics, terrain, forest, entities or long-run thermal evidence. Final screenshot inspected; camera ends facing outward at the street edge. Evidence: evidence/settlement_travel/.

## Large frontage mesh publication and material startup - 2026-10-03

Added a short 1920x1080 fullscreen Forward+ test on the GTX 1060 Max-Q for 128 cottages (59,904 cells, 192 mesh chunks, 151,680 triangles). Corrected upload telemetry located an initial 184.158 ms frame spike at first publication, whose upload step included lazy material/texture initialization (178.383 ms). Structure facade and standalone demo now initialize their selected materials during startup. Same fixture afterward: maximum sampled publication frame 16.767 ms, p95 16.722 ms, maximum upload step 2.002 ms, 3.233 s for all mesh chunks. Insertion is timed separately at 13.884 ms and excluded from these frame percentiles. Material work is moved to startup, not eliminated. Only 32 nearby collision chunks were active; all-city collision, terrain, vegetation, entities and sustained thermals are excluded. Screenshot inspected for the initial layout; identical layout retained after startup change. This is a short isolated result, not a full-world 60 FPS guarantee. Evidence: evidence/settlement_publication/ (initial incomplete counters retained separately).

## Asynchronous frontage authoring - 2026-10-03

The world editor now submits frontage composition to one low-priority worker using captured packed records and private native resources. Composition and resource saving both happen there; the scene thread only consumes a finished result and updates its library/UI. An initial composition-only offload still spent 21.430 ms saving during completion, so file saving was moved to the worker too. Final targeted maximum-layout test observed 3.696 ms submission and 0.039 ms maximum poll/completion, with geometry matching the synchronous reference. Eight worker lifecycle checks and eleven full-world checks passed, including source mutation isolation, duplicate rejection, shutdown file cleanup, and the actual world authoring action publishing 128 cottages. Large block insertion, mesh publication and rendered frame time remain separate concerns. Evidence: evidence/frontage_async/.

## Maximum frontage CPU scaling check - 2026-10-03

A targeted headless check exercised 4, 16, 64 and 128 authored cottages. Twenty correctness checks passed, including exact snapshot roundtrips. At 128 cottages: 59,904 cells, 104,064 clearance probes, 204 batches, 230,700 snapshot bytes. Combined query/reply memory remained bounded at 8,224 bytes per batch. Observed native composition was 26.004 ms, insertion 10.341 ms, total density query time 23.685 ms, slowest density batch 1.299 ms. This exposes a scene-thread authoring hitch: maximum frontage composition alone exceeds the 16.67 ms frame budget. Large composition needs asynchronous authoring before calling this a hitch-free editor. The test took about one second overall and excludes rendering, collision, worker queue latency and thermal qualification. The queried terrain was not asserted to support the buildings; this checks data-path scaling. Evidence: evidence/settlement_scale/.

## Frontage interior terrain screening - 2026-10-03

Frontage placement now follows foundation support with revision-consistent clearance checks. Native cached column spans include empty room space between a floor and roof, excluding unoccupied street columns. Prefix-indexed cursors return at most 512 probes without allocating an expanded building volume. Seven native tests passed, including rotation, page boundaries, invalid input, transactional cache preservation and a 4095-cell-tall sparse column. Ten full-world editor checks passed: a terrain obstruction above a supported cottage floor rejects placement, and regrading permits the six-cottage frontage. This remains conservative lattice screening, not exact mesh intersection or structural analysis; arbitrary spaces without occupied floor/roof columns are not inferred. Evidence: evidence/frontage_clearance/.

## Frontage placement support enforcement - 2026-10-03

Frontages now wait for bounded terrain-worker foundation checks before placement. Unsupported probes reject placement. Large footprints advance in 512-probe batches with a 10-second deadline; terrain revision/epoch changes and editor selection changes cancel. Commit rechecks terrain state, blocks, player and parked vehicle clearance. The ordinary prefab path remains available for stairs and modular assemblies; frontage metadata opts into support enforcement. Preview bounds are amber until the placement check, rather than implying proven ground support. Seven full-world headless checks passed, including a six-cottage 594-probe placement spanning two batches, unsupported rejection and rotation cancellation. An initial test fixture failed to refresh its palette after appending an asset; corrected fixture rerun has no engine errors. Startup LOD hitches reached 180.26 ms. This screens foundation voxel centres only: it does not prove full contact, exclude terrain from interiors or establish structural stability, and manual grading is still needed. Evidence: evidence/frontage_support_editor/test.log.

## Bounded terrain-worker site queries - 2026-10-03

Added native command 29 and request_density_batch for 1-512 world-space density probes, with one outstanding reservation through completion consumption. Native sampling checks the requested density revision and validates all coordinates before returning lattice samples. The facade removes values on stale revision/epoch, pending edits, active brush, shutdown or unavailable world. Sixteen headless checks passed including the exact upper bound, malformed input, native sample equivalence, worker delivery, reservation pressure and stale-result rejection. Both terrain binaries rebuilt with the pinned prebuilt SDK. Sampling uses floored voxel coordinates, matching command 26; it is not interpolated surface contact. Prefab placement consumption and final commit revalidation remain unfinished. Evidence: evidence/terrain_density_batch/test.log.

## Native foundation footprint probes - 2026-10-03

NativeBlockPrefab now caches lowest occupied cells per X/Z column during authoring. foundation_samples transforms column-centre probes below those cells, filtered by an explicit local foundation height band to exclude eaves and balconies. Thirteen headless checks passed, including all rotations, stepped bases, invalid-input cache preservation, 396 supported cottage probes on actual graded terrain and unsupported probes after excavation. Seventeen existing composition checks also passed. Both structures binaries rebuilt against the pinned prebuilt SDK. This is a prerequisite for placement validation, not automatic editor enforcement: revision-consistent worker queries and commit-time revalidation remain to be integrated. Centre probes do not establish full contact coverage or structural stability. Evidence: evidence/prefab_foundation/.

## Parked vehicle grading protection - 2026-10-03

Road and foundation submission now checks the vehicle envelope from the native driving policy, including suspension support beneath the chassis. Twenty-three full-world headless editor checks passed, including rejection of asphalt paving and stone grading through a parked vehicle before terrain mutation, followed by successful unobstructed edits. This guards submission against the currently present single vehicle; it does not cover general mining or a vehicle entering an already submitted asynchronous edit. Startup logged 50.58 ms world processing, 50.91 ms LOD requests and 189.08 ms LOD scheduling; no sustained frame-rate or thermal claim follows. Evidence: evidence/road_vehicle_guard/editor.log.

## Level foundation selection - 2026-10-03

Added Level end to start height to the Roads / Foundations palette. It preserves horizontal endpoints, updates the preview and clearly states that terrain is unchanged until Build. The action shares the existing world/editor guards. Twenty full-world editor checks passed, including equal endpoint heights, unchanged terrain revision before Build and successful subsequent foundation publication. The 1920x1080 panel capture was inspected. This supplies manual level grading; automatic settlement siting and terrain support validation remain unfinished. Evidence: evidence/foundation_level_editor/.

## Combined frontage and terrain grounding check - 2026-10-03

A controlled solid-hill fixture now combines native stone grading for two building rows, asphalt paving and ordinary block-prefab placement. All 396 bottom-cell samples have solid support one metre below; all 1,476 upper-cell samples are outside solid terrain. Asphalt identity and placement passed. Terrain and building meshes rendered together at 1920x1080 fullscreen; image inspected. Initial render attempts supplied invalid vertical region spans; corrected to native 32 m bands. The resulting image deliberately retains surrounding hill mass: bounded local cuts form recessed rows, not a connected/landscaped town site. No automatic terrain planning, traffic access, complete collision qualification or performance claim is made. The fixture uses direct native commands on controlled terrain, not the streamed-world UI. Evidence: evidence/settlement_grounding/.

## Foundation grading editor - 2026-10-03

The road palette now offers Asphalt road and Stone foundation. Both use the existing endpoint/width/depth/clearance preview and player/building obstruction checks; stone dispatches the new grading API with material 1. The action label and submission status identify the operation. Eighteen full-world editor checks passed at 1920x1080 fullscreen, including foundation submission and worker completion. The panel screenshot was inspected for layout; the remotely positioned fixture capture shows controls/outline, not finished foundation geometry. Startup recorded 56.51 ms controller and 103.22 ms world-process stages; no sustained performance claim follows. Automatic settlement alignment/support remains unfinished. Evidence: evidence/foundation_editor/.

## Material-selectable terrain grading - 2026-10-03

Added construct_graded_bed and a backward-compatible extended command 28 packet. Native fill/cut geometry and existing road limits remain shared; material IDs 1-4 select the bed surface, with legacy road commands defaulting to asphalt. Ten focused checks verified grading, subsequent narrower paving, preserved surrounding material, invalid-material rejection and snapshot round trip. Twenty-six road/worker checks passed including the new API through asynchronous publication. Both terrain binaries rebuilt using the pinned prebuilt SDK. This supplies a terrain operation for settlement preparation; it does not yet automatically support/place a settlement, fill arbitrary deep valleys or provide a cross-system transaction. Evidence: evidence/terrain_grading/.

## Pave already graded terrain - 2026-10-03

A focused test exposed roads skipping asphalt assignment when the requested solid density already matched the terrain (material stayed 1 at density -1). Native road edits now count material-only changes inside the solid bed, preserving cut walls, air and protected bedrock. The regression now observes material 4 at unchanged density, no changes on repetition, unchanged off-corridor samples, and exact material survival through save/reload. Both native binaries rebuilt against the existing prebuilt SDK. All 24 road-bed checks passed on rerun. The initial broad test missed its 10-second startup deadline and then exceeded the 35-second process timeout during shutdown; its log is retained. The fixture startup allowance is now 30 seconds, consistent with other world fixtures; the passing rerun took about seven seconds. No startup/loading issue is claimed fixed. This corrects a prerequisite for grading followed by paving; settlement terrain grading remains unfinished. Evidence: evidence/road_existing_surface/.

## Frontage geometry and entrance visual check - 2026-10-03

The actual four-cottage frontage rendered at 1920x1080 fullscreen through NativeBlockWorld: 1,872 cells, eight mesh chunks, 4,768 triangles. Independent cell checks verified both rows retain two-cell doorway openings with solid neighboring walls facing the reserved street. Overview and street-level images were inspected. The fixture explicitly labels screenshots as visual checks and suppresses stale/FPS HUD telemetry, which was contaminated by startup and PNG capture in the initial run. Mesh publication completed; the test does not wait for or qualify all collision, terrain support, asphalt, world integration or performance. Evidence: evidence/frontage_render/.

## Frontage authoring and personal-library integration - 2026-10-03

The construction palette now opens a frontage dialog for buildings per side, street width and gap/setback. It uses the selected building prefab and entered name, calls native composition, saves through the personal library and selects the resulting asset through the existing placement workflow. Invalid composition leaves the library unchanged. Twenty-four library checks passed, including frontage geometry/metadata reload; a fullscreen 1920x1080 dialog fixture verified parameter submission and disabled/hidden state, and its screenshot was inspected. This test directly emits UI signals rather than simulating mouse clicks. World script loading passed; full-world frontage placement and terrain grading remain unverified/unfinished. Evidence: evidence/frontage_editor/.

## Native street-frontage composition - 2026-10-03

NativeBlockPrefab now composes deterministic paired building lots along a reserved straight street. It accounts for rotated and offset source bounds, aligns ground level, enforces gaps and existing prefab budgets, and preserves the old resource on rejection. Ten focused checks passed: 128 lot layout, clearance, seeds, invalid input, ordinary block placement, conflict rejection and snapshot round trip. Sixteen actual cottages produced 7,488 cells in one observed 4.776 ms composition. Existing prefab composition checks also passed. The main prefab catalog includes a four-cottage ungraded frontage using the existing preview/placement pipeline. This is the initial settlement composition primitive, not completed town generation: terrain support/grading, asphalt placement, road connectivity, settlement editing and large-city rendering qualification remain open. Evidence: evidence/settlement_frontage/.

## Remove hidden vehicle import nodes - 2026-10-03

The native vehicle adapter now releases its hidden GLB setup hierarchy after runtime mesh, door, wheel, accessory and damage references are established. The visible nodes retain their shared mesh/material resources. A two-vehicle check verified 32 shared mesh instances per car, 11 accessories and 10 damage meshes, with descendant node count reduced from 98 to 63 after deferred cleanup (35 fewer nodes per car). Repair still restores the original mesh resource. Native damage parity (6,266 vertices), accessory parity (600 ticks) and 18 world interaction/storage checks passed. This reduces retained scene-node overhead; it does not reduce the visible triangle count or prove fleet rendering performance, and initial import nodes are still constructed transiently. Evidence: evidence/vehicle_visual_sharing/.

## Reuse existing vehicle during restore - 2026-10-03

Restoring a present vehicle now reuses the already instantiated model instead of freeing and rebuilding it. The reset applies the exact saved pose, clears retained streaming momentum, parks/disables simulation, repairs transient dents and cancels/resets the door tween. Missing vehicles still instantiate normally; absent saved vehicles are removed. Eighteen interaction/storage checks and 21 streaming checks passed. The focused existing-instance restore observed 8.220 ms including test assertion/log overhead; this is not a controlled before/after benchmark. It does not fix first-load instantiation or the earlier 462 ms receive hitch. Evidence: evidence/vehicle_restore_reuse/.

## Seated F5 disk round trip - 2026-10-03

A full headless main-world test now routes F5 while the driver remains seated, waits for verified compound publication, closes without a shutdown re-save, and opens a fresh world instance from that file. Parked vehicle transform and saved player pose matched; the grounded player was within 6 mm of the saved position beside the car. A unique disposable slot is cleaned after the test. The first run incorrectly checked a restore buffer cleared after application; corrected to the retained saved record, with both logs retained. The passing run recorded a 462.06 ms receive hitch and up to 220.68 ms LOD scheduling during startup; these are unresolved loading costs, not a runtime 60 FPS qualification. Evidence: evidence/vehicle_seated_save/disk.log and disk_initial.log; fixture: tests/vehicle_seated_persistence.gd.

## Save while seated - 2026-10-03

F5 is now routed to world saving while driving. Player capture derives a clear, loaded on-foot position beside the vehicle using the same ground/capsule checks as exiting; the live driver stays seated. Reload remains parked/on foot, without velocity or cosmetic dents. If no valid nearby restore position exists, capture returns an invalid record to reject the compound save instead of silently saving an old distant player position. This also applies to automatic captures while seated. The fullscreen 1920x1080 main-world fixture verified valid nearby player encoding, rejection when vegetation collision is unavailable, continued driving and normal exit/UI restoration. It ran in temporary mode, so this increment verifies capture rather than a disk round trip; prior disk persistence evidence remains separate. Fifteen world interaction/storage regression checks also passed. Evidence: evidence/vehicle_seated_save/.

## High-speed chassis collision check - 2026-10-03

Six headless ballistic tests passed using the real vehicle chassis and native static collision proxies: a 0.1 m thick wall and a 0.7 m trunk, each at 30, 60 and 100 m/s (108, 216 and 360 km/h), 120 Hz, 40 ticks per case. Each reported physical contacts, remained on the incoming side and lost forward velocity. Continuous collision detection was already enabled in the supplied vehicle scene; no production physics setting changed. Driving logic, wheel forces, gravity and visual damage were disabled to isolate chassis collision. This does not qualify grazing impacts, penetration depth, terrain impacts, streaming at these speeds, active driving responses or rendered frame time. Evidence: evidence/vehicle_high_speed/collision.log; reproducible fixture: tests/vehicle_high_speed_collision.gd.

## Vehicle forest readiness lifecycle - 2026-10-03

Vehicle vegetation binding is now explicit and remains required after provider loss. A short headless test uses real native trunk collision to verify pending admission holds motion, publication restores velocity, moving a trunk invalidates stale readiness, republishing resumes, and tree removal leaves no hold. Rebinding while held is rejected. All 21 streaming checks and 15 world interaction/persistence checks passed. Logs are in evidence/trunk_collision/*forest_binding.log. These verify lifecycle correctness, not high-speed impact response or sustained performance.

## Nearby native trunk collision - 2026-10-03

Vegetation can now opt into native physics-only static batches: at most 256 nearby trunk proxies, 16 admissions per physics tick, within 96 m of the camera. No duplicate render batches or transform GPU buffers are allocated. Main-world walking, vehicle travel, placement and exit check trunk readiness. Local mining removal and chunk retirement remove collision too. Eleven targeted checks, 235 static placement checks, building collision streaming and vehicle integration regressions passed. The 1920x1080 fullscreen visual fixture passed driving and exit with simulated foreground input (4.044 m, 27.706 km/h). Initial visual run lost foreground behavior and did not move; retained alongside successful evidence. A repeated-input-event fixture warning was corrected with duplicate() after that run. Evidence: evidence/trunk_collision/. Simple box proxies approximate trunks; foliage has no collision. This is single-player focus streaming, not fleet or multiplayer coverage, and not sustained frame-rate or thermal proof. The building regression observed a 40 ms collision admission tick, still an outstanding spike.

## Vehicle pose persistence - 2026-10-03

The single world vehicle now participates in compound world saves through a native versioned 72-byte pose record. Older saves default to no vehicle; restored vehicles remain parked at rest. Invalid live captures reject the save and invalid restores retain the existing vehicle. Ten codec/archive checks, fifteen interaction/storage checks, a real worker disk publication/new-world restore and a temporary main-world startup passed. Evidence: evidence/vehicle_persistence/. The restore run recorded a 241.26 ms receive step while instantiating the detailed model; synchronous creation remains a loading hitch. Cosmetic dents, velocity and occupied-seat state are not persisted. Fleets and sustained frame/thermal performance remain incomplete.

## Native chase camera obstacle avoidance - 2026-10-03

Main-world chase follow now runs in C++ and uses a reusable sphere/query to shorten camera distance at terrain/building/vehicle colliders. Six focused physics checks passed: clear distance, wall stopping, repeated smoothing against wall, recovery after removal, invalid delta rejection and self-body exclusion. Fullscreen 1080p main-world placement/drive/exit/UI regression also passed; screenshot reviewed. Evidence: evidence/vehicle_camera/. Embedded anchors return failure with the previous camera pose retained, and vegetation without physics colliders is not covered. Persistence, fleets and sustained performance remain incomplete.

## Main-world vehicle visual integration check - 2026-10-03

Automated fullscreen 1080p test now exercises actual world placement, entry, a short straight drive, stopped exit and restoration of walking UI. Passing run travelled 4.044 m, reached 27.706 km/h and had 2,320 trees resident. Driving HUD now hides the editing toolbelt/crosshair, shows driving controls and reports speed or collision-loading status. Screenshot reviewed. Test explicitly stops the car before exit; braking dynamics are not proved by that step. Evidence: evidence/world_vehicle_visual/. This is integration evidence, not sustained FPS, fleet or thermal validation. Persistence and camera obstacle avoidance remain unfinished.

## Main-world vehicle controls - 2026-10-03

Added single session-only vehicle placement (V), nearby entry and clear stopped exit (E). Placement rejects unavailable/obstructed ground; exit uses a capsule clearance query and terrain/building readiness. Driving suspends walking/editing and owns terrain focus; occupant position supplies building/vegetation focus. Parked physics is suspended, and camera/player collision/physics rate are restored on exit. Nine interaction checks passed against real physics with controlled readiness providers; a short temporary main-world headless startup exited without script errors. Evidence: evidence/world_vehicle/. Full populated-world visual driving, persistence, door transitions, camera obstacle avoidance and fleets remain unverified/incomplete. No human playtest was run.

## Asynchronous vehicle terrain check - 2026-10-03

Added a short fullscreen 1080p integration check using TerrainWorld, its persistent worker, native road edits, real mesh/collision publication and the bound vehicle adapter. Passing run moved from z=404.914 to 455.808, reached 80.067 km/h, recorded 2 held ticks out of 480, and 125 worker builds. Screenshot inspected. No saved user world or derived cache is used. Evidence: evidence/vehicle_async_terrain/. The first run failed its 20-second initialization deadline; diagnostics were then added and the rerun passed without a loader fix. That startup reliability issue remains unresolved. This small road case does not establish large-world streaming, turning, populated scenes, sustained 60 FPS or thermal performance. Main-world player handoff remains unfinished.

## Vehicle on generated terrain: gravity integration fix - 2026-10-03

A short fullscreen 1080p generated-road drive exposed bottomed-out suspension: project gravity is 20, whereas the authored vehicle used default 9.8. Native suspension now scales stiffness and force caps with gravity and damping with its square root. Same test changed from FAIL (minimum body-origin clearance 0.124 m) to PASS (0.588 m), crossing z=416 and z=432 mesh boundaries, reaching 66.306 km/h with at least three loaded wheels on all 360 measured ticks. Eight suspension checks passed. Screenshot inspected; evidence in evidence/vehicle_terrain/. This uses actual native generated terrain triangles published synchronously, not asynchronous streaming or a populated world. Runtime gravity areas/mass changes, vehicle world handoff and sustained performance remain unverified.

## Vehicle reset and reload during streaming holds - 2026-10-03

Reset now discards retained momentum, including when invoked by the R key during a hold. Bound terrain reload holds without teleporting and clears drive speed, resuming at rest after readiness returns. Rebinding disconnects the previous reload signal. All 12 streaming checks passed, including injected reset input. Evidence updated in evidence/vehicle_streaming/. Main-world control handoff and actual streamed-world driving remain incomplete.

## Vehicle streaming adapter - 2026-10-03

The native demo vehicle now exposes optional streamed-world binding. It supplies terrain focus/travel velocity and checks terrain plus optional structure publication before/after control updates using native motion bounds. Missing readiness holds physics and retains momentum; ready publication resumes it. Eight targeted checks passed, including no drift over four physics steps and missing-provider handling. Evidence: evidence/vehicle_streaming/. These use real native readiness with controlled published-cell state, not a generated-world driving run. Main-world spawn/control handoff, smooth braking, reload/reset while held, and fleet focus remain incomplete.

## Directional terrain preloading - 2026-10-03

Native requests_travel adds up to four lookahead samples at no more than 32 m spacing, covering two seconds of horizontal travel capped at 128 m. Current-position requests remain included and retain activation priority. TerrainStream consumes travel_velocity; the walking controller now supplies intended velocity, including when movement is blocked. Brush targeting retains precedence. Eight targeted checks and all 179 planner regressions passed. Evidence: evidence/terrain_travel/. This establishes request planning only: actual delivery latency, turns, braking and vehicle/world control handoff still require integration and measurement.

## Terrain collision region readiness - 2026-10-03

TerrainStream.is_collision_region_ready now exposes a native all-cell bounds check over published fine collision columns. It requires every touched 16 m column, including the far boundary, and rejects nonfinite, negative-sized and out-of-world bounds. Published empty columns remain valid: this tests readiness, not solid ground. Ten targeted boundary/input cases and all 179 existing terrain planner checks passed. Evidence: evidence/terrain_collision_region/. This is an integration prerequisite; the vehicle demo does not yet call it, predictive loading/braking is not implemented, and no high-speed streamed-world claim is made.

## Native vehicle accessory motion - 2026-10-03

Eleven mounted accessory springs now use native state, cached spring coefficients and one adapter call per physics tick. Disabled animation resets transforms once instead of every tick. A 600-tick comparison at 120/60 Hz, including toggles and reset, matched original mount transforms exactly; deleted-node handling and mismatched configuration were exercised. The short fullscreen 1080p Forward+ smoke drive also passed; screenshot inspected. Evidence: evidence/vehicle_accessories/. Fleet LOD, world integration and sustained performance remain incomplete.

## Native vehicle cosmetic damage - 2026-10-03

Crash dent vertex work now runs in NativeVehicleDamage, with conservative bounds rejection and copy-on-write vertex changes. Original scripts still orchestrate damage events and repair. A short headless comparison matched 6,266 vertices on 10 damageable meshes exactly, preserved source vertices/materials, and rejected distant/zero-radius impacts. One sample measured native 1,504 us versus script 3,257 us; this is not a fleet or sustained-performance result. Evidence: evidence/vehicle_damage/vehicle_damage.log. Static ArrayMesh only; original normals are retained and mesh upload remains synchronous.

## Vehicle native motion migration — 2026-10-03

Grounded bicycle velocity, free-mode drive/brake forces, stabilization and downforce now run in C++. Original mode transitions and visual/interaction scripts remain scripted. This is an isolated vehicle demo, not streamed-world integration.

Validation: 3,600 steering/speed comparisons, 240 grounded-motion comparisons (maximum observed error 0), five suspension checks, and a short 1920x1080 fullscreen Forward+ drive at a 60 FPS cap and 120 Hz physics. Drive reached 49.019 km/h over 14.7135 m with four loaded wheels. Screenshot inspected. Evidence: vidence/vehicle_motion/. Free-mode impact/airborne trajectories, fleet scaling, sustained frame timing and thermals are not proven by these checks.

# Original objective and completion evidence

## Current delivery priority

Vehicle suspension/contact sampling now runs in NativeVehicleSuspension with
the original spring, damping, travel and force cap. The native pass updates four
rays once per tick; automatic ray updates are disabled and effects/telemetry
reuse those contacts. Five targeted support/force-limit/input checks pass. The
1080p automated drive remains close to the pre-port result (14.7136 m, 49.0202
km/h, four loaded wheels). Both binaries rebuilt; evidence:
`evidence/vehicle_suspension/`. A small script adapter still copies contact data;
motion modes, impacts, effects, fleet activation and streamed-world integration
remain unfinished. No fleet performance claim follows from this single-car test.

The user's own vehicle project is imported under `vehicle_demo`, with their
explicit 0BSD declaration recorded in PROVENANCE.md. NativeDrivingPolicy ports
its steering and longitudinal control rather than substituting the earlier
simple controller. 3,600 original-script comparisons at 60/120 Hz pass with
maximum errors below 1e-6 radians and 1e-5 m/s. A short automated 1920x1080
Forward+ drive at the original 120 Hz physics travelled 14.7 m and reached
49 km/h with four loaded wheels. Both native binaries built; evidence is in
`evidence/vehicle_adoption/`. Launch Vehicle Demo.cmd imports and launches the
isolated comparison scene. Suspension, impacts, damage and accessory runtime
remain scripted; native migration, world collision streaming, vehicle storage,
fleet activation and multiplayer integration remain required work.

Native entity ticks now iterate only a preallocated dense list of nonzero-velocity
entities instead of scanning the entire live population twice. Spawn, velocity
changes, despawn and restore maintain membership; spatial queries and snapshots
still include stationary entities. The 100,000-stationary fixture visits zero
slots per tick; a mixed 100,003 population visits its three movers. Thirteen new
lifecycle/scaling/overflow checks and 54 spatial/storage/identity regressions
pass. Both world-runtime binaries rebuilt. Evidence: `evidence/entity_sleeping/`.
This reduces CPU kinematic work only; physics contacts, AI, animations, entity
paging, rendering cost and multiplayer simulation remain separate requirements.

Road collision now has a targeted capsule traversal check. A native graded cut
through a solid hill is meshed across adjacent 16 m regions; its native face
arrays drive a Godot concave collider and the existing player capsule/movement.
Six checks pass for construction, triangles, uphill traversal, continuous floor
support, grade at the shared edge and downhill return. The uphill sample kept
floor contact for all 140 measured ticks. Evidence: `evidence/road_traversal/`.
This bypasses asynchronous collider publication and does not qualify streaming,
vehicles, road joins or long-run frame performance.

Roads now support an optional native clearance cut (0 disables; maximum 16 m)
in the same density edit as bed construction. The editor exposes it, includes
it in the outline, and protects player/building bounds throughout that height.
The cut follows the graded rounded corridor; material outside the pavement
retains its substrate. Terrain above the cap remains, allowing a tunnel rather
than guaranteeing an open cutting. Both terrain binaries rebuilt. Twenty-four
native checks and fifteen world-editor checks pass; evidence and a 1920x1080
guide capture are in `evidence/road_clearance_cut/`. Terrain undo, vegetation
policy, road-network joins, collision traversal and scale qualification remain.

Road editor aiming now uses the combined native structure/physics ray, rejecting
building hits rather than marking terrain through them. Submission checks the
native block/model overlap mask and rejects unavailable building regions.
The road bounding box plus 0.5 m margin is conservative, particularly on diagonal
routes; this is not exact capsule clearance. Fifteen world checks pass, including
a building inserted before collider publication and removed before acceptance.
Evidence: `evidence/road_structure_clearance/`. This is an editor admission rule,
not a cross-system transaction or multiplayer authority guarantee.

Road selection now has a bounded editor outline showing rounded ends, grade,
width and depth. It rebuilds on selection/dimension changes only, has no
collision or shadows, and hides outside terrain editing or during loading and
inventory use. Green means parameter-valid, not obstacle-free; red indicates
incomplete/invalid selection. Thirteen world checks pass, including aimed
selection, player protection, color changes and no rebuild while unchanged.
The 1920x1080 screenshot in `evidence/road_preview/` isolates the guide at the
selected distant coordinates; it is not evidence of terrain publication there.

The terrain-mode road panel now marks two aimed collision-surface points,
configures half-width/depth and submits the native road command. Release the
mouse with Esc while using a terrain tool to see the panel. Grade/length/world
boundary validation gives feedback; inventory, loading, focus and mode gates
apply; a conservative player-overlap box prevents building around the player.
Selection is temporary; accepted density edits use normal world saving. This
is an initial authoring interface: hill cutting, terrain undo,
network authority and vegetation-clearing policy remain unfinished.

Fixed a rendering regression introduced by asphalt commit `43cf536`: extracting
weight with `fract(UV2.y)` wrapped interpolated LOD integers slightly below their
exact value to nearly full asphalt. Untouched terrain acquired noisy dark pixels
and bands. Decode now subtracts the nearest integer before clamping. The same
1920x1080 Forward+ fixture visibly loses the speckling with only this shader
change; before/after captures are in `evidence/asphalt_weight_fix/`. The earlier
shader-error-free render was insufficient validation and its visible noise was
missed. World data and native binaries are unchanged by this fix.

Native graded road-bed construction is available through
`TerrainWorld.construct_road_bed(a, b, half_width, depth)`. It unions a rounded
road footprint with a graded top into existing terrain density, using asphalt
and the existing worker, meshing and snapshot paths. Both terrain binaries
rebuilt; sixteen short headless checks pass for geometry, input rejection,
idempotence, snapshot restoration, mining, meshing and worker completion.
Asphalt uses saved material ID 4 and continuous native vertex weights; the
shader reuses the existing aggregate texture without overlay geometry. A short
1920x1080 fullscreen Forward+ render passed without shader errors. Its isolated
floating segment validates appearance only, not road placement in a world.
Evidence: `evidence/terrain_road_bed/`. This raises terrain only: hill cutting,
road editor/network tools, surface polish and large-scale performance are
not implemented or certified by these checks. Segments are limited to 128 m,
half-width 0.5–16 m, depth 1–8 m and grade at most 25 percent.

Actual capsule traversal exposed a missing walking behavior: `move_and_slide`
alone stopped at the first quarter-metre stair riser. NativePlayerMovement now
provides a bounded 0.3 m step-up operation, used by the walking controller after
collision-readiness checks; building readiness bounds include raised headroom.
It tests obstacle, overhead clearance, raised travel and landing, with an extra
support ray when the capsule's rounded corner normal obscures a flat tread.
Six physics checks pass for native tower collision, ascent, descent, tall-wall
rejection and low-ceiling rejection; twenty movement-policy regressions pass.
Both player binaries rebuilt. Evidence: `evidence/tower_traversal/`, including
the original first-riser failure. The helper targets the existing upright 0.34 m
radius capsule; arbitrary body shapes/up axes, moving platforms and network
prediction are unqualified. This is not a complete locomotion certification.

Stacked tower-floor alignment is corrected. The original module reaches five
metres in bounds but is designed for a four-metre repeat pitch; using bounds
introduced a landing-height gap. The asset/generator now record explicit
`stack_height=4`, and the library preserves combined pitch in saved assemblies.
Eighteen infill cells were removed because repeated solid stair undersides blocked
headroom below. Six native-geometry checks pass: exact quarter-step heights and
landing continuity, 1.85 m vertical clearance across three flights, persistence
of pitch and invalid-pitch rejection. Evidence: `evidence/tower_connectivity/`.
These are geometric ray checks, not a completed player capsule traversal or
navigation test. Existing placed buildings/personal assets are not rewritten.

The construction editor now exposes **Stack selected prefab**, with a name and
2–32 repeat count. It saves/selects the native assembly through the existing
personal library. Twenty-one library checks and fourteen actual-world checks
pass, including a four-floor assembly, exact library reload and invalid-name
rejection. A separate 1080p panel check verifies layout after widening the
initially clipped count field. Evidence: `evidence/prefab_stack_editor/`.
One full-world attempt missed the 30-second startup deadline before the editor
test; the next completed. Startup variability remains unresolved. Stacking is
authoring, not automatic stair connectivity, roofs or terrain foundations.

Native prefab composition now assembles translated/quarter-turned modules into
one ordinary `NativeBlockPrefab`, preserving material and shape rotation and
rejecting overlaps, invalid inputs and cell/coordinate limits atomically. Seventeen
focused checks pass, including normal world placement, self-source composition,
source immutability and exact resource reload. Sixteen authored tower-floor
modules produced 6,368 cells (one observed composition call: 1.575 ms). This is
synchronous authoring and a flattened asset, not live hierarchical instancing,
terrain grading, connected navigation or settlement generation. No city rendering
performance follows from this test. Evidence: `evidence/prefab_composition/`.

Pickup persistence now has direct disk evidence. The terrain-owned save worker
published authored supplies, fresh provider instances reloaded their identities
and positions, and a second verified save/reopen retained a collected material
in inventory without respawning its supply. An uncollected second material
survived both reloads. A malformed pickup section with a valid outer archive
checksum was rejected before world readiness, with subsequent saving disabled
to protect the original file. The headless test pauses mesh streaming and uses
an isolated temporary save slot; this does not measure live-game save hitches.
Evidence: `evidence/material_pickup_persistence/`; executable coverage:
`tests/material_pickup_persistence.gd`.

The construction palette now authors brick, wood, concrete and metal supplies
through a material selector and **Place supply at aim** action. Placement checks
support normal, building-collision readiness, physical obstruction and existing
supplies. The actual-world test exercises the button and overlap rejection;
the expanded panel is checked after Godot layout and visually at 1920×1080.
These supplies join existing compound-save sections. They remain editor-authored
free placements; block undo/redo does not affect them, and physical settling and
survival costs are unfinished. Evidence: `evidence/material_pickup_editor/`.

Material pickups now connect the entity stores/renderers to the actual world and
player inventory. Four static authored supply types register compound-save
sections; E collects a reachable supply within 2.5 m while walking. Collection
checks terrain/building obstruction, focus, inventory modality and stack capacity.
Inventory shows quantities and cannot equip materials as tools. Eleven addon
lifecycle checks and eight actual-world checks pass, with the 1920×1080 fullscreen
inventory capture inspected. Compound provider tests cover inventory/pickup restore
together; this turn did not repeat on-disk save testing. Evidence:
`evidence/material_pickups/`. The first default-generator world fixture exceeded
its 30-second startup deadline; profile 2 seed 1703 completed the integration test.
That default-profile startup issue remains unqualified. Automated input explicitly
sets the focus state and also verifies unfocused rejection.

Pickups are authored through the addon API, not automatically seeded or produced
by demolition. Editor undo/redo remains separate to avoid loot duplication.
Placement UI, settling, build-cost consumption, region paging and authoritative
multiplayer collection remain missing. Rendering limits are exposed through
`render_status`; dense query overload rejects collection with an explicit notice.

Entities now have store-local persistent identities separate from runtime handles.
Version 2 snapshots retain IDs and their allocation cursor; version 1 still loads
with deterministic migrated identities. Twelve identity checks pass, along with
19 storage and 23 spatial regression checks. Duplicate/cursor-invalid IDs reject
atomically; exhausted IDs cannot wrap; deleted IDs no longer resolve. Evidence:
`evidence/entity_identity/`. This supplies saved-reference resolution, not network
authority or globally unique IDs. Loading an older save rolls back the identity
timeline. Identity-index allocation overhead is outside the pool byte counter.

Native entity positions and velocities now have a versioned storage codec that
registers with the existing compound world-save provider. Nineteen focused checks
pass, including exact 99,999-row round trip, malformed-input atomic rejection,
fresh runtime handles, spatial-index reconstruction, restored motion and archive
corruption detection. Both native binaries rebuilt; evidence is in
`evidence/entity_storage/`. This is provider-level integration, not yet a saved
gameplay population in the demo. Persistent gameplay IDs, archetypes and region
paging are still missing. Whole-population restore stages a second pool and runs
synchronously; it is not a bounded per-frame streaming operation.

Feature delivery remains the priority; laptop thermal feasibility is unproven
and is not a prerequisite for continuing planned functionality. The 60 FPS,
1920×1080 target remains unchanged.

`NativeEntityRenderer` now connects spatial entity queries to a fixed-capacity
MultiMesh in C++. Thirteen focused checks pass, including movement, generation
reuse, invalid queries, dense-region limits and external resource mutation.
A short 1920×1080 fullscreen Vulkan run displayed 49 nearby instances from a
100,000-entity store, visited 256 candidates and uploaded 6,144 bytes at configured
capacity 128. The captured image was inspected. Both native binaries rebuilt
against the existing prebuilt SDK. Evidence: `evidence/entity_renderer/`.
This is a reusable addon adapter, not yet gameplay-world entity integration or
a sustained performance result. It has one shared mesh, translation-only poses,
aggregate culling and explicit truncation rather than nearest-first admission.
Collision, animation, replication and world orchestration remain unfinished.

The native entity store now maintains a 32-unit spatial index and exposes bounded
sphere queries, with explicit incomplete results for candidate/output limits.
Movement across cells, despawn and generation-checked slot reuse update the index.
Twenty-three targeted checks pass, including exhaustive-query comparisons after
movement and negative-coordinate crossings. Local queries inspected four candidates
both at 1,024 and 100,000 entities (one observed call: 19/26 microseconds). Dense
10,000-entity neighborhoods stopped at requested budgets and reported truncation.
The existing 18 runtime checks pass; 240 ticks over 100,000 moving entities measured
3.104 ms median, 4.252 ms p95 and 5.139 ms maximum with index maintenance included.
Evidence: `evidence/entity_spatial/`. These are CPU-only data/kinematics checks.
Gameplay entities, rendering admission, collisions and replication still need
integration; this API is not a completed large-entity game system. Hash-map cells
allocate on demand, and their overhead is not included in the pool byte counter.

Vegetation placement now consults the native water catalog. Each published lake
stores a one-byte-per-horizontal-cell water-column index; bounded batches of up
to 512 roots query at most 16 lakes in C++, without per-root vertical scans.
The optional ecosystem coordinator reconciles only owners intersecting changed
lake bounds and preserves unchanged renderer rows. Removing a lake restores the
original candidate IDs; built terrain and dry/disconnected root locations are
not removed by a blanket rectangular exclusion. Twelve focused native/coordinator
checks pass, along with the existing 45 water and 17 shoreline checks. The real
generated-lake scene also passes four integration checks. Both water binaries
were rebuilt with the prebuilt SDK. Query-index bytes are reported separately
from occupancy and surface bytes. The visual sub-cell shore margin still differs
from conservative occupancy, and population-scale forest/water costs remain
unqualified; this is not proof of complete vegetation support for every biome.

Correction to the repeated **3 FPS construction screenshots** below: direct
instrumentation measured 964–972 ms of synchronous PNG encoding/writing per
screenshot, plus 13–14 ms of GPU readback. The test captured three images during
interaction. Those HUD values were contaminated by test I/O and must not be used
as runtime FPS evidence. A separate 120-frame stationary sample, with streaming
enabled and no capture I/O, averaged 60.0006 FPS (p95 16.748 ms, max 16.797 ms).
The construction test now keeps three image readbacks in memory and defers PNG
encoding until after scene shutdown. All 27 interaction checks still pass; the
repeat sample averaged 60.0026 FPS (p95 16.942 ms, max 17.670 ms). Evidence:
`evidence/construction_observer/before_deferral.json` and `after_deferral.json`.
These roughly two-second stationary samples do not qualify mining/travel,
dense-city rendering or endurance, and do not explain unrelated lake FPS readings.

The construction palette now supports archiving personal prefabs and restoring
the latest archived prefab. Archive moves the original file into a separate
library subdirectory, preserves its bytes and removes it from active selection;
placed blocks are independent and remain intact. Restore works after reopening
the library. Built-in assets cannot be archived, and destination collisions or
I/O failures retain existing files. Eighteen library checks and 27 scene interaction
checks pass, including exact byte restoration and palette synchronization.
The 1080p screenshot was inspected; its 3 FPS HUD reading is not a performance
pass. Archive browsing, renaming and combined block/model prefabs remain open.

Lake rendering now uses a native clipped shoreline built from the density samples
at fill elevation. Connected surface triangles stop at solid contours; fully wet
interiors still merge into rectangles. If sub-cell connectivity reaches the volume
boundary, rendering falls back to the conservative contained surface. Geometry is
built during the worker bake, retained as packed arrays, and copied safely on read;
the 3D density scratch is released. `surface_bytes` reports retained geometry
separately from occupancy bytes. Seventeen shoreline checks, all 45 existing water
checks and 80 generated-basin checks pass. Both native build configurations pass.
The four-check 1080p scene run completed in 9.738 seconds; visual inspection shows
the circular lake's staircase edge removed. Evidence is in
`evidence/generated_lakes/smooth_shoreline/`. The screenshot HUD reads 41 FPS;
this functional check does not establish sustained 60 FPS or rendering-cost parity.
Swimming/containment still uses conservative occupied cells, so the visual contour
can extend into the narrow shore margin reported dry by occupancy queries. Exact
shoreline interaction, varied natural basin shapes and finished water art remain open.

Lake scheduling now admits one outstanding builder reservation instead of
rejecting all lake requests whenever terrain has more than four queued jobs.
Read-only water slices may advance between background terrain owners without
crossing mutation/save/load/unknown barriers. Native sampling retains its 2 ms
yield and admits up to 2,048 points per slice; final flood fill remains bounded
by volume size, not that sampling time budget. Eleven scheduling checks pass,
including real signed Godot instance IDs and reservation retention through poll.
The compound lake persistence/reset test passes again.

The graphical fixture previously let the world overwrite its requested spawn,
then directly moved the camera to unloaded terrain. It now uses normal destination
loading and verifies arrival. The corrected run reached terrain plus nearby lake
readiness in 9.923 seconds, with 49 completed slices, and passed all four checks.
The screenshot shows the basin and water surface together; stepped shores remain.
Evidence: `evidence/generated_lakes/after_scheduling.log`. This is one short
functional observation, not a matched timing comparison against the flawed
fixture or proof of sustained 60 FPS. The earlier all-lakes deadline failure and
remaining water visual/streaming/cache requirements stay recorded below.

Generator 4 adds four deterministic closed lake basins to the mountains/caves/ore
profile. Native command 27 supplies bounded lake definitions; new-world and reset
initialization encode them through the registered water catalog. Normal load uses
the saved catalog, so deleted lakes stay deleted. `Play Lake World.cmd` selects
profile 4 in its own save slot. Profiles 1–3 remain available and unchanged.
Both native configurations build with the pinned prebuilt SDK. Eighty checks over
four seeds verify contained water, generated surfaces and terrain save identity;
11 compound persistence checks cover automatic baking, deletion, reload and reset.
The previous generator compatibility/cave/geology tests also pass.

Rendered validation remains incomplete: one full-scene run completed all four
lakes, a later run completed only two within 50 seconds, and the focused nearby
lake test failed its shorter 25-second readiness deadline. Retained failure:
`evidence/generated_lakes/all_lakes_scene_deadline.log`. Screenshot inspection
confirmed a basin/surface but showed a visibly stepped shoreline and 15 FPS on
that frame. Worker slice scheduling under terrain streaming, smooth shores,
vegetation/water exclusion and persistent water bake caching remain open. These
generated lakes are available for development, not qualified for release. They
use existing static connected occupancy, not dynamic pressure/flow simulation.

`tests/prefab_building.gd` adds a short headless 16-storey authoring check:
78,624 occupied cells in a 64x64x64 selection (the native maximum selection
volume), with floors, windowed walls and stairs. Thirteen checks pass: exact disk
roundtrip, every rotated placed cell, overlap rejection without mutation, full
undo/redo snapshot equality and oversized-selection rejection. One recorded run
took 18.639 ms for native capture, 46.992 ms for capture plus synchronous saving,
5.035 ms to reload, 14.090 ms for placement, 7.285 ms undo and 6.895 ms redo.
The saved asset was 1,258,302 bytes. Evidence is retained in
`evidence/prefab_building/native_authoring.json`. These are individual operation
observations, not latency percentiles. Large capture/save currently exceeds a
16.67 ms frame budget and can hitch. No meshing, collision cooking or rendering
was included; city FPS and large-building authoring responsiveness remain open.

Prefab capture now has a selection-volume outline, distinct corner markers,
`[` / `]` aim shortcuts and a Clear action. Feedback uses three shared-mesh line
instances regardless of selection size; geometry changes only when selection
changes. Oversized bounds are red and labelled before capture. Eleven library
checks and 24 construction interaction checks pass, including actual corner-key
events, exact inclusive bounds, inventory visibility and clearing. Screenshot
inspection confirmed the UI, but its HUD displayed 3 FPS: this functional run is
not performance qualification and does not resolve existing frame stalls. The
cause of that displayed reading was not isolated in this test.

Construction now exposes native block-prefab capture through two aimed corners
and a named save action. The structures addon keeps a shared local library under
`user://building_prefabs`, loading up to 32 assets, and immediately selects captured
prefabs for the existing rotated placement/undo workflow. Capture traverses cells
in C++, refuses unavailable regions and oversized selections, and preserves the
source world. Ten short library checks cover disk reopen, exact records, rotated
placement and invalid selections. The 19-check fullscreen construction test passes
with corner capture and palette selection; its screenshot was inspected. This is
block-only authoring: model-inclusive prefabs, library management and
large-building authoring latency remain unfinished. The
library is separate from world saves, including when capturing from temporary worlds.

Feature delivery takes priority over further speculative thermal optimization.
1920x1080 fullscreen at a 60 FPS target remains the requirement; sustained laptop
thermal feasibility and the deferred mining failure are not declared resolved.

`Play Generated World.cmd` launches generator 3, seed 1703, in the separate
`generated_g3_s1703` save slot. `python tools/run.py --generator 3 --seed 42`
automatically selects another slot; `--slot campaign` explicitly selects a named
save, and existing saves retain their own generator/seed. `--temporary` disables
persistence and `--dry-run` prints the launch command without starting Godot.
The launcher requests 1920x1080 fullscreen and caps at 60 FPS. Focused command
checks cover default/profile/custom slots, zero seed, invalid seeds, path traversal
and raw argument override rejection. These checks do not measure runtime FPS.

Generator audit: current terrain remains a fixed 2000x256x2000 domain. Generator 1
preserves seeded height noise and hard-coded mountain/cave landmarks. Generator 2
adds four seed-derived mountain groups and four connected cave networks represented
by 20 canonical capsules, with tunnels and larger chambers. Select it for new worlds
with `--world-generator=2 --world-seed=2468` after Godot's `--` separator. Existing
saves always determine their own profile; the default remains generator 1. Legacy
base-mesh assets are disabled for profile 2. Twelve native profile checks cover cave
interiors, determinism, cache separation and save restoration; compound persistence
also checks profile/seed survival. Broader biome generation, configurable
world bounds and large-world scaling remain unfinished.

Generator 3 retains profile 2's landscape and adds seeded iron/copper capsules in
32 m geological cells. Native material queries expose stable IDs 8/9 and signed
continuous vein weights; excavation preserves natural material IDs in edited pages.
Rendering blends the weights with exposed rock, while existing placed edit materials
remain separate. Select new worlds with `--world-generator=3`. Nine geology checks
cover discovery, repeatability, mining, save/reload, mesh weights and actual shader
rendering; the full scene test also passes for profile 3. Ore art is preliminary,
mining rewards and a configurable material registry are unfinished, and distant LOD
preservation of thin veins has not been validated. This does not establish large-world
scalability. Profiles 1 and 2 retain their earlier material field.

Terrain saves now write format 2 with explicit generator
ID; format-1 saves are read as generator 1. Unknown generator IDs are rejected
before state replacement. Geometry content keys include generator identity. Future
generator versions must preserve an implementation for old worlds rather than
merely changing this constant. Older application binaries cannot read format-2
saves. Eight focused compatibility checks and compound save/reopen checks pass.

Player tool switching now shares one transition across the toolbelt and legacy
terrain/building/object shortcuts, with active-tool feedback and explicit brush
suppression while inventory is open. `tests/player_hud_smoke.gd` exercises actual
key events for these routes at 1920x1080. Its pending-edit switch check injects
the pending flag; it does not prove concurrent edit completion. This is input
integration, not the completed native interaction/authority system.

`NativePlayerMovement` now computes walking velocity, gravity/jump and flight
displacement for the controller. It rejects nonfinite inputs and timesteps outside
(0, 0.25] seconds. Scene orchestration, collision readiness checks and Godot
`move_and_slide` remain in the controller; the full player redesign is incomplete.
Fourteen native behavior checks pass, including bounded diagonal speed, release,
gravity and invalid inputs. The 1080p scene test also checks flight motion and
stopping. These checks do not establish an FPS improvement, multiplayer prediction,
or exhaustive walking/collision behavior.

Player swimming now uses a chest-depth query against baked lake occupancy and
native bounded swim targets, drag and passive buoyancy. Space ascends; Ctrl dives.
Godot collision and terrain/building readiness still gate movement. Twenty native
movement checks pass, including swimming, and the graphical water integration test
checks submerged ascent and a dry query after leaving the volume. Entry/exit motion,
shoreline traversal, underwater visuals, breathing and networking need further work.
The current lake lookup still scans lake bounds in GDScript; this is not evidence of
scalability to many resident lakes. The water test now keeps 60 FPS/VSync instead of
its earlier uncapped measurement phase.

The water addon now supplies a camera-local underwater environment using ordinary
depth fog. It reuses the environment during steady immersion, restores the previous
camera environment on exit/invalidation/removal, and leaves shared scene resources
unchanged. Seven lifecycle checks and the real-lake graphical test pass; the
underwater screenshot was inspected. This is basic visibility feedback, not finished
underwater art, sound, surface optics or a measured rendering-cost improvement.

Player position, yaw/pitch, flight mode and active tool category now have a 56-byte
native validated `player_pose` section in compound saves. Missing sections retain
default spawn behavior. Restoring a pose goes through destination loading and
collision readiness; capture during loading retains the previous saved pose rather
than saving the temporary staging position. Fifteen codec checks, a disk save/reopen
check and a graphical restore-through-readiness check pass. Individual terrain
brush variants, construction shape/material settings and player attributes are not
yet persisted. This remains a single local player record, not multiplayer identity
or authoritative player-state storage.

The structures addon includes a construction palette for six block shapes, four
materials, quarter-turn rotation and the registered prefabs. It appears in block
mode; Esc releases the mouse for selection. Keyboard selection synchronizes the
palette, and prefabs disable shape/material overrides they do not support. The
1080p smoke test checks selection signals, mode visibility and keyboard sync;
the screenshot was inspected. This adds access to existing native construction
operations; it does not prove large-city throughput or mouse-click placement.

`tests/construction_interaction.gd` now adds a separate ten-check real-scene
interaction test at 1920x1080 fullscreen: native support targeting, palette-selected
wood stairs rotated 90 degrees, injected RMB placement and LMB removal, exact
undo/redo and inventory click isolation. All checks pass and the screenshot was
inspected. Palette selection in this test uses its signals, while placement/removal
use input events. This verifies the small building interaction, not city-scale load.

Individual blocks now share the existing bounded preview renderer: a cell outline
updates at 10 Hz, with player-overlap color driven by the same check as placement.
This outlines the occupied cell, not the detailed selected shape. Inventory and
released mouse hide the preview. The expanded construction interaction test passes
15 checks, including exact preview cell, red overlap and rejection; its preview
screenshot was inspected.

Single-block placement additionally shows a translucent shape preview from the
native building mesher. Its per-world cache is bounded to 24 shape/rotation meshes;
material changes reuse geometry. `tests/structure_preview.gd` verifies all 24
combinations against placed-block vertices/normals/indices, cache reuse and absence
of world edits. The 16-check scene interaction test passes and the stair-preview
screenshot was inspected. No city-scale or rendering-cost claim follows from this.

Resume planned gameplay work: player, toolbelt, inventory and unified interaction,
followed by water/lakes, generator/material veins, roads and settlements. Preserve
the full requirement matrix below. New hot-path rules belong in native addons;
UI and scene wiring may remain in GDScript. Multiplayer authority and persistent
player state remain explicit requirements, not claims implied by a local UI.

**Deferred, not forgotten:** the arrival-frame hitch and sustained laptop power/
thermal qualification remain open. The latest short mining workload produced
maximum visible-change gaps of 137.616/103.745 ms, but a 52.49 ms arrival frame
still failed the overall gate. Evidence: `evidence/mining_flight_failure/cooperative_local_build/`.
This is two three-second holds, not endurance qualification. Reopen immediately
for progressive slowdown, repeated normal-play stalls, incorrect terrain or
vegetation loss; otherwise review before release without blocking all feature work.

The target remains **1920x1080 fullscreen, 60 FPS**. No 30 FPS fallback was added.
Laptop thermal feasibility is unproven. GPU utilization is not a power or thermal
budget; future evaluation must record GPU frame time, watts, temperature and
throttling under matched workloads. Do not pursue iGPU delegation or speculative
GPU optimization as the next milestone.

The entries below describe earlier stages and retain their original limitations.

Repeated edits now preserve unaffected queued terrain jobs and atomically
advance a bounded set of requested fine children. In the corrected 2,176-command
run, original/return median latency is 20.4/20.7 ms. Travel p95 is still 451 ms,
so the foundation remains unqualified. See [refinement progress and observer
correction](TERRAIN_REFINEMENT_PROGRESS.md).

Integrated mining pressure now rejects the foundation at 136, 544 and 2,176
edits. The largest original run reaches 452 ms edit publication;
patch tracing identifies expensive coarse-LOD rebuilds for small edits. See
[measured failures](FOUNDATION_MINING_RESULTS.md) and the
[qualification matrix](FOUNDATION_QUALIFICATION.md). These are open failures,
not an accepted performance baseline.

The original large boundary-frame stall figures are withdrawn as game evidence:
full synchronous benchmark checkpoints caused substantial observer overhead.
The harness now retains only compact progress during capture and writes detailed
traces after capture stops. Original artifacts are preserved with this correction.

Foundation work now replaces column-wide forest clearing after mining with
bounded native surface-support revalidation and preserves unchanged tree renderer
rows. See [localized vegetation support](FOUNDATION_VEGETATION_SUPPORT.md).
This fixes a correctness defect; sustained combined-world performance and
progressively slower mining remain unqualified.

The native mesh cache now uploads bounded batches. A 16-tower / 8-cottage
fullscreen district returned from cache in 0.536 s versus 4.267 s before, with
exactly preserved texture mipmaps and authored data. See
[dense building rendering](DENSE_BUILDING_RENDERING.md). Cold startup spikes,
combined-world city density and endurance remain open.

Dense native paging now covers 4,096 authored chunks across 256 travel arrivals
under a 512-chunk resident budget. It exposed and fixed destination starvation
after pressure eviction; see [pressure regression](REGION_PAGER_PRESSURE.md).
This is cell-storage evidence, not a rendered-city or endurance result.

The persistent main world now uses a native building-region pager for automatic
nearby admission and safe distant eviction. It retains unsaved edits and undo/redo
history, rejects stale read results, and saves partially resident worlds. See
[native region paging](NATIVE_REGION_PAGING.md). City-scale latency and memory,
high-speed readiness and multi-hour endurance remain unverified.

Opt-in metadata-first archive loading now restores region availability without
reconstructing all block cells, and preserves checkpoint identity through later
saves. See [metadata world loading](METADATA_WORLD_LOADING.md). The persistent
main demo now enables metadata loading and bounded automatic region admission.

Fresh block worlds can now initialize checkpoint availability metadata without
loading cell chunks; see [region bootstrap](BLOCK_REGION_BOOTSTRAP.md). Partial
saving and automatic building paging are now connected to the main world.

The main world now publishes block-region checkpoint references through a native
archive adapter, retaining current and backup roots. See [region-backed world saves](REGION_WORLD_ARCHIVE.md).
Legacy full-resident restore limits remain; metadata loading avoids reconstructing
all building cells at startup.

Persistent native catalog checkpoints now preserve referenced block versions through
future edits and collection. See BLOCK_REGION_CHECKPOINTS.md. World-root integration is covered by REGION_WORLD_ARCHIVE.md.

NativeBlockRegionIO now runs disk catalog work on one persistent C++ worker,
bounding queued, active and unread-completion reservations. See BLOCK_REGION_IO.md.
The main pager uses the archive's shared reader instead of opening a second store
owner; see [archive region reads](ARCHIVE_REGION_READS.md).

Authored block regions now support bounded native capture, conditional unload
and reload, availability-aware walking/editing/exclusion, and refusal of legacy
whole-world saves that would omit unloaded data. See BLOCK_REGION_TRANSFERS.md.
A native disk catalog now provides conditional batch publication and explicit
backup recovery; see BLOCK_REGION_CATALOG.md. Automatic block travel paging is
connected; authored static-model region storage remains unfinished.

Walking now checks native block and static-model collision readiness within conservative capsule
travel bounds before moving, and waits without accumulating motion when an
authored surface is unavailable. See BUILDING_MOVEMENT_READINESS.md and
STATIC_MODEL_READINESS.md. Vehicle paths, multiplayer authority and the native player redesign
remain separate unfinished requirements.

Dense building collision now uses 1,024-triangle pieces, incremental retirement
and explicit readiness instead of the measured ~1.3-second whole-chunk creation
path. See BUILDING_COLLISION_STREAMING.md and the retained baseline in
BUILDING_COLLISION_PROFILE.md. Dense chunks still need many ticks to become
ready; vehicle readiness and physics memory budgets remain open.

Block worlds now reuse one sleeping native bake worker instead of creating a
thread per chunk. Lifecycle, stale-result and shutdown tests are documented in
BLOCK_WORKER_VALIDATION.md; multi-hour endurance remains outstanding.

Native block baking now uses exact shape-dependent scratch grids instead of
quarter-cell expansion for every chunk. Seven legacy mesh fingerprints match,
including cross-chunk partial shapes; see BLOCK_LATTICE_VALIDATION.md. This
reduces cube/slab bake work while building LOD and authored model-region storage remain open.

Terrain collision slicing, validation and cache-key preparation now run in a
native worker recipe API. Main-thread shape matching, cooking and node attachment
are measured separately; see TERRAIN_COLLISION_VALIDATION.md. Physics cooking is
still non-preemptible, and long-run/high-speed collision readiness remains open.

Native authored-cell picking supports block editing and model placement without
waiting for block mesh/collision admission. See BLOCK_PICKING_VALIDATION.md.
Player/vehicle collision readiness and model collision residency remain separate
outstanding work.

The original scope remains active. This project must not be called fully game-ready based on the implemented subset below. Each remaining item needs working implementation and evidence at its actual scope, not merely a class, API stub or narrow benchmark.

| Requested outcome | Current state | Evidence still needed for completion |
| --- | --- | --- |
| New combined project; terrain and forest as modular addons | Implemented integration; source folders preserved | Final full-support matrix and release verification after all changes |
| Professional architecture, visuals, resilient long runs and performance headroom | Bounded placement/worker queues, lifecycle tests and short graphical runs; old 120-cycle travel evidence | Multi-hour current-build endurance, measured memory/VRAM/latency tails, matched baselines and visual refinement |
| Volumetric water and lakes | Native static connected occupancy, queries, surface, edit invalidation and compound persistence | Automatic placement, smooth shorelines, underwater/player integration, region exchange or explicitly scoped flow model, bake cache |
| Large caves and mountains | Inherited fixed-size generator | Redesigned native generator, large-world terrain/LOD/collision tests |
| Underground material veins and material variety | Inherited limited material set | Native material registry, seeded vein generation, editing/rendering/persistence tests |
| Volumetric asphalt roads | Pending | Native road volumes, surface/material blending, placement/editing and terrain integration |
| Shape prefabs: cubes/boxels, stairs, spheres, slopes and more | Separate native structures addon: textured cubes, slabs, stairs, slopes, posts and spheres; chunk collision, main-world block authoring, native reusable block prefabs, bounded native block undo/redo and compound persistence | Combined block/model prefabs, additional curved shapes, material catalog, graphical selection/capture and cross-addon editor commands |
| Large buildings, towns and cities | Native chunked house/tower showcase; automatic committed block-region paging; bounded nearby block meshes and memory bake reuse; model catalog/placement UI, single-model selection/move/rotate/uniform-scale controls and bounded native model history across assets; spatial static-model batching with bounded nearby paged render buffers, native per-tick upload budgets and page-local transform refresh, stable IDs, incremental edits, nearby compound-box collision, native vegetation exclusion, asset-bound snapshots and compound world persistence; 100,000-placement API test | Authored static-model region storage, persistent derived bake cache, building LOD, prefab selection/capture UI, city generation, model drag handles/numeric transforms/multi-selection, arbitrary concave model collision and dense-settlement rendering tests |
| Efficient world generator/editor with baking and caching | Existing terrain cache; dependency-invalidated native block bake cache and mesh admission budgets; compound snapshot bridge and native block-region paging | Unified command/editor model, persistent bake caches, model-region storage and high-speed loading tests |
| Proper player, toolbelt, inventory, unified interaction | Native fixed-capacity inventory with revision checks and atomic validation; inventory UI and six-slot toolbelt connected to sculpting, blocks and objects; 264-byte loadout persisted in compound world saves with legacy defaults and worker validation; inherited movement controller | Persistent player position/attributes and selected tool, pickup and resource consumption, native movement, unified command routing, water integration and multiplayer authority |
| Large multiplayer world, terrain, vegetation, structures and players | Native Windows terrain instances now isolate cancellation; networking remains pending | Multiple-scene cache/save ownership, authoritative region/command model, interest management, bandwidth/backpressure, server + two-client loss/reorder/late-join tests, measured scaling |
| Forest/vegetation including stones, plants and grass | Streamed spruce renderer and bounds | Native scatter/selection hot paths, species tiers, small-object batching and visual/performance tests |
| Efficient world representation and storage | Legacy sparse edited terrain, native checksummed compound snapshots and exact-version block-region storage/paging | Terrain/model region and delta representation, arbitrary-world addressing, journal/compaction and bounded streaming under travel |
| High entity counts | Native bounded kinematics and bulk transforms | Gameplay simulation, spatial queries, rendering, collision and replication at measured populations |
| Efficient vehicles and high-speed travel | Pending | Vehicle physics, swept collision readiness, predictive streaming, correction and sustained high-speed traversal tests |
| Always 1920Ã—1080 fullscreen for fair graphical testing | Implemented presentation policy and report assertions | Continue enforcing for every new graphical measurement |
| Most systems as Godot addons; no performance-critical GDScript | Native terrain planning, entity/archive/water and structures work implemented; remaining scene and forest schedulers use GDScript | Native migration of remaining scene/forest hot paths, non-Windows planner binaries and profiling across targets |
| Zig and prebuilt godot-cpp | Implemented, pinned, checksum-verified; debug/release tests | Maintain ABI checks and reproducible release packaging on upgrades |

Relevant evidence: VALIDATION.md (historical terrain/forest), TOOLCHAIN_VALIDATION.md (initial native/fullscreen), WATER_VALIDATION.md (first lake stage), WORLD_STORAGE.md and STORAGE_VALIDATION.md (current compound saves). Historical limitations and timings describe their recorded stage, not the final target.

Offline terrain cache inventory and verified quota cleanup are available via
`tools/maintain_terrain_cache.py`; see TERRAIN_CACHE_MAINTENANCE.md. This does not
replace the pending native runtime cache ownership, eviction and disk-reserve
work. Live-cache cleanup has not been applied while the editor/game are running.

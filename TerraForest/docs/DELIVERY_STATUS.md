## Disabled vehicle braking regression completed - 2026-10-09

Completed the remaining check after the vehicle control-admission and shortcut
fixes. The real native vehicle scene runs on a flat static floor at both 60 and
120 physics ticks per second, with controls disabled and W/A/Shift/Space held.
All 24 assertions pass: loaded support, installed input state, ignored driving
inputs, finite non-accelerating motion, stopping bounds and resumed throttle.
From 30 m/s forward it stops within 2.5 seconds after 24.69-24.85 m; from 15 m/s
reverse it stops after 6.11-6.18 m. No runtime code change was required.

Test: `tests/vehicle_disabled_braking.gd`; evidence:
`docs/evidence/vehicle_admission/disabled_braking_new_host.log`. An initial
fixture parse error was corrected with an explicit float type before execution.
This was a short headless physics check on the new machine with Godot
4.7.2.stable.steam.ed1daf0bf, not an FPS or thermal comparison. It directly
disables controls; OS focus delivery, airborne/slope behavior and streamed-world
stopping remain outside its coverage. See [HARDWARE_BASELINE.md](HARDWARE_BASELINE.md).

## Hardware migration: performance evidence boundary - 2026-10-09

The development machine changed from the previously logged GTX 1060 Max-Q GPU
to a Lenovo 82XV with i5-12450H, RTX 4050 Laptop GPU and 16 GiB RAM. Inventory,
observed power settings and comparison rules are in [HARDWARE_BASELINE.md](HARDWARE_BASELINE.md).
Cross-machine improvements must not be credited to software. The 1920x1080
fullscreen / 60 FPS target remains unchanged. No load test or settings changes
were performed; sustained performance and thermal headroom remain unqualified.

## Disabled vehicle controls also block auxiliary shortcuts - 2026-10-07

Vehicle reset (R), damage toggle (F8), repair (F9) and accessory toggle (F10)
previously polled keys without checking controls_enabled. They now require
enabled controls while still recording sampled key state, preventing shortcuts
observed during disabled ticks from firing merely when controls resume. Throttle
already used the control gate; no driving physics or braking policy changed.

Seven checks with the real native vehicle scene and injected held-key state pass:
disabled shortcuts preserve pose/damage/settings, sampled held keys remain inert
on resumption, and release/new press restores normal behavior. The fixture
explicitly flushes buffered input before checking held state; its initial attempt
without that flush did not install the intended key state. Evidence:
`docs/evidence/vehicle_admission/shortcuts.log`; test:
`tests/vehicle_disabled_shortcuts.gd`. This covers shortcut polling, not OS focus
event delivery, physical stopping distance or every frame scheduling sequence.

## Vehicle transitions respect live world interaction state - 2026-10-07

Added an optional live admission callback to the vehicle adapter. Creation,
entry, exit and control enabling consult it. The main world supplies a policy
requiring focus, captured mouse, closed inventory, ready terrain, and no loading,
shutdown, benchmark or pending terrain edit. Standalone callers without a callback
retain existing behavior. This closes the driving E path that previously could
attempt exit while unfocused or during a world transition.

The vehicle adapter fixture passes 22 checks, including blocked creation, entry
without changing player collision/physics rate, and exit without losing occupancy.
Existing speed, safe-ground, persistence and vehicle-reuse checks still pass.
Fourteen main-scene lifecycle/admission checks pass at 1920x1080 fullscreen,
covering the live callback against each configured state and clean shutdown.
Evidence: `docs/evidence/vehicle_admission`. State gates are exercised directly;
this does not qualify high-speed readiness, braking after focus loss, thermal
headroom or multiplayer possession.

## Model buttons and history use live world admission - 2026-10-07

Model pick, placement, transforms and undo/redo now consult a live availability
callback as well as the cached scene state. The main world rejects these actions
during loading, shutdown, benchmarks, driving, open inventory, loss of focus,
unready terrain or pending terrain edits. This closes both a stale-frame button
path and an editor history path that previously omitted edit availability.
The paid-placement adapter repeats the live gate before charging inventory.

Action buttons disable while unavailable. Gameplay resizing buttons also remain
visibly disabled; free editor resizing recovers when available. Twelve focused
transaction/control checks and thirteen actual-scene checks pass. The scene
checks opening inventory and immediately requesting a selected-object transform
before a frame update; the transform remains unchanged. The fullscreen 1920x1080
capture was inspected. Evidence: `docs/evidence/model_admission`. This is local
interaction admission, not server authorization or a complete editor command API.

## Object selection owns E while its tool is active - 2026-10-07

Fixed an input-routing conflict: on-foot E was consumed by harvesting/pickup
collection before the object tool could select the aimed model. Active object
mode now handles E before vehicle entry and resource interactions, subject to
focus, captured mouse, world readiness, shutdown/loading and benchmark gates.
The existing model tool still checks edit availability. Driving retains its
exit interaction; outside object mode, vehicle/harvest/pickup routing is unchanged.

The expanded paid-model scene passes 11 checks, including on-foot selection of
the placed beam, preservation of a nearby pickup and unfocused rejection. The
selection screenshot was inspected. Six harvesting-scene checks also pass outside
object mode, including range, wall occlusion and single reward delivery. Both run
at 1920x1080 fullscreen. Evidence: `docs/evidence/interaction_routing`. This fixes
one real routing conflict, not a complete unified interaction or multiplayer model.

## Cache-enabled main-scene startup check - 2026-10-06

The actual Forward+ main world passes all six startup, pickup-autosave notification
and teardown checks at 1920x1080 fullscreen with derived caching enabled. Added
startup phase output and worker-delivered cache counters to the scene fixture.
The recorded cache inventory takes 51.970 ms, examines 126 entries and enters
read-only mode with incomplete accounting. The reported 536,870,912-byte value is
the conservative quota sentinel, not a measured disk total when
`accounting_complete` is false. No cache writes occur in the recorded interval.

Playable readiness is observed about 10.4 seconds after backend start. Worker
startup publication preceded it by about 10.3 seconds: nearby terrain/collision
preparation remains distinct from cache initialization. This successful short run
does not establish a startup deadline, diagnose all past timeouts, or qualify
frame rate. Evidence: `docs/evidence/cache_scan_budget/world_scene.log`.

## Cache-enabled startup uses bounded accounting - 2026-10-06

Replaced recursive cache enumeration with an iterative scan limited to 2,048
entries, 32 directory levels and a cooperative 50 ms deadline. Reaching a limit,
the disk quota, or an unreadable file leaves accounting incomplete and blocks new
derived-cache writes. Existing checksum-validated reads continue with direct
lookup; no incomplete directory index suppresses them. Complete small inventories
retain normal quota-checked writes. The geometry index also has entry/time bounds.
No canonical save or existing cache data is deleted by configuration.

A 2,100-file fixture stopped after 187 entries in 52.896 ms. Five checks verify
bounded enumeration, refusal of writes with unknown usage, resumed writes after
complete reconfiguration, and valid reads while read-only. Disabled-cache probes
and all ten paid-model disk checks also pass. Evidence:
`docs/evidence/cache_scan_budget`; fixture: `tests/cache_scan_budget.gd`.

Tradeoff: large or slow caches become read-only until offline maintenance and
reconfiguration produce a complete inventory. This is conservative admission,
not background accounting, eviction or a persistent quota ledger. Individual OS
filesystem calls are not preemptible, so 50 ms is not a hard wall-clock guarantee.
Multiple writers and external changes still need cache ownership/accounting work.
Full-game startup and the historical 30-second timeout remain unqualified.

## Disabled derived cache no longer scans historical files - 2026-10-06

Startup phase diagnostics identified unnecessary recursive disk enumeration even
when the derived cache was disabled. Three openings in the paid-model fixture
spent 2.301/2.982/2.745 seconds in cache configuration, while world generation/load
took under 2 ms. Disabled configuration now clears stale accounting/index state
and returns before enumeration. Re-enabling requires explicit configure() to
rebuild quota accounting. Enabled-cache behavior is unchanged.

The same fixture after the change spent 29/20/21 microseconds in cache
configuration and reported world readiness in 66/36/36 ms. Its ten persistence
checks pass. A separate probe verifies no quota scan when disabled and restoration
of accounting on enabled reconfiguration. These figures cover a headless fixture
with streaming paused, not the full graphical game's loading time.

The backend now exposes a mutex-protected startup phase, phase age, completed
phase durations and pending-result count. It distinguishes native world load,
cache fingerprinting, cache configuration, native setup and metadata publication.
This is bounded startup-only instrumentation. Evidence is under
`docs/evidence/startup_phases`. The earlier 30-second timeout was not reproduced
or proven explained; enabled-cache recursive enumeration and full-scene startup
variability remain open. No canonical world data or cache files were removed.

## Paid model placement persists with its inventory debit - 2026-10-06

Added a fresh-provider/worker disk test using the region-aware compound archive.
Starting with eight metal, native paid placement creates one model and leaves
four metal. Autosave publishes before teardown; shutdown writes are disabled.
Fresh providers restore byte-identical inventory and model snapshots, including
the placement identity and transform. Removing the model gives no refund; another
autosave and fresh reopen preserve its absence and the original debit. All ten
checks pass in the final run, which completed in about ten seconds.

The first run missed its 30-second initial startup deadline and incorrectly
continued dependent assertions; its log is retained as a fixture failure, not
evidence of a persistence defect. The fixture now stops on setup failure, logs
worker status and allows 60 seconds for initialization. Startup variability
remains unexplained; the successful rerun does not resolve it. No runtime change
was required. Evidence: `docs/evidence/model_inventory/disk.log` and
`disk_initial_startup_failure.log`; fixture: `tests/model_inventory_persistence.gd`.
This checks normal autosave/reload, not abrupt interruption during disk publication
or multiplayer transactions.

## Gameplay model placement consumes inventory - 2026-10-05

Connected the static-object tool to the existing synchronous native inventory
coordinator. Provisional recipes charge 4 metal for a beam, 8 metal for a floor
panel and 8 concrete for a doorway; costs appear in the object palette. Native
placement failure rolls back the debit using the debit revision. Missing recipes
reject gameplay placement. Gameplay object undo/redo and resizing are disabled
to avoid bypassing costs; moving/rotating paid objects remains available. Removal
does not refund. Editor placement, scaling and history remain unrestricted.

The actual-scene check exposed missing world autosave notification for structure
changes. Connected the existing structures changed signal to the terrain/world
dirty flag. This covers model edits as well as block changes; the addon already
invalidated its own snapshot cache. The initial failed scene log is retained.

Seven model transaction/control checks, 22 existing block/prefab inventory checks,
and eight actual-scene checks pass. The scene creates a beam using the real tool
on an elevated test support, deducts exactly four metal, marks the world dirty,
shows the recipe and refuses gameplay undo. Its 1920x1080 fullscreen screenshot
was inspected. Evidence: `docs/evidence/model_inventory`. These checks establish
local placement accounting and autosave notification, not a fresh paid-model disk
reload, multiplayer authority, final recipe balance or large-city throughput.

## Pickup renderer pressure at all seven store limits - 2026-10-05

The new targeted pressure fixture fills all seven native pickup stores to 4,096
records each (28,672 total). Selection remains capped at 256 visible rows per
type, or 1,792 combined. Initial transform submission is 86,016 bytes; thirty
stationary refreshes submit zero transform bytes. Focus movement stays within
the same caps; removing the selected stone population replaces its rows with
live nearest positions, and leaving the populated area hides every batch.
All 27 checks pass with Forward+ at 1920x1080 fullscreen.

Thirty synchronous seven-store refresh calls measured CPU p50/p95/max of
1.325/1.499/1.534 ms in the recorded final run. This is a deliberately dense
API-level fixture, not a camera-rendered combined world, frame-time measurement,
thermal test or endurance run. No renderer optimization was necessary: existing
native row comparison already suppresses unchanged uploads. It still performs
bounded selection work at the adapter's refresh frequency.

The initial headless run failed transform readback, returning zero positions;
the graphical renderer returned the expected positions. Both diagnostic logs
are retained, and the fixture now explicitly requires a graphical renderer.
Evidence: `docs/evidence/pickup_pressure`; test: `tests/pickup_render_pressure.gd`.

## Raw mining resources support world drops - 2026-10-05

Stone, iron ore and copper ore now support the same inventory drop/recollection
path as construction materials. Native stores, spatial queries, batched rendering
and compound persistence are reused. Pickup colors are keyed by item ID rather
than assuming contiguous construction IDs. Tools remain nondroppable. Each of
the seven item types has at most 4,096 stored pickups and 256 rendered nearby
instances; adding the three types increases fixed store/renderer overhead and
the bounded explicit collection search to at most 7 x 64 candidates. No active
rigid bodies or per-pickup nodes were added. Visuals remain simple colored cubes.

All 39 disk checks across the three new resources pass: drop, autosave, fresh
reopen, recollection, second autosave and second fresh reopen conserve counts
and identities without resurrecting collected pickups. The transaction fixture
passes 17 checks including empty defaults for absent resource sections in legacy
saves. Nine actual-scene copper-ore checks pass at 1920x1080 fullscreen; the
inventory screenshot was inspected. Evidence: `docs/evidence/resource_drops`.
The scene test grants fixture ore directly; generation/mining yields are covered
separately by existing mining tests. Dense pickup rendering, multiplayer authority
and runtime thermal headroom are not qualified by these checks.

## Save protection reports its actual cause - 2026-10-05

Removed the blanket assertion that every blocked save follows snapshot corruption.
Explicit write protection now retains its first supplied reason under the existing
mutex. Pending-edit shutdown, interrupted scene teardown, addon restoration and
mining accounting supply specific reasons; a subsequent protection call cannot
overwrite the original cause. Worker initialization/validation rejection reports
that broader category without falsely diagnosing corrupt disk data. Existing
save admission, temporary-world behavior and disk protection remain unchanged.

Seven diagnostic checks, 13 fresh disk drop/recollection checks and 25 mining
reward/persistence checks pass. The latter exercises direct teardown with a
pending edit: the log now identifies interrupted publication and the prior saved
inventory/building state is preserved. Evidence: `docs/evidence/save_block_reason`.
Historical logs retain their original misleading message; no disk corruption is
inferred from those intentionally protected test teardowns.

## Dropped supplies survive fresh disk reloads - 2026-10-05

Added a 13-check disk test using the production compound capture, worker and
archive path. It drops one of five wood units, autosaves, destroys the worker and
providers, then reopens with four inventory units and exactly one pickup at the
same persistent identity and location. Recollection restores five units; repeated
collection is rejected. A second autosave and fresh reopen preserve all five
inventory units and no world pickup. All checks pass in about seven seconds.

The test accelerates only the autosave timer. Shutdown writes are disabled before
each teardown, so shutdown cannot create the archive being verified. This invokes
an existing misleading backend message about a corrupt snapshot; this fixture
does not detect corruption and both archive reloads succeed. The test covers
normal saved-state conservation, not process termination during writes, network
authority or arbitrary filesystem failures. No runtime correction was needed.

Evidence: `docs/evidence/inventory_drop/disk.log`; fixture:
`tests/inventory_drop_persistence.gd`.

## Inventory supplies can return to the world - 2026-10-05

Added an inventory action to drop one selected construction material on clear
ground ahead of the on-foot player. It uses the existing bounded native entity
stores and static batched pickup renderer, without per-pickup nodes or physics
bodies. The world adapter validates lifecycle, support, collision readiness,
reach and nearby supplies. Native reservation precedes revision-checked slot
consumption; capacity rejection preserves inventory contents and revision.
Observers receive the existing autosave change signal after both sides commit.
Editor inventory drops consume owned materials too; free editor authoring is
unchanged. Raw ores and tools are not droppable yet.

All 16 transaction checks pass, covering conservation on recollection, snapshot
restoration of pickup identity, stale/invalid requests, nested drop rejection,
atomic observer state and full-store rejection. Nine main-scene checks pass at
1920x1080 fullscreen, including button wiring, real support physics, overlap and
focus rejection, autosave dirtiness, reachable recollection and clean shutdown.
The screenshot was inspected: the expanded inventory fits on screen.
Evidence: `docs/evidence/inventory_drop`. The first scene run passed interaction
checks but used a nonexistent test teardown method; its log is retained and the
corrected rerun shuts down through the normal terrain drain.

This is a local gameplay feature, not multiplayer authority, a new persistence
format or a performance qualification. The scene fixture uses an elevated
physics support platform in the real world to isolate drop placement from terrain
shape variability; it does not test every natural slope or a full disk reload.

## Native vegetation streaming priority - 2026-10-05

Moved periodic nearby-cell enumeration and distance sorting from GDScript into
the existing native vegetation addon. Native partial sorting retains the previous
distance order and row-major tie-break; the facade still owns request admission,
eviction and retries. Work is bounded to 625 candidates for the existing 32x32
world, with radius at most 768 metres and at most 625 requested owners. Invalid
arguments return an empty selection; extreme outside-world coordinates are
rejected by range intersection before distance arithmetic.

The frozen legacy comparison passes 23,131 cases, covering every world cell plus
a one-cell border, five radii, four limits, invalid inputs, extreme coordinates
and actual facade insertion order. The 19 integrated resampling checks also pass.
Both Windows native targets were rebuilt against the existing prebuilt SDK.
Evidence: `docs/evidence/native_scatter/priority.log` and `priority_resample.log`.

A headless 1,000-call comparison measured 538,027 microseconds for the legacy
selector and 10,256 for native selection (including the script/native boundary).
This removes periodic script work; it is not evidence of better GPU use, sustained
60 FPS, faster terrain mining or support for a larger world. No loading budget,
terrain algorithm or gameplay/editor policy changed.

## Vegetation refresh rejection and recovery - 2026-10-05

Expanded the integrated resampling fixture after the native placement migration.
An invalid scale in a completed batch preserves live visual/collision support,
keeps the owner marked for resampling and releases its request slot. A valid
retry publishes new support and clears the retry flag. An unknown completion
does not release another request. A completion received during a pending terrain
edit preserves support and retry intent, then recovers after the edit settles.
All 19 fixture checks pass, including the existing empty-owner and neighbouring
tree checks. No runtime change was required for these scenarios.

Evidence: `docs/evidence/native_scatter/retry.log`. The fixture injects callback
completions into the actual ecosystem/renderer/trunk path; it does not simulate
worker stalls, prove a retry deadline or qualify long-session behaviour.

## Native vegetation surface placement - 2026-10-05

Moved slope filtering and yaw/scale/root-offset transform construction from
the ecosystem callback into `NativeVegetationScatter.place_surface`. GDScript
retains epoch/revision checks, request ownership and publication orchestration.
The native API admits at most 4,096 samples (runtime owners currently contain
at most 36), checks equal array lengths and validates unique positive IDs,
finite rotations, renderer-supported scales and a finite slope cutoff before
producing placements. Nonfinite surface points/normals and zero normals are
skipped as unavailable support; the old loop did not explicitly reject NaN
normals. Valid sample order and transforms are preserved.

All 22 API checks pass, including exact agreement with legacy transforms for
the valid fixture and acceptance at the slope boundary. Existing terrain
resampling and road/vegetation tests add 24 passing checks; the fullscreen
1920x1080 scene adds six. The whole-world candidate compatibility test still
passes all 49,152 byte comparisons. Both native DLL targets rebuilt against
the prebuilt SDK; runtime validation uses debug. Evidence is under
`docs/evidence/native_scatter/surface*.log`. This is a native migration and
validation improvement; no frame-rate or transform-throughput gain is claimed.

## Whole-world scatter compatibility - 2026-10-05

Expanded native-generation verification to every cell of the current 32x32
world grid across four seeds (including negative and INT64_MAX) and three
densities. A frozen copy of `_candidates` from commit 2ad1c8a is kept solely as
a test oracle in `tests/fixtures/legacy_scatter.gd`; runtime does not import it.
All 49,152 packed-byte comparisons across 12,288 cell cases pass. IDs are also
checked for uniqueness and membership in their owner's exact 36-ID range.

For seed 1703 at density 0.82 the generator emits 6,519 candidate roots before
terrain slope/support and structure/water/harvest exclusions. This is the current
world's population, not proof of large-world or dense-city capacity. Surface
sampling, transforms after support queries and render throughput are outside
this test. Evidence: `docs/evidence/native_scatter/whole_world.log`; executable
fixture: `tests/scatter_world_compatibility.gd`. Runtime used the debug DLL.

## Native seeded vegetation candidate generation - 2026-10-05

Moved the ecosystem's per-cell RNG, biome mask, stable-ID generation and packed
candidate-array construction into `NativeVegetationScatter`. The scene adapter
now makes one native call per requested owner. Each call visits exactly 36
candidate slots; invalid cells outside the existing 32x32 grid and nonfinite or
out-of-range density return empty arrays. Species, world bounds and generation
rules are unchanged. This does not add grass/plants or migrate the remaining
ecosystem scheduling and publication loops.

Before replacement, 72 cases were captured from the GDScript implementation at
commit 2ad1c8a: four seeds including a negative seed, three densities and six
cells spanning empty, biome-edge and populated regions. The checked-in fixture
stores exact packed bytes for points, IDs, rotations and scales. All 576 direct
and integrated byte comparisons plus eight invalid-input cases pass. An initial
native float-promotion mismatch was caught and corrected before integration;
the reference fixture was not regenerated to accommodate that mismatch.

The short 1,000-call comparison measured about 37 microseconds per cell for the
legacy adapter and 14 microseconds through the integrated native path. This is
a bounded CPU microbenchmark, not an FPS or GPU-usage improvement measurement.
Both native targets rebuilt using the pinned prebuilt SDK; runtime tests used
the debug DLL. All 32 harvest-state checks and six fullscreen 1920x1080 scene
checks pass. The headless scene attempt hit its readiness deadline; its failed
log is retained, and startup variability remains open. Evidence:
`docs/evidence/native_scatter`; fixture: `tests/scatter_reference.json`.

## Harvest admission respects world and owner updates - 2026-10-05

The ecosystem's harvest API now checks its bound terrain lifecycle directly,
rather than relying solely on the main scene's input handler. It rejects during
loading, pending edits, closing and stopping. It also rejects an owner awaiting
surface resampling, an outstanding surface request or exclusion reconciliation,
so retained visual trees cannot yield rewards from stale owner state. These
checks precede changes to inventory, exclusions or render/collision roots.

Successful owner publication, including an unchanged result, clears its
reconciliation restriction. Other stable owners remain eligible once there is
no global terrain edit. The user gets a retry message while their target owner
updates. An ecosystem without a bound terrain retains standalone operation;
this is local admission logic, not network authority or a multiplayer protocol.

All 32 state/admission checks, 11 fresh disk-reload checks and six fullscreen
1920x1080 scene interaction checks pass. The lifecycle tests set each gate
independently and verify no mutation; they do not simulate network races.
Evidence: `docs/evidence/harvest_state/admission.log`, `admission_disk.log` and
`admission_scene.log`.

## Correction: saved HUD images do not substantiate missing glyphs - 2026-10-05

Direct pixel analysis contradicts the earlier visual interpretation of missing
characters. In both archived native-flush images described below, all 1,108
bright reference title pixels remain at the same locations (two additional
pixels cross the threshold). The help strip retains all but 5 or 10 of 3,567
reference bright pixels, with 23 additional pixels. These counts do not support
the earlier claim of broad missing title/help characters or renderer corruption.
That diagnosis is retracted; the older entries below are investigation history,
not confirmed open defects. No runtime workaround is justified by this evidence.

The latest probe captures the original transparent HUD without added labels or
opaque backing. All 12 post-harvest bright help masks are identical. Its six
gameplay checks pass. `tools/compare_hud_pixels.py` reproduces the comparison
against the archived PNGs; results and source captures are under
`docs/evidence/transparent_text`. The masks use minimum RGB thresholds of 210
for help and 230 for the title. Background blending can move antialiased edge
pixels across thresholds; this is not a full font-rendering correctness oracle.
The cause of the misleading visual appearance in prior inspection is unknown.
This closes the unsubstantiated glyph-corruption diagnosis, not a verified code
defect, and makes no claim about the earlier startup timeout or runtime FPS.

## Automated text stability comparison - 2026-10-05

Added `tests/world_text_stability.gd`: it renders four static text sizes on an
opaque panel, puts an opaque backing behind the actual bottom help label,
harvests a natural tree and compares exact captured pixel bytes over 12 samples
while telemetry text changes. Native vegetation uploads remain enabled.
The final run reports zero changed panels and zero changed help strips, with a
confirmed harvest. Reference crops were visually inspected and contain readable
complete text. Evidence: `docs/evidence/text_stability/native.log` and `native/`.

Earlier panel-only runs also stayed stable, with and without harvesting. This
does not reproduce the transparent-HUD artifact, and weakens attribution to
native vegetation uploads alone. Adding a backing and extra labels changes
composition and timing; passing this diagnostic does not prove the original
issue fixed. Production HUD and renderer settings are unchanged. The test runs
at fullscreen 1920x1080 with the game's 60 FPS cap, but synchronous GPU readbacks
make it unsuitable for performance measurements. Pixel equality detects change
after the reference frame; it cannot establish correctness without inspecting
that initial reference, nor cover text elsewhere outside the sampled rectangles.

## HUD glyph diagnostic remains open - 2026-10-05

Extended the natural-harvest capture with a 30-frame settling period and explicit
help-label redraw. The native vegetation-upload run reproduced missing glyphs
in help, title and toolbelt. Layout inspection reports the complete text,
visible_characters=-1, clip_text=false and a help rectangle inside 1920x1080.
Queueing a redraw did not fully remove the visual artifact. This is broader
than the original report of clipped help text; ordinary label bounds do not
explain the observed title characters disappearing.

A separate `tests/text_render_probe.gd` with 20 labels and dynamic text updates,
but no world, rendered cleanly using the same Forward+ GPU and resolution.
A full-world comparison with the existing `--scripted-vegetation-flush` switch
also produced readable help/title in the inspected capture. These are single
comparison runs, not proof that native code corrupts rendering; timing and
render workload differ. No production rendering switch or speculative redraw
workaround was added. Further reproduction is required to isolate the cause.

Evidence under `docs/evidence/natural_harvest`: `native_flush/`,
`scripted_flush/`, `text_only.png`, `text_only.log` and `ui_check.log`.
All six gameplay assertions pass in each world run, but those assertions do not
detect missing glyphs. Screenshot readback/PNG writing stalls this diagnostic;
its HUD FPS values are not usable gameplay performance samples.

## Natural forest harvesting visual check - 2026-10-05

`tests/natural_harvest_visual.gd` loads the actual generator-3 world, selects the
nearest naturally generated root, positions the camera beside its trunk and
invokes the E handler. Native ray targeting identifies tree 23488 at approximately
(804.9953, 49.07021, 1305.7). Harvesting changes resident root count from 1,907 to
1,906 while all other root identities and transforms remain unchanged. Inventory
wood increases from 64 to 68. Six checks pass with Forward+ fullscreen 1920x1080
and the 60 FPS cap; before/after images were inspected after exit.

Evidence: `docs/evidence/natural_harvest`. The first attempt timed out at the
fixture's 30-second readiness limit before testing harvesting. One retry with
a 60-second limit passed; the initial timeout cause remains undiagnosed.
Movement and new ecosystem scheduling are paused for the controlled visual
comparison, with existing terrain work still running. This is not a walking
playtest, sustained FPS/thermal result or animation-quality qualification.
The tree disappears immediately; a felling animation is still absent. Some
bottom help text appears clipped in the after capture and needs a separate
UI/rendering check before claiming visual polish.

## Maintain canonical harvest order during mutation - 2026-10-05

Native harvest state now uses an ordered set. Canonical save capture walks IDs
directly without building and sorting a temporary vector. Membership/insertion
are O(log n); unchanged cached captures remain constant-time. Serialized format
and save compatibility are unchanged. A tested radix-sort alternative worsened
maximum-capacity measurements and was discarded before committing.

Seven changed-capture samples per case, using the debug DLL on this laptop:
36,864 IDs improved from 1,811 to 410 microseconds median; 262,144 IDs from
17,876 to 10,776 microseconds. Sparse wide IDs at that limit improved from
18,732 to 10,998 microseconds. The measured maximum was 12,919 microseconds.
Repeated captures remain about 1 microsecond. A 36-candidate mask averages
2.4–3.2 microseconds at nonempty populations (1,000 calls, repeatedly querying
the same candidates; this is a warm-cache microbenchmark).

The current generator has at most 36,864 candidate IDs across its entire world.
At the general store limit, capture still takes a material portion of a 60 FPS
frame and needs a worker/regional design before larger-world qualification.
The container change does not establish sustained gameplay FPS or memory usage.
All 24 state checks, including an independent ordering oracle through INT64_MAX,
and 11 fresh archive checks pass. Evidence: `ordered_before.log`,
`ordered_capture.log`, `ordered_state.log`, `ordered_disk.log` under
`docs/evidence/harvest_state`. Both DLL variants rebuilt; runtime tests use debug.

## Reuse unchanged harvest snapshots - 2026-10-05

A short native capture benchmark reproduced repeated main-thread sorting work:
at 36,864 IDs the median unchanged capture was 1,553 microseconds; at the
262,144-ID limit it was 18,645 microseconds (21 samples per population).
The native store now caches canonical serialized bytes until a successful mark
or unmark. A valid restore adopts the already canonical input using Godot's
copy-on-write byte storage. Worker validation remains pure and does not touch
the cache. Callers cannot mutate previously captured or cached state indirectly.

The same benchmark measures 1 microsecond median at both populations after the
change, with 2 microseconds p95 at maximum capacity. First capture remains
2,400/18,418 microseconds respectively: this removes repeated unchanged work,
not the large first-capture hitch after mutation. Cache memory adds up to about
2 MiB, and rebuilding can temporarily retain older snapshots held by consumers.
No sustained frame-rate claim follows from these microbenchmarks.

All 23 state/transaction checks and 11 fresh disk-reload checks pass. Both DLL
variants rebuilt against the prebuilt SDK; runtime checks used the debug DLL.
Evidence: `docs/evidence/harvest_state/capture_before.log`, `capture_after.log`,
`cached_state.log` and `cached_disk.log`. First-capture cost at larger world
scales still needs worker-side serialization or regional persistence work.

## Harvest archive round trip - 2026-10-05

`tests/harvest_persistence.gd` verifies a live harvest through the actual
autosave worker and disk archive. It destroys the terrain worker, inventory,
harvest provider and vegetation, then creates fresh instances using the same
isolated save slot. Exact saved inventory and harvest bytes return. Regenerating
the owner preserves its neighbour but not the harvested tree or trunk collider;
a physics ray confirms the old trunk location is clear. Repeated harvesting
after reload grants nothing, and a second unload/regeneration remains correct.

All 11 checks pass in `docs/evidence/harvest_state/disk.log`. Shutdown writes are
disabled before both teardowns so they cannot conceal a missing autosave. The
backend's generic "save disabled after corrupt snapshot" message reflects that
intentional guard; the fixture does not inject corruption. The autosave clock is
advanced to its threshold, and rendering/terrain streaming is paused. This proves
the disk transaction and fresh-instance restoration, not timing or FPS under
active travel. The earlier supply test covers the unaccelerated 15-second clock.

## Gameplay tree harvesting - 2026-10-05

In gameplay construction mode, E now harvests an aimed trunk within 2.5 metres
when no vehicle interaction takes precedence. The native scene ray includes
terrain, structures, trunks and vehicles for occlusion. Harvesting is disabled
while flying, loading, editing terrain or using the inventory, and editor mode
retains its existing interactions. Four wood per tree is a provisional recipe.

The synchronous adapter checks active generator ownership, native inventory
capacity and native exclusion admission before removing the exact visual root
and trunk collider. It announces a save-relevant change after the transaction.
Duplicate attempts cannot grant again; a full inventory leaves the tree intact.
Cell reconciliation applies the persistent exclusion on subsequent publication.
Native ray queries, inventory storage and harvest membership handle the data;
GDScript coordinates one user action and one bounded owner reconciliation.

Nineteen native/transaction checks and six graphical main-scene checks pass,
including the E-key handler, range, occlusion, reward and autosave notification.
Evidence: `docs/evidence/harvest_state/action.log` and `interaction.log`.
The E-handler check initially failed headless because mouse capture was not
available. The passing run uses Forward+ fullscreen 1920x1080 with the existing
60 FPS cap. The earlier direct-method headless check did not cover this gate.
The scene fixture inserts a controlled tree above terrain; it does not establish
visual polish, natural-tree targeting across a forest, a harvest-specific disk
round trip, multiplayer authority or long-session performance. Tree-felling
animation and tool requirements are not implemented.

## Native harvested-tree persistence substrate - 2026-10-05

The vegetation addon now stores harvested stable IDs separately from resident
render cells. `NativeHarvestState` supplies native hash lookup and bounded batch
masks; ecosystem publication applies the mask before updating visual roots and
trunk collision. The main scene registers `harvested_trees` in the compound
archive, with an empty default for older saves. Resetting resident cells does
not erase harvested IDs. Snapshot restoration replaces them atomically after
validating version, size, positive IDs and strict sorted uniqueness.

The store admits at most 262,144 IDs and refuses overflow without forgetting
old entries. Serialized storage is 16 + 8 bytes per harvested ID (2,097,168 bytes
at capacity); RAM includes hash-table overhead. Masks accept at most 4,096 IDs;
current ecosystem owners have 36 candidates. This is a bounded whole-world
store for the current generator, not regional paging for unlimited worlds.
Stable-ID meaning must be preserved when changing the generator or migrating
saves. Archive capture sorts the stored IDs; no large-world capture latency
claim is made here.

Fifteen native/filter/lifecycle checks and six actual-scene checks pass. Both
native DLL variants rebuilt against the prebuilt SDK. Evidence:
`docs/evidence/harvest_state`. The fixture checks compound provider restoration,
not a harvest-specific disk round trip. Player targeting, inventory rewards,
autosave notification for harvesting and player-facing controls remain to be
implemented; this commit does not expose a harvest action yet.

## Supply autosave disk proof - 2026-10-05

`tests/pickup_autosave.gd` now verifies the actual worker-owned archive. It saves
an authored wood supply, collects it, waits through the production 15-second
autosave interval without a manual save, disables further writes, deliberately
changes live inventory/pickups, and reloads from disk. Reload restores the wood
and leaves no pickup, including the unsaved replacement. All ten checks pass.
Only the initial setup save timer is accelerated. Terrain rendering/streaming is
paused in this headless fixture; this is persistence proof, not an FPS test.

The first attempt exceeded a 10-second startup allowance; the fixture now allows
30 seconds for initial load/reload and 20 seconds for each autosave. Evidence:
`docs/evidence/pickup_autosave/disk.log`. Its shutdown message about a corrupt
snapshot is the backend's generic writes-disabled message: this test explicitly
disables writes to prevent shutdown from masking a missing autosave. No corrupt
snapshot is injected here.

## Supply mutations trigger autosave - 2026-10-04

Supply placement and collection previously changed persisted addon state without
setting the terrain-owned autosave dirty flag. A player who only collected
supplies could therefore miss periodic saves until another action dirtied the
world (manual save and shutdown remained separate paths).

The pickup addon now emits `changed` after successful spawn or complete
inventory-grant/entity-removal transactions. The main world marks autosave dirty
from that signal. Failed spawns, blocked/full-inventory collections and snapshot
restoration emit no mutation notification. Work remains bounded to user actions;
no polling or per-frame inventory scan was added.

Sixteen pickup checks and six actual-scene lifecycle/wiring checks pass without
leaked-object warnings. The tests cover consistent snapshot capture from the
notification and autosave eligibility, not a timed autosave disk-write test.
Evidence: `docs/evidence/pickup_autosave`. Wood harvesting remains unimplemented;
starter wood and authored supply pickups are the existing sources.

## Actual gameplay scene integration check - 2026-10-04

Added `tests/gameplay_scene.gd`, launched with the real main scene in temporary
gameplay mode, generator 3, Forward+ and fullscreen 1920x1080. Nine functional
checks pass: startup/nearby collision readiness, mode wiring, starter supplies,
streamed excavation and reward delivery, actual inventory claim/craft buttons,
pointer availability and 60 FPS cap/presentation settings. The screenshot was
visually reviewed. Mining is submitted through the terrain API in this fixture;
it is not a mouse-driven mining-input or sustained performance qualification.

The original run reported one leaked `RefCounted` at exit. This was isolated to
the vehicle scene preload: startup requested a threaded load but never retrieved
it when no vehicle was placed. The vehicle adapter now consumes each accepted
request on use or tree exit. Early exit can wait for an unfinished resource load.
The four-check startup/shutdown fixture and 19-check vehicle integration test
pass without leaked-object warnings. The nine-check fullscreen gameplay test
also passes without the leak; its Vulkan loader still reports missing Epic
overlay JSON files on this machine. Evidence: `docs/evidence/scene_lifetime`.
This resolves the reproduced teardown warning, not long-session memory stability.

## Save barriers in priority terrain queue - 2026-10-04

A targeted regression reproduced a queue-ordering defect: a newly submitted
priority edit jumped ahead of an already captured save. The resulting archive
contained the later terrain revision and addon state rather than the earlier
save request's state. Three assertions failed on the previous implementation.

Priority edits, loads and resets now insert after the last queued save or world
mutation. They still bypass unrelated background work after that barrier. This
preserves accepted mutation order and snapshot meaning; an edit may have to
wait for an earlier save rather than overtake its disk work. The extra queue
scan is bounded by the existing 96-job admission limit.

The deterministic test queues jobs before starting the real worker, reads the
actual compound save, and verifies that live terrain still receives the later
edit. All 11 barrier checks, eight manual-save checks and 25 mining/building
save checks pass. Before/after evidence: `docs/evidence/save_queue_barrier`.
This is a correctness fix, not a disk-latency or frame-rate improvement claim.

## Paid construction compound-save proof - 2026-10-04

The live mining/crafting fixture now registers the real structures component,
uses metadata-first regional persistence and restores through the native block
pager, matching the main world's storage path. The paid block is no longer an
unsaved isolated store. After explicit save, the fixture disables teardown
writes so a later shutdown save cannot mask a faulty manual save.

All 25 checks pass, including exact building-region bytes after fresh-worker
reload, preserved inventory/pending receipt, rejecting replacement of an
occupied restored cell without charging, and retaining the same building region
through graceful close and protected direct teardown. Expected write-protection
messages appear during the intentionally disabled shutdown saves. Evidence:
`docs/evidence/mining_build_save/test.log`.

This closes the earlier persistence verification gap for one constructed block.
It does not establish populated-city throughput, large-region paging latency,
building rendering performance or multiplayer consistency.

## Mining-to-building crafting loop - 2026-10-04

The inventory now offers four starter recipes: 2 stone to brick, 3 stone to
concrete, and 2 iron ore or 2 copper ore to metal. These are provisional game
rules. Native `exchange_items` consumes inputs and grants outputs together,
restoring original contents/revision on any failure. Outputs can use slots
freed by consumption. A successful exchange advances revision once and the UI
marks the world dirty for autosave. Recipe definitions and bounded batch
selection remain moddable script; stack operations are native.

Fifteen native/recipe checks pass. The 21-check live mining fixture now includes
claiming actual excavation output, crafting and paid native block placement,
then inventory/reward save reload. Its isolated block store is not included in
that fixture's archive. Fourteen graphical checks pass at 1920x1080 fullscreen,
covering crafting button behavior and layout; screenshot reviewed. Evidence:
`docs/evidence/crafting` and updated `docs/evidence/reward_claim_ui`. World parsing
and debug/release native builds pass. Stations, processing time, wood harvesting
and authoritative multiplayer crafting remain unfinished; these correctness
checks do not qualify sustained world performance.

## Gameplay mining to pending inventory - 2026-10-04

Gameplay excavation now converts native removed lattice samples into pending
stone (201), iron ore (202) and copper ore (203), with one raw unit per removed
sample. Terrain revision identifies the receipt. Repeated/no-op cuts do not
award resources. The existing inventory UI claims them through native atomic
transfer. Raw items have separate labels/catalog entries; starter building
supplies remain unchanged. Crafting raw resources into building materials is
not implemented yet.

Gameplay edit admission rejects free terrain additions, grading and legacy
terrain cubes, and checks conservative inbox capacity before mutation. Editor
tools remain unchanged. Normal close drains rewards before saving; direct
synchronous teardown during a pending gameplay edit protects the previous save.
This fallback can lose unsaved progress rather than publish unaccounted terrain.
Unexpected receipt failure protects the previous save and stops mining.

Nineteen live worker/persistence checks pass for actual excavation, deduplication,
claiming, fresh-worker reload, normal/direct teardown and saturated admission.
Eleven graphical UI checks pass at fullscreen 1920x1080, including raw-resource
labels; the screenshot was reviewed. The inbox/loadout/excavation worker suites
add 52 passing checks. Evidence: `docs/evidence/mining_rewards` and the updated
`docs/evidence/reward_claim_ui/inventory.png`. World parsing and both native
builds passed. This demonstrates the reward path, not sustained mining FPS,
precise volume economics or multiplayer authority.

## Inventory pending-material claim UI - 2026-10-04

The inventory now lists pending materials with a quantity input and Claim
button. Claims use the native atomic transfer, refresh the visible inventory
and pending balances, and retain all pending stock on capacity or stale-state
failure. Successful claims and slot transfers notify the world for autosave.
Keyboard handling now permits GUI quantity entry and dropdown navigation.

Ten graphical checks passed at 1920x1080 fullscreen Forward+, including actual
keyboard input, button dispatch, partial/exhausted claims, full inventory,
stale-state retry, panel bounds and presentation policy. The saved screenshot
was visually reviewed. Evidence: `docs/evidence/reward_claim_ui`. This short UI
fixture is not a sustained performance measurement. Mining still does not
produce reward receipts; the test populates the inbox explicitly.

## Persistent pending reward storage - 2026-10-04

Added `NativeRewardInbox` with 32 distinct-item capacity, a 10^12 per-item bound,
and a fixed 400-byte save format. Receipts accrue atomically and must increase
strictly; their saved watermark rejects duplicates after reload. Native partial
claims commit pending deductions only after the inventory grant succeeds, so
capacity/revision failure retains the complete unclaimed reward. Main-thread
mutations emit no callbacks; save-worker validation reads only supplied bytes.

The main world registers `pending_rewards` with an empty default for older
saves. Thirty-one checks cover duplicate receipts, full-inventory retention,
partial claims, malformed data, capacity limits and disk round trips, including
a compound terrain/inventory/inbox archive. Thirteen loadout regression checks
and world script parsing also passed. Evidence: `docs/evidence/reward_inbox`.
Debug/release native builds use the prebuilt SDK.

Mining receipt production, claim UI, inbox saturation handling and authority
integration remain unfinished. This storage addition does not enable mining
rewards or provide out-of-order/network delivery semantics.

## Atomic multi-material inventory grants - 2026-10-04

Added native `grant_items` and nonmutating `can_receive` for up to 32 item/count
pairs over the fixed 32 slots. All rows stage before commit: a late invalid row
or capacity failure cannot partially award earlier materials. Duplicate rows
share staged capacity, existing stacks fill first, and successful batches
advance revision once. Gameplay starter stock now uses the batch API.

Seventeen targeted checks passed, including stale revisions, malformed tails,
late capacity failure, duplicate rows, exact remaining capacity and the maximum
32-million-item inventory bound. The existing inventory, construction and
loadout suites also passed (67 checks). Evidence: `docs/evidence/inventory_grants`.
Both native builds use the prebuilt SDK. This provides atomic capacity handling,
not overflow storage: durable mining reward retention/delivery remains unfinished.

## Graceful window-close save ordering - 2026-10-04

The game window's close handler now awaits `shutdown_after_edits()`. Closing
rejects new terrain edits/reloads, continues draining pending publication and
its callbacks, then captures addon state and joins the worker for final save.
Background scheduling stops during this drain. If publication reports an error
or has not settled within 30 seconds, snapshot writes are disabled before
shutdown, retaining the previous canonical save. Joining an already-running
native job can still take additional time; this is not a hard process-exit bound.

Thirteen checks cover closing immediately after admission, callback inventory
capture, fresh-worker disk reload, idle close, and injected publication failure
preserving the previous terrain/inventory pair. Eight manual-save regression
checks and world/controller script parsing also pass. Evidence:
`docs/evidence/shutdown_save_ordering`. The timeout itself was not exercised.

This covers the normal window-close path. Direct synchronous `shutdown()` and
forced scene/process teardown do not drain main-thread publication callbacks.
Gameplay rewards remain disabled; inventory overflow and reward delivery across
other teardown paths still need a defined policy.

## Manual-save ordering across edits - 2026-10-04

Manual save requests now wait while a terrain edit is pending. Repeated requests
coalesce into one request, and addon capture occurs after publication and its
synchronous callbacks. Worker queue admission failure retains the request for
the next frame. Unready/stopping worlds reject manual save; unresolved world
errors cancel the deferred request. Autosave policy is unchanged.

The eight-check `tests/manual_save_ordering.gd` fixture uses an isolated real
compound save file: it requests save twice during native excavation, grants a
test inventory item in the publication callback, waits for verified save, clears
runtime inventory and reloads from disk. Both the edited terrain revision and
post-publication inventory restore together. Evidence:
`docs/evidence/manual_save_ordering/test.log`. This proves the manual-save path,
not shutdown during a pending edit. Mining rewards remain disabled pending
shutdown ordering and inventory overflow handling.

## Native excavation accounting - 2026-10-04

Brush edits now count newly excavated density-lattice samples by their original
material in the existing native edit loop. A count requires a quantized sample
to move from negative (solid) to nonnegative (air). Band-only changes, repeated
cuts into air and additive edits do not count. This is lattice accounting, not
exact removed volume; adding terrain and removing it again can count anew.
No inventory rewards are enabled by this change.

Command 2 preserves its 52-byte response prefix and appends sixteen u32 counts
(116 bytes total). Failed and legacy replies decode as zero. The worker sums
successful grouped brushes, clears accounting on group failure, and exposes
the counts as `last_edit_outcome.removed_samples` alongside epoch/ticket/status.
This field is diagnostic output, not a durable reward receipt. Road grading
and the legacy separate cube store are excluded. Reward integration still
needs save ordering, overflow policy and restrictions on free terrain creation.

Validation: 18 native/codec checks use independent before/after material and
density queries; eight live worker checks verify grouped duplicate brushes and
no-op clearing. The 12 road/vegetation regression checks and world script parse
also pass. Debug/release binaries built against the prebuilt SDK. Evidence:
`docs/evidence/excavation_accounting`. No rendering or mining-latency improvement
is claimed by these correctness tests.

## Gameplay starter inventory - 2026-10-04

New gameplay construction loadouts receive 64 units of each building material,
so the separate launcher permits initial building without preparing supplies
in the editor. The grant is part of the registered default loadout, used only
when the world has no player-loadout section. Saved contents replace that
default exactly; repeated preparation/restoration does not replenish spent
materials, and existing editor inventories remain unchanged.

The 13-check `tests/gameplay_loadout.gd` fixture passed, covering all four
materials, unchanged editor defaults, repeated preparation, native validation,
disk-restored partial/depleted stocks and the actual persistence component
restore path. Evidence: `docs/evidence/construction_inventory/gameplay_loadout.log`.
Mining rewards and renewable gameplay resource acquisition remain unfinished.

## Separate gameplay construction costs - 2026-10-04

The editor remains free. The new `Play Gameplay Construction.cmd` uses its own
save slot and enables material costs for blocks and prefabs, including deferred
frontage placement. Native inventory deductions are atomic across stacks and
materials; rejected native placements restore inventory contents. Prefab
material totals are cached during authoring, avoiding per-cell script work at
purchase time. The HUD names the mode. Free supply spawning and construction
history are disabled in gameplay construction; removal has no refund.

Validation: 22 new construction/inventory checks, 32 existing inventory checks,
13 large-building checks (78,624 cells), 17 prefab composition checks and world
script parsing passed. Both native addons have debug/release builds using the
prebuilt SDK. Evidence: `docs/evidence/construction_inventory`. These are short
correctness tests, not a frame-rate or multiplayer qualification.

This is not a full survival ruleset: mining rewards, starter resources, road,
vehicle and static-model recipes and authoritative multiplayer transactions
remain open. Mode selection is a launch option; inventory uses existing world
persistence. See `addons/player_runtime/README.md` for transaction boundaries.

## Entity nearest-query scaling evidence - 2026-10-04

Added an 18-case short CPU fixture: populations 4096, 100000 and 262144, sparse versus tightly crowded placement, and candidate budgets 512, 4096 and 16384. Each case executes four warmup and 32 measured native nearest queries, returning at most 128 handles. All admission/count/completeness checks passed. Sparse local queries visited 256 candidates at every population and averaged 7.875..10.719 us. Crowded queries visited at most their budget; maximum observed query duration across cases was 464 us at budget 16384 and population 262144.

The limiting behavior is explicit: all crowded 100000/262144 cases exhausted every tested budget, so their nearest result is only among visited candidates. CPU boundedness does not solve completeness or insertion-order bias under extreme same-cell occupancy. The current 32 m index remains unsuitable for claiming arbitrary crowd-density coverage without additional spatial subdivision or a different admission policy. Costs exclude population creation/index allocations, renderer uploads, simulation, physics and GPU work; this is not an entity-fleet or 60 FPS qualification. Evidence: docs/evidence/entity_query_scaling.

## Bounded nearest entity selection - 2026-10-04

Added NativeEntityStore.query_sphere_nearest and switched the native renderer to it. Unlike the original gameplay query, it does not stop when output capacity fills: it scans up to the explicit candidate budget, retaining at most result_limit candidates in a native max heap, then sorts by distance with persistent identity as the tie-breaker. Existing cell-footprint, candidate and result bounds remain. selection_complete distinguishes a proven nearest subset after a full scan from a partial scan; complete still reports whether all matching entities were returned. Original query_sphere behavior remains unchanged for gameplay callers.

Nine native checks passed, including an adversarial cell where the nearest entity is last in traversal, a distance oracle over 5101 entities, exact candidate-budget behavior, invalid regions, ties and deletion. All 21 graphical renderer checks passed at 1920x1080 Forward+, retaining unchanged-buffer reuse. Both native binaries were rebuilt. The new selection can examine more candidates than the old early-result-limit exit, bounded by the same explicit budget. No throughput or sustained-frame-rate improvement is claimed. Under candidate-budget exhaustion it is nearest only among visited candidates; spatial traversal order is unchanged.

Evidence: docs/evidence/entity_nearest.

## Reuse unchanged entity GPU transforms - 2026-10-04

NativeEntityRenderer now compares selected positions against its retained transform rows. It acquires writable array storage and submits a MultiMesh buffer only when a visible row actually changes. Query budgets and generation-checked position lookup remain unchanged. Visibility still updates after empty/invalid queries, removals and selection-size changes; first-use rows initialize their identity basis even at the origin. No second retained buffer or per-entity node is added. Changed selections still upload the full fixed-capacity buffer; this is not sparse GPU upload or query-result caching.

The 1920x1080 fullscreen Forward+ test passed 21 checks against a 100000-entity store, including 60 unchanged refreshes with zero transform upload bytes, movement/reuse, origin initialization, growing selections, visibility recovery, empty removal and external layout mutation. Actual MultiMesh transform readback matched selected entity positions. An initial headless run failed transform-readback assertions; graphical rendering is required for this renderer verification. The saved screenshot was inspected. Both native targets were rebuilt against the prebuilt SDK. No GPU-utilization, thermal or sustained-frame-rate claim is made.

Evidence: docs/evidence/entity_renderer_reuse.

## Road vegetation with terrain streaming enabled - 2026-10-04

road_vegetation_live.gd now accepts --streaming-fixture, enabling ordinary terrain mesh scheduling and checking that actual tiles were built and retained before paving. The report includes worker build and tile counts rather than treating an enabled flag alone as evidence of work. In the final thirteen-check headless run, builds increased from 30 to 36 and retained tiles from 30 to 33 across the edit/resample interval. Exactly one of 324 roots was removed; 323 neighbors retained transforms and trunk records. Repainting as stone restored all original memberships and transforms.

Observed edit completion was 32.853 ms, followed by 33.355 ms until resampling drained, with no stale results or rejected batches. Disk cache was disabled. This is a short stationary nine-owner streaming fixture, not worst-case queue contention, travel, visible rendering, collider contact or sustained-60-FPS evidence. Evidence: docs/evidence/road_vegetation_streaming.

## Live road/vegetation resampling regression - 2026-10-04

Added a short integration fixture using TerrainWorld, its real worker/signals and the actual ecosystem scheduler with nine resident owners. It starts with 324 native-supported roots, selects an existing root, paves at its support height, waits for edit publication and lets the normal async surface batch retire it. Exactly one root and its trunk record disappear; all 323 other roots retain their transforms and trunk records. No batches were rejected or stale. In the final run edit completion was observed after 32.955 ms and resampling completed 16.669 ms later. These are one-run wall timings observed at process-frame boundaries.

Repainting the identical geometry as stone through the worker restores all 324 original IDs/transforms and trunk memberships. All twelve checks passed. Terrain mesh streaming is intentionally paused to isolate worker-to-ecosystem behavior; the test does not qualify full-world latency under streaming load, visual fade completion, active collider proxy contact or sustained FPS. Evidence: docs/evidence/road_vegetation_live.

## Asphalt vegetation support exclusion - 2026-10-04

Native natural-root sampling now rejects support contributed by solid asphalt lattice corners. Previously command 17 only tested density support and natural slope, so paving at the original surface height could leave valid tree roots on asphalt. The material check reuses the lower support interpolation samples, skips zero-weight corners and returns the existing zero-normal rejection marker. Batch size remains bounded to 64 and the wire format is unchanged. It does not remove an entire vegetation owner or introduce scene-thread terrain queries.

Twelve targeted checks passed: natural support, asphalt at unchanged height, unchanged same-owner neighbor, identical geometry repainted as stone, actual ecosystem publication, renderer/trunk removal for the paved root, preserved neighbor transition state, and restoration after stone repaint. Existing twelve resampling and fourteen building-exclusion checks passed. Both native targets were rebuilt with the pinned prebuilt SDK. This is native-query and ecosystem membership evidence; the fixture feeds native results into the ecosystem directly and does not qualify live async resampling latency, visible fade completion or physics contact. Asphalt support rejection is root-local, not a full canopy clearance corridor.

Evidence: docs/evidence/road_vegetation.

## Exact connectors between saved streets - 2026-10-04

The street selector now includes Set start / Set end. Entrance buttons use that target through the normal world action handler. Setting an end retains the captured start and existing road settings, requires asphalt and matching destination width, and reports the existing length/grade/boundary validation result. Invalid preview geometry does not bypass guarded Build. Missing starts, pending edits, stale epochs and mismatched widths reject selection. Choosing endpoints only updates the preview.

Sixteen continuation checks passed. The 27-check persistence fixture reopens two paved streets, selects an entrance from each, builds the connector through native road construction and verifies asphalt/clearance at its endpoints and midpoint across the gap. The 35-check 1080p mixed-site editor fixture verifies the actual end-target button routing and unchanged terrain revision; its screenshot was inspected. The graphical preview deliberately connects opposite ends of one prepared street to exercise the control; separate-street construction is covered by the native integration fixture. Frame capture reached 42.436 ms, so this is feature evidence only.

This supplies manual straight connectors within the existing 128 m and 25 percent grade limits. It does not plan curved routes, grade transitions, junction topology or navigation. Evidence: docs/evidence/street_connector.

## Persistent prepared-street catalog - 2026-10-04

Preparing another street now appends its entrance pair instead of replacing the previous one. A road-panel selector identifies streets by sequence and midpoint X/Z; selecting a street changes which entrance buttons are available without submitting terrain work. Exact repeated endpoint pairs update the existing width rather than duplicating entries. The catalog retains at most 256 streets and refuses additions at capacity without discarding existing records. It clears on unrelated epoch changes and restores with the selected index through compound saves.

The native codec retains version-one single-street compatibility and adds a version-two collection: 16-byte header (magic, version, count, selected index) followed by 1..256 validated 64-byte version-one records, at most 16400 bytes. Malformed counts, nested versions, selected indices and records reject the collection. Single-entry captures retain version-one encoding. Both native binaries were rebuilt against the prebuilt SDK.

Twenty-four persistence checks passed, including two independently paved streets, exact selected-street disk restoration, legacy migration, duplicate registration, malformed input and the exact 256-record limit. Twelve continuation checks passed. The 33-check mixed-site graphical workflow initially exposed the added row intruding into the toolbelt; reducing vertical spacing fixed it, and the rerun passed. Its 1080p screenshot was inspected. The functional frame capture reached 38.783 ms and is not sustained-60-FPS evidence.

This is a saved entrance catalog, not a connected road graph, routing, intersections or automatic city layout. Deletion/renaming and spatial catalog search remain future authoring work. Evidence: docs/evidence/street_catalog.

## Compound paved-street restoration proof - 2026-10-04

Strengthened road_anchor_persistence.gd beyond fabricated metadata. It constructs and waits for publication of a native 64 m asphalt section at y=180, registers its entrances only after the revision advances, and publishes the compound save. Before and after reopening, native point queries verify asphalt material with negative density one metre below both endpoints and the midpoint, plus positive density two metres above those points. Queries run only after joining the terrain worker, retaining its core reference to avoid concurrent native access. The fresh palette restores identical anchor bytes and selects the exact second entrance as its preview start. All twelve checks passed in the short headless test.

This proves matching saved geometry and entrance metadata for the tested section, not arbitrary roads, interrupted-save fault recovery, full site grading or junction topology. Evidence: docs/evidence/road_anchor_terrain_persistence.

## Saved prepared street entrances - 2026-10-04

The last completed prepared street now retains its two entrance coordinates and width through the compound world save. NativeRoadAnchors supplies a versioned fixed 64-byte codec and stateless worker validation, rejecting nonfinite/out-of-world coordinates, widths outside 4..64 m, degenerate endpoints, unknown versions and trailing bytes. Missing sections preserve compatibility with older saves. UI restoration clears transient selections and pending/completed section state, binds the restored anchors to the current epoch and restores the entrance controls. Invalid data leaves current anchors untouched. Invalid live data rejects saving rather than silently dropping it.

Nine targeted checks passed, including actual compound disk publication and restoration into a new terrain/palette instance, exact restored preview selection and legacy empty-section handling. All twelve road continuation checks and nineteen vehicle interaction checks passed. Both native binaries were rebuilt with the pinned prebuilt SDK; godot-cpp was not rebuilt. Main-world graphical startup and vehicle interaction also passed at 1920x1080 Forward+.

This persists only the last prepared street, not a road graph, junction network, terrain undo or durable site preparation job. Anchors record authoring coordinates; later terrain edits may invalidate their physical suitability. Manual road continuation remains session-only. Evidence: docs/evidence/road_anchor_persistence.

## Vehicle startup logging stall - 2026-10-04

Opt-in nested setup timing narrowed the previous attachment cost. Native helper initialization took 29 us; body construction 497 us, four wheel bindings 26 us total and door binding 7 us, while the full base setup interval was 37002 us. The four unconditional startup print calls were outside those measured visual operations. Vehicle startup messages are now controlled by the exported startup_logging option, default false. Errors remain enabled.

The otherwise equivalent 1080p Forward+ world test then measured placement 1672 us, attachment/setup 852 us, native initialization 34 us and base visual setup 628 us. First post-draw completion was 5.881 ms after placement began. Placement, driving, seated saving and exit passed; all 19 headless interaction checks also passed and the screenshot was inspected. This identifies synchronous startup logging as the large setup stall in this redirected-output test configuration. It does not establish identical console behavior on every launch path or sustained world frame times; one later interval was 18.504 ms. The previous assumption that rendering construction itself consumed 23 ms is superseded by these finer measurements.

Evidence: docs/evidence/vehicle_quiet_setup. Profiling remains opt-in with no per-frame sampling.

## Vehicle installation stage measurements - 2026-10-04

Added opt-in install timing for scene instantiation, attachment/_ready and world binding. It is disabled by default and adds no per-frame instrumentation. The graphical world fixture enables it. Before the change, placement measured 29.200 ms: allocation 0.655 ms, attachment/setup 22.079 ms and binding 6.338 ms. This narrows the remaining hitch to setup plus a synchronous adapter script load.

The native car adapter now preloads the streaming adapter as a script dependency, so its load occurs with vehicle resource preparation. The imported setup-only Model is hidden in the scene resource, rather than becoming hidden only at the end of setup. Afterward, placement measured 23.726 ms: allocation 0.505 ms, attachment/setup 23.030 ms and binding 0.077 ms. First post-draw completion was 28.966 ms after placement began. These are two observational world runs, not a statistically controlled benchmark; no attachment improvement is demonstrated by hiding the model. Setup remains above the 60 FPS frame budget and is unresolved.

The 1080p Forward+ placement/driving/save/exit test and all 19 headless interaction checks passed. The resulting screenshot was inspected. Evidence: docs/evidence/vehicle_install_stages.

## Vehicle prefetch world validation - 2026-10-04

Updated the interaction fixture to await explicit resource readiness rather than assuming two physics frames suffice. It also checks that resource preparation creates no live vehicle or saved vehicle record. All 19 interaction checks passed, including ground readiness, placement, entry/exit, reuse and invalid snapshot handling. The initial unadapted fixture failed its placement assumptions and exited while resource loading was still running; the bounded readiness wait removes that premature teardown.

The full 1920x1080 Forward+ world fixture now records placement CPU time and eight post-draw intervals. Placement, driving, seated saving, exit and UI restoration passed. The captured car moved 4.04 m with 2724 renderer roots reported. The screenshot was inspected after completion. Placement took 54.039 ms and the first post-draw completed 63.031 ms after placement began; subsequent intervals were 6.025, 5.536, 8.884, 15.292, 19.956, 13.914 and 16.330 ms. These include world work and cap waiting and are not isolated GPU timings. The first interval starts at placement, not the previous frame boundary.

The remaining first-placement hitch is confirmed, not resolved by threaded resource prefetch. Next investigation must separate scene setup/render-resource registration from first-visible rendering. This functional fixture simulates foreground input during driving and does not establish sustained 60 FPS or thermal headroom.

Evidence: docs/evidence/vehicle_prefetch_world.

## Vehicle resource prefetch - 2026-10-04

The world vehicle adapter now requests its PackedScene on the resource loader worker during prepare. Interactive placement polls readiness without waiting and asks for another V press if loading is incomplete. The retained PackedScene is reused. Snapshot restoration retains its synchronous contract during world loading, and installation reports failure if the resource is unavailable.

A short headless creation probe measured 306950 us resource loading, compared with 678 us first instantiation and 1317 us first scene setup. The final threaded loader check passed repeated requests, readiness polling, retained resource identity and scene instantiation: request 46 us, maximum poll 51 us over 51 polls. Compound vehicle persistence passed save and restoration into a new world. These are CPU-only measurements; GPU uploads, pipeline compilation and first-visible-frame latency remain unqualified. No sustained frame-rate claim is made.

Evidence: docs/evidence/vehicle_resource_prefetch.

## Vehicle traversal of joined road sections - 2026-10-04

Added --joined-road-fixture to tests/vehicle_terrain.gd. Two independently constructed native road sections share their endpoint at a 16 m region boundary, with a constant 6.25 percent intended grade. The joined fixture uses eight separate collision bodies built from native region meshes, rather than combining them into one physics shape. Thirty-three vertical ray samples cover an 8 m window around the join at 0.25 m spacing, checking for holes, excessive height deviation and abrupt sampled steps. The vehicle must traverse the entire window.

The final 1920x1080 fullscreen Forward+ test passed: 390/390 drive ticks had at least three loaded wheels, including 55/55 ticks in the join window. Minimum chassis clearance against the intended grade was 0.588 m. Maximum adjacent sampled height change was 0.0391 m; end speed was 70.06 km/h. Collision geometry contained 2964 triangles. The original one-section test also passed before separating region bodies in the joined branch. An initial 360-tick trial ended just short of the inspection window and failed; the joined test now drives 390 ticks to require a complete crossing.

This is resident-collision proof for one straight uphill connection. It does not qualify turns, mismatched grades, arbitrary junctions, downhill travel, streaming at speed, or sustained frame rate. The screenshot uses a plain test material, not production asphalt shading.

Evidence: docs/evidence/joined_road_vehicle.

## Prepared street entrance handoff - 2026-10-03

Site planning now captures two street centerline endpoints using native prefab cell-center rotation conventions. Only completed preparation registers them with the road editor. Street end A / B transfers the captured endpoint, grade and street width into an asphalt preview; the user marks the connecting endpoint and uses existing guarded road construction. The handoff survives building placement and later plan mutation, but world reload clears it. Streets above the road tool maximum width of 32 m are explicitly rejected rather than narrowed. Coordinates remain authoring anchors, not certification against subsequent terrain edits.

Twelve continuation/handoff checks, 28 native paving checks and 33 mixed-street graphical checks passed. Native terrain tests verify asphalt at both rotated entrances and extension beyond one end in all four rotations. The graphical test uses the actual tool-switch method, verifies no terrain mutation during handoff, and checks that only the road panel is visible and fits above the toolbelt. The inspected 1080p screenshot records that UI. An earlier test-only direct mode assignment left overlapping panels; the test now exercises the real switching path.

This supplies manual connectors from the last prepared street, not persistent road topology, automatic routing, junctions or a city generator. The functional capture still reached 36.377 ms; no sustained-60-FPS claim is made.

Evidence: docs/evidence/street_entrances.

## Confirmed road-section continuation - 2026-10-03

The road/foundation editor now tracks the exact epoch, ticket and expected revision of its accepted edit. A matching published or unchanged outcome unlocks Continue from completed end. This restores captured endpoint and section settings, clears the next endpoint and changes only the preview. Pending or mismatched edits cannot authorize continuation, later selection changes cannot redirect it, and world reload clears the remembered section. Terrain processing and protection checks remain in the existing native-backed path.

Seven targeted outcome/continuation checks and all 28 graphical road-editor checks passed. The 1080p screenshot confirms the new control fits above the toolbelt; it is UI evidence, not rendered road or vehicle seam qualification. The last completed section is session-only. Connecting generated street entrances automatically, persistent road topology, intersections and city network generation remain incomplete. No performance claim is made from this feature check.

Evidence: docs/evidence/road_continuation.

## Empty vegetation resample retirement - 2026-10-03

Fixed the zero-candidate resampling branch, which previously marked the owner resident without replacing its cached candidates or removing previously published roots. Empty candidate batches now use the same sample replacement and publication path as surface results. This retires renderer roots and trunk records, preserves the one-owner-per-frame budget and prevents later exclusion reconciliation from restoring stale candidates. Empty caches skip structure/water overlap queries and invalidations because exclusions cannot introduce candidates. Terrain resampling can still populate them later. This does not add automatic live density-setting regeneration; it corrects an already scheduled resample.

The regression reproduced three failures before the fix. All twelve resampling checks and fourteen existing native vegetation-exclusion checks now pass. These short headless checks validate membership and stored trunk transforms, not rendered appearance or physics contacts. No new frame-rate claim is made.

Evidence: docs/evidence/vegetation_empty_resample.

## Tree support resampling correctness - 2026-10-03

Fixed an ecosystem publication bug: matching stable IDs previously skipped publication even when authoritative surface samples moved their transforms. This left both renderer roots and native trunk records at the previous height. Each resident sample now retains its last accepted transforms and skips an owner update only when IDs and transforms both match. The renderer already preserves unchanged neighboring rows and their fade state. The extra comparison is bounded by the existing 36-candidate owner batch.

A targeted test first reproduced two failures (render and trunk heights). After the fix all eight checks passed, covering raised/lowered support, unchanged neighbors, identical resamples and stale revision rejection. All fourteen existing frontage vegetation checks passed. The mixed-street graphical editor test passed 29 checks, including a new post-placement native overlap query for resident tree envelopes. This checks occupied structure space rather than inferring overlap from an image; the screenshot concern was not independently established as a pre-fix intersection. The graphical capture still reached 40.927 ms and does not establish sustained 60 FPS.

Evidence: docs/evidence/vegetation_resample.

## Mixed building street authoring - 2026-10-03

The street dialog now exposes a full unsigned-32-bit layout seed and an optional explicit prefab mix. Ctrl-click selects building types; single-prefab behavior remains available. The world routes mixed selections through begin_frontage_sources on the existing low-priority authoring worker. Input is bounded to 32 sources and 262144 total source blocks before snapshots are copied. Native composition still validates output limits. Saved resources include completed geometry, street metadata, source count and seed, without depending on mutable source assets.

Fifteen worker checks passed, including immutable snapshots, deterministic geometry, empty/oversized mix rejection, persistence and compatibility with site grading/paving. The graphical palette check passed with maximum seed 4294967295, and its 1080p screenshot was inspected after widening the seed field. The mixed cottage/tower-floor fixture passed all 28 world editor checks, including survey, grading, asphalt, cancellation, support validation and exact insertion. A first run lost application focus and failed the foreground-cap check; focused retries passed. Final capture: 221 frames, p95 19.010 ms, max 49.267 ms. This is feature validation, not sustained-60-FPS certification.

The final placement screenshot shows the mixed authored modules. The tower-floor source is an open structural module, not a finished tower. Layouts remain straight paired rows; junctions, city road networks and populated-city performance remain incomplete.

Evidence: docs/evidence/frontage_mix.

## Native sparse vegetation updates - 2026-10-03

The vegetation extension now runs sparse instance slot removal/insertion and transform/fade-data updates in C++. Full cell rebuilds, allocation and transition completion still use the existing renderer; dictionary-based scene-thread state remains. The original flush loop is available through --scripted-vegetation-flush for comparisons. Both native binaries were rebuilt against the prebuilt SDK.

The 2000-tree, 180-frame adversarial parity test now compares logical render slots and packets each frame, plus MultiMesh transforms/custom data at checkpoints. It passed deletion/reuse, removal of all roots with zero live cache payload, threshold behavior and fade-time wrap at 4096 seconds. The final CPU fixture measured 358999 us scripted flush versus 300966 us native, including unchanged full rebuild work (about 16 percent less time). This is a modest improvement, not a complete renderer redesign.

The 1920x1080 fullscreen Forward+ editor test passed all 27 checks and confirmed native flush on every captured frame. The 178-frame capture measured p95 18.881 ms and max 39.001 ms; max flush phase was 11.863 ms. The earlier capture had max flush 19.133 ms, but streaming workloads differ, so this is observational evidence rather than a controlled throughput guarantee. Sustained 60 FPS is still unproven.

Evidence: docs/evidence/vegetation_native_flush.

## Application focus frame-cap policy - 2026-10-03

Frame-cap selection now queries OS focus across application windows after focus events settle. Embedded control focus loss no longer immediately assigns the background cap. Both survey and frontage dialogs use the policy, replacing the survey-only per-frame override. Player movement still clears on main-window focus loss. Minimized windows are excluded even when the platform reports them focused. There is no added per-frame window scan.

The short graphical dialog_frame_cap test passed ten event-driven checks: two open/close cycles each for embedded and native dialogs retained 60 FPS caps; minimizing selected 15 FPS and restoration returned to 60 without a manual refresh. The final window was 1920x1080 fullscreen at scale 1.0. Background behavior was verified through minimization, not a physical Alt-Tab test. The world editor test passed all 27 checks; its 206-frame capture measured p95 18.839 ms and maximum 54.693 ms. Timing varies with streaming and this is not a sustained-60-FPS claim.

Evidence: docs/evidence/dialog_frame_cap.

## Dialog focus presentation hitch - 2026-10-03

The presentation policy now sets VSync only when the reported mode is not already enabled. Previously, every window focus return reapplied the mode, including returns from embedded survey dialogs. The fix preserves enabled VSync and the requested fullscreen resolution.

A short isolated dialog test compares four close/reopen cycles per policy in one 1920x1080 fullscreen Forward+ process capped at 60 FPS. Unconditional reapplication produced four close frames of 95.478, 98.850, 99.824 and 95.821 ms. The conditional policy had a maximum of 17.562 ms across 24 sampled intervals; both phases observed four focus returns and final VSync was enabled. This reproduces the specific presentation hitch without terrain or vegetation workloads. It does not prove physical display tearing behavior or sustained gameplay throughput.

The world test now separates dialog closing/reopening, camera relocation and placement requests across draw boundaries. The probe records those actions, process/pre-draw/post-draw intervals, actual embedded-dialog state and available pipeline compilation counters. Before the fix, the isolated close frame was 112.366 ms, including 91.401 ms between pre-draw and post-draw with no compilation counter increase. After the fix its interval was 18.764 ms, including 2.006 ms in drawing. All 27 editor checks passed. Other CPU-side delays remain: the full after-capture still reached 104.308 ms, with only 1.743 ms in drawing. No broad stutter-resolution claim is warranted. The exploratory embedding toggle was removed because the runtime already embeds dialogs.

Evidence: docs/evidence/dialog_presentation.

## Native vegetation selection - 2026-10-03

The optional vegetation_runtime extension now performs neighborhood selection, visual/shadow decisions and camera-travel event scheduling in C++. The original scripted selector remains available with --scripted-vegetation-selection. The implementation uses existing scene-thread dictionaries; transition completion and instance flush remain scripted. Build-all and addon packaging include the new extension.

The 2000-root, 180-frame adversarial comparison passed audit and final state parity, queue bounds, deletion/reuse, teleports and projection/profile changes. Additional exact LOD boundary sweeps with an extreme negative signed ID passed. Summed selection time was 1628928 us scripted versus 572658 us native (2.84x reduction) in this CPU fixture.

The first graphical attempt failed the 30-second startup deadline before capture; no cause was established. The unchanged-deadline retry passed all 27 editor checks at 1920x1080 fullscreen Forward+ with a 60 FPS cap, and every captured frame reported native selection active. Its largest selection phase was 8.176 ms for 1887 rows, compared with the earlier scripted capture of 32.144 ms for 1892 rows. These are comparable workflow observations, not identical workload timing guarantees. Overall capture: 178 frames, p95 18.983 ms, maximum 101.741 ms. The worst wall interval contained only 4.353 ms vegetation work, so the remaining frame spike is not resolved or fully attributed. Sustained 60 FPS and laptop thermal headroom remain unproven.

Evidence: docs/evidence/vegetation_native_selection.

## Short site-workflow frame attribution capture - 2026-10-03

The graphical editor test now includes a bounded post-draw frame probe spanning preparation, validation and 60 post-placement frames. It records wall intervals, cap/focus state, terrain stage timings, renderer CPU/GPU timers, vegetation phase timings and counters, ecosystem time and draw calls. At most 1200 frames are retained. Vegetation profiling is restored and viewport timing disabled when the probe finishes. Nested stage labels must not be added together; GPU timers may lag and zero denotes unavailable measurement.

The first 176-frame capture measured p95 18.584 ms and maximum 108.461 ms. A second 185-frame capture with vegetation phase counters measured p95 18.574 ms and maximum 113.121 ms. Its largest vegetation update was 44.137 ms: selection 32.144 ms, flush 11.866 ms, transition 0.122 ms and negligible audit work. It evaluated 1892 roots. Another selection phase took 21.099 ms for 1475 roots. Native sparse setter time is a subset of flush (3.947 ms in the 44 ms update), so it cannot explain the entire spike. These observations establish scripted selection as a concrete frame-budget failure in this fixture. They do not attribute the full 113 ms wall interval, whose recorded vegetation work was 12.961 ms.

The next performance action is a native vegetation decision/scheduling path with behavioral parity checks, not a new terrain mesher. Runtime production behavior is unchanged by this diagnostic addition. All 27 editor functional checks still pass, but this capture fails the sustained-60-FPS expectation and provides no thermal guarantee. Evidence: evidence/site_frame_probe/.

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

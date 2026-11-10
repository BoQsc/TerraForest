# Next-tick destruction and 25% frame headroom

Status: implementation in progress; acceptance is not achieved. Original code,
tests and tooling are AI-assisted 0BSD project work. No external code was imported.

## Accepted contract

Target: i5-12450H / RTX 4050, 1920x1080, existing visuals, 60 FPS foreground cap,
VSync and 15 FPS background cap. CPU critical-path and GPU work each require
p99 <=12.5 ms; presentation requires p99.9 <=17.5 ms with no reproducible
gameplay-induced frame >20 ms. Intentional pacing wait is not CPU work.

All 256 eligible barrel triggers in resident, collision-ready terrain must have
damage, terrain, building visuals and collision consistent by the next physics
tick. The user authorized replacing the 24-cell/serialized-edit scheduling;
other gameplay, resource, debris and FPS limits remain unchanged. Do not measure
from delayed admission, drop damage, publish partial geometry or extend deadlines.

Delivery order: measurement and maximum-load feasibility; native revision-checked
transactions; pooled effects; integrated exact geometry/physics publication;
renderer synchronization; three ten-minute runs and a thirty-minute soak.
The remaining implementation and gates below must be completed in that order.

## First measured gate

`reports/performance_changes/20261110T110833384843Z_next_tick_256_baseline`
is deliberately **failed**, not a performance pass. Source gameplay retained
normal pacing with zero unfocused gameplay samples and no engine diagnostics.
The owned fixture placed 256 grounded barrels and 244 nearby building cells;
every affected neighborhood was resident before all triggers were applied.

- Trigger tick: 3006; exact deadline/sample tick: 3007.
- All 256 ignitions accepted; triggering took 2,857 us.
- At the deadline: one explosion started, 255 queued, one block job pending,
  terrain still pending, zero debris bodies and no new published terrain revision.
- The rolling trace records all 256 trigger identities and misses, with no dropped
  records. The first terrain publication arrives about 199.5 ms after ignition;
  its measured field/build/queue costs are 0.152/17.802/3.214 ms.

This proves failure of the current serialized implementation, not impossibility
of a replacement. The probe records the deadline before freezing further combat
admission, preserves queued damage for the normal save, and lets pending terrain
work shut down normally. Eventual completion cannot turn this failure into a pass.
Full building-render/collision parity is explicitly unverified; a future passing
counter alone must not qualify the complete transaction requirement.

## Measurement and retention delivered

An opt-in bounded diagnostic journal uses world epoch + persistent barrel ID,
retains the original trigger tick, and links admission, block-store completion
and terrain publication through the existing edit ticket. It holds 256 active
events and 2,048 transitions; overflow is reported, never silently overwritten.
These are diagnostic identities, not the future authoritative persistence format.
The existing rolling recorder consumes transitions. Store/terrain completion is
explicitly not proof of full building-render/physics publication.

The owned-world launcher accepts `--destruction-deadline 1|3|32|256`. It keeps the
normal pacing policy, captures the exact next physics tick, and fails missing
publication. The trace analyzer adds p99.9 and event-correlation summaries.

Completed captures automatically cold-retain old raw traces through the existing
hash-verified chunk store, keeping two ordinary captures ready. Report pins remain
respected. Observations, images and commands stay loose; `traces.archive.json`
preserves original hashes and restoration metadata. There is no storage-budget
increase or save/evidence eviction.

## Coalesced terrain feasibility

`tests/destruction_transaction_feasibility.gd` is a test-only 256-command
cohort, using four resident regions and one geometry rebuild per region. It
executes actual native field edits and Jolt cooking/registration and checks all
four replacement collision surfaces. Production command limits are unchanged.
This headless test does **not** measure rendered GPU work, building transactions,
damage, debris or the default-world recipe as a whole.

The original-core run (`reports/checks/20261110T112112763610Z`) failed:
43.658 ms observed completion, 18.046 ms field, 4.988 ms mesh build. Initial
completion timestamps included the polling return; the probe now records the
actual atomic-publication callback instead. Generator 31 with the experimental
lazy-height core (`reports/checks/20261110T112944053258Z`) still failed at
43.852 ms actual publication, tick 19 versus deadline 17; field 21.969 ms and
mesh build 7.479 ms. This is evidence that removing serialized admission alone
does not satisfy the contract. No headroom or visual acceptance is inferred.

The candidate native change computes procedural height lazily: resident field
samples use their existing density, while absent pages and removed-soil receipts
still evaluate the exact original height. No density formula, material rule,
quantization, damage ordering or memory limit changes. The native baseline /
candidate / baseline test preserves all 12 serialized field/receipt hashes,
including overlapping 256-command cohorts and allocation rollback/balance.
Generator 31 field-only median timings were 23.151 / 14.187 / 30.550 ms;
generator 1 was 15.785 / 13.456 / 17.586 ms. Variation remains substantial;
these timings exclude mesh, physics and rendering and are not FPS qualification.
Evidence: `reports/terrain_edit_core_parity.json`, baseline core `39990fdb`.

**Not adopted:** the normal-gameplay candidate
`reports/performance_changes/20261110T113144282135Z_lazy_height_candidate`
and repeated unchanged baseline
`reports/performance_changes/20261110T113438254106Z_lazy_height_baseline_repeat`
both passed exact 102-cell damage, 96-body debris and shutdown checks with zero
lost-focus frames, but did not pass frame-tail acceptance. Candidate/baseline
chain maxima were 30.541/26.614 ms; recovery p99 21.347/20.514 ms and maxima
26.345/22.273 ms. A faster field substep does not justify adoption when the
whole-frame comparison does not improve. This pair does not establish causality
for the worse tails; more attribution and repeated comparisons are required.
Native source and both DLLs are restored to the unchanged baseline. The candidate
patch is retained at `reports/checks/lazy_height_experiment.patch`, SHA-256
`9aaef1cf96cd83f58161e40f8199e817a4b2e7ba25da75ed4da681afb10e97a9`.

The older `terrain_edit_atomicity` stored hash fixture also fails on the unchanged
current core. The direct same-compiler comparison establishes parity for this
change; it does not resolve that historical fixture discrepancy. Its expected
hashes were not rewritten. Audit its intervening storage/generator changes before
using that older fixture as a current release gate.

## Remaining implementation and acceptance

### Native block-store/durability boundary (scoped checks passed)

`NativeDestructionCoordinator` now prepares a bounded native batch and commits
surviving-block damage and block erasures before block observers run. Admission
and durability revision failures discard preparation without consuming damage or
the job cursor. Reentrant combat capture is rejected until the cursor advances,
so a save cannot pair new damage with the old cursor. Existing combat snapshots,
24-cell gameplay scheduling, native 64-cell erasure ceiling and 96 debris limit
are unchanged. Packed removal/impulse outputs replace per-cell script quote,
hit and debris dictionaries; durability remains owned by `NativeWorldDurability`.

This is a **store boundary**, not atomic rendered/physical publication. The
coordinator explicitly returns `geometry_ready=false`. It does not yet own all
barrel events, spatial actor queries, terrain transactions or persistent event
IDs. Preparation still allocates bounded temporary records; pre-reserved full
transaction storage remains part of the larger redesign.

Focused checks passed: `reports/checks/20261110T115123347311Z` (ordered overlapping
damage, exact impulses, byte-identical stores, rejection/reentrancy and observer
consistency), `20261110T115231260964Z` (block regions) and
`20261110T115345802669Z` (82 combat checks).

Normal-gameplay baseline/candidate/baseline captures:

- `reports/performance_changes/20261110T115421424716Z_coordinator_baseline_before`
- `reports/performance_changes/20261110T115659370386Z_coordinator_candidate`
- `reports/performance_changes/20261110T115951742471Z_coordinator_baseline_after`

All preserve exact expected destruction, 96 debris bodies, pacing and foreground
focus. Baseline/candidate captured blast-batch median work is 1.352/1.124 ms
(eight retained frames each, including effects). Chain maxima are
26.792/26.570/32.142 ms; recovery p99 is 22.559/21.247/22.182 ms. Recovery maxima
remain variable (28.974/28.538/24.433 ms). These are scoped work and semantic
results; presentation stability and 25% headroom still fail.

### Building collision retirement (scoped checks passed)

Building retirement had the same registered-compound shape-deletion pattern
previously corrected for terrain. Retiring `StaticBody3D` nodes now enter disabled
process mode before their shapes are freed, removing them from physics. Cached,
live and preparing bodies retain their existing registration. The 1,024-triangle
piece size, one preparation piece per tick and four retirement operations per
tick are unchanged. `--legacy-structure-retirement` is a process-local diagnostic
control, not a saved preference or a reduced-quality setting.

The dense 480-piece actual-Jolt baseline/candidate/baseline test passed contact,
partial preparation, interrupted edits, resource rejection and final cleanup:

- `reports/checks/20261110T120217325273Z`: release median/max 0.309/2.335 ms.
- `reports/checks/20261110T120350209963Z`: release median/max 0.072/1.178 ms;
  directly verified retired bodies have no physics space before shape deletion.
- `reports/checks/20261110T120424780753Z`: legacy release median/max
  0.314/1.984 ms, with retired bodies still registered as expected.

These are native retirement slice timings, not total frame or headroom results.
Admission work is unchanged and still has variable multi-millisecond tails.
Final coordinator checks, including old repeated survivor records and capture
guard, passed in `reports/checks/20261110T120831215253Z`. The final native commit
gate also rejects premature admission-callback commits:
`reports/checks/20261110T121243287271Z`. Godot import/identity
generation passed in `reports/checks/20261110T120534436516Z_coordinator_import`.

### Installed gameplay: semantic pass, frame acceptance failed

The exported package contains both scoped changes; all 14 source/installed native
library pairs match. PCK SHA-256:
`d42de8b13a1b205955968fc4763860cf07dcf78cc9814fdeff506928dfae97c8`.
Export smoke, packaged house-light checks and building standards passed
(`reports/building_standards/20261110T121845461115Z`).

- `reports/performance_changes/20261110T122254453453Z_destruction_native_installed`:
  chain mean/max 24.002/36.126 ms; recovery p99/max 20.895/22.066 ms.
- `reports/performance_changes/20261110T122537797625Z_destruction_retirement_control_installed`:
  same package with legacy retirement; chain mean/max 19.616/25.704 ms;
  recovery p99/max 20.489/21.544 ms.

Both pass exact expected destruction, 96 debris, settled building collision,
foreground focus and clean shutdown. **The installed legacy control has better
frame tails.** The isolated retirement reduction is retained as a scoped CPU
improvement; these captures do not establish overall frame improvement or exclude
contention elsewhere. They remain failed performance evidence, not acceptance.

The candidate records GPU chain median/p99 21.726/25.048 ms and settled idle
14.272/18.670 ms. GPU work already exceeds the 12.5 ms target independently of
CPU retirement. Additional diagnostic capture
`reports/performance_changes/20261110T123024519612Z_destruction_gpu_passes_installed`
has a completed 15.075 ms GPU profile including opaque rendering 6.048 ms,
omnidirectional shadows 3.715 ms and directional/spot shadows 1.594 ms. Extra
profiling is enabled in this capture, so its frame tails are not an equivalent
baseline comparison. These pass timings prioritize investigation; they do not
identify an engine defect or prove a complete GPU attribution.

Matched settled screenshots in the last two capture directories were reviewed:
no obvious new visual discrepancy, with the existing floating vegetation and
exposed terrain defects still visible and unaccepted. Live geometry, shadows,
draw distances, density, pacing and resource limits are unchanged. Baked debris
and icon outputs are unchanged; their native-source receipts were refreshed.

### Opt-in debris pool and publication attribution (2026-11-10 follow-up)

The 96-slot rigid-body pool is implemented behind `--pooled-debris`; ordinary
source gameplay and the installed package still use the prior debris lifecycle.
Slots are allocated during startup, absent from physics while inactive, reused
oldest first, and retain shared baked mesh/shape resources. Reuse resets transform,
forces, velocities, mass, sleeping/freeze state and interpolation. CCD, masks,
eight-second lifetime and damage independence remain unchanged. No new storage,
debris or frame budget was introduced. Flashes/audio pooling remains outstanding.

`reports/checks/20261110T125137995836Z` passes repeated replacement/clear, original
node identity and bounded counts, real Jolt landing, paused contact, expiry,
material/mass changes, force/transform reset and inactive physics-space checks.
Its warmed 96-body enqueue ABBA values (legacy/pool/pool/legacy) are
1.499/1.099/0.793/1.818 ms; clear values are 0.056/0.117/0.113/0.060 ms. These
exclude subsequent physics/render work and are not whole-frame acceptance.
The first pool version cleared shared geometry unnecessarily; its retained
`reports/checks/20261110T124947533819Z` timings show cleanup offsetting much of
the enqueue saving. The final version retains exact shared resources in the
bounded slots instead.

Integrated headless combat with the pool passed 50 checks in
`reports/checks/20261110T124806501342Z`. The earlier invocation
`20261110T124607510648Z` omitted the fixture's required `--zombies` flag and failed
its two zombie admission checks; that failed result is preserved, not relabeled.
Final resource-retention revision also passes all 50 integrated combat checks:
`reports/checks/20261110T125314710419Z`.
Editor import and UID generation pass in
`reports/checks/20261110T125455899860Z_pool_import`; startup index and Python
launcher compilation checks pass. The installed PCK hash above and all 14 native
library pairs remain unchanged. No candidate export was created.

Foreground baseline `reports/performance_changes/20261110T124321991740Z_debris_pool_baseline`
lost focus for 179 gameplay frames and is **invalid performance evidence**.
The user explicitly deferred foreground comparisons. Do not enable/install the
pool until baseline/candidate/baseline gameplay, matched visuals and contact
checks pass without changing the approved background cap.

The existing rolling trace now optionally retains eight largest adjacent GPU
timestamp gaps, independently from its CPU gaps, with the completed device-frame
identity and recorder CPU cost. Use `--render-stages --render-gpu-stages` through
the existing launcher. Reads are bounded to 256 markers; repeated frames and
reversed timestamps remain explicit. No synchronous readback or new profiler is
introduced. Vulkan timestamp results are nanoseconds (confirmed against the
[upstream driver implementation](https://github.com/godotengine/godot/blob/master/drivers/vulkan/rendering_device_driver_vulkan.cpp)); CPU timestamps are microseconds.
No upstream code was copied. `reports/checks/20261110T125213825203Z` passes the
recorder regression including independent clocks and bounded GPU retention.
On-device GPU validation and instrumentation overhead comparison remain pending.

The 256-command terrain prototype now records stage counts and totals as well as
maxima. `reports/checks/20261110T125032612762Z` **fails** next-tick publication:
59.100 ms elapsed, trigger tick 16, required tick 17, actual tick 20. Field work
is 26.614 ms, mesh work 8.009 ms, four collision attachments total 2.034 ms,
four Jolt cooks total 0.102 ms, and the final atomic swap 0.122 ms. Nested stage
totals overlap and cannot be summed. All four collision surfaces match the
excavation. No buildings, damage, effects or GPU costs are included in that lower
bound. Field evaluation is the dominant measured prerequisite here; faster
publication scheduling alone cannot meet the deadline. Full atomic geometry and
physics publication is still unfinished, and no new deadline pass is claimed.

### Native field and mesh preparation (2026-11-10, qualification only)

`TerrainCore.execute_explosion_cohort` executes up to 256 ordered subtractive
sphere/capsule commands under one native world lock. A stack-owned 1,024-entry
cache reuses exact immutable generator heights for that call only. Spatial slot
selection avoids collisions within a 32x32 lattice window; full coordinate keys
still verify hits, and other layouts merely recompute. Point spheres use the
exact point-distance specialization. Generator-changing commands are rejected
before processing, ordinary command limits are unchanged, and cancellation
retains its separate nonblocking path.

This API is a **preparation primitive, not an atomic destruction transaction**.
Per-command edits still commit in their original order. On failure it returns
the attempted/successful prefix, original receipts and each resulting revision;
it never reports whole-cohort success after a partial failure. Reply containers
are reserved before processing. Full transaction reservation/rollback, authoritative
damage/event persistence and cross-owner publication remain unfinished.

`configure_mesh_height_cache(true)` separately enables an exact, patch-scoped
height cache for material/shading inputs. The normal path defaults off. Neither
optimization is enabled by ordinary gameplay or installed in the PCK. The
test-only cohort backend invokes the native API with `--native-cohort`, and uses
`--native-mesh-height-cache` for mesh preparation. No GPU shader, lighting formula,
geometry, collision rule, resource limit or saved-data format changed.

Final core baseline/candidate/baseline evidence:
`reports/checks/20261110T131658932368Z_terrain_edit_core_parity.json`. All 14 field,
receipt and complete mesh-packet hashes match, including positions, normals,
material/lighting attributes and collision faces. Generator 31 field medians are
26.982/8.477/24.332 ms; four-region mesh medians are 6.223/5.040/6.838 ms. These
are separate native CPU timings, excluding Jolt, publication and GPU work.
The report retains the verified source/header/harness patch. Compilation uses
the same compiler/options for all three versions; temporary products retire
automatically. Older parity reports now retain timestamped paths instead of
overwriting earlier evidence.

`reports/checks/20261110T131841906515Z` passes native API checks on generators 1/31:
all 256 receipts and revisions, exact field and mesh bytes, limit/preflight
rejection, explicit partial failure, subsequent reset, non-point capsules,
cache-key collisions and world-edge/exterior samples. Debug and release native
libraries build successfully. Foreground and installed qualification are deferred
at the user's request; source libraries therefore intentionally differ from dist.
Ordinary terrain worker/publication regressions pass in
`reports/checks/20261110T132346859827Z`, including contact, priority/cancellation,
locality/seams and clean worker shutdown. Editor import/UID generation passes in
`20261110T132521649136Z_cohort_import`; startup-index and Python compilation checks
also pass. Source debug/release DLL SHA-256 values are
`ef5ca6b1fa587f9f11332a9bb81744d0ef69afb8221be459312834a424fb7c0b` /
`e88cd01402d04c42812e86fd2a5e1705644906b35b8678b9e5bb29ad27cf1683`.
The installed PCK retains its previously recorded hash; no export/install was run.

The expanded mesh profile identified shading as 4.676 ms of an 8.726 ms baseline
worker build; the final swap was only 0.079 ms. Baseline actual publication is
46.426 ms in `reports/checks/20261110T130804221905Z`. The intermediate general-hash
candidate (`20261110T131507501559Z`) improves it to 29.048 ms but still fails at
tick 18 versus required tick 17. Its cache hit rate was 59,063/82,944, motivating
the retained spatial slot mapping.

Final actual-Jolt candidate `reports/checks/20261110T131939667642Z` publishes in
27.738 ms: field 12.025 ms, worker mesh build 5.456 ms, final swap 0.073 ms,
82,103/82,944 exact height-cache hits. It still **fails**, at tick 18 versus
required tick 17. The matching baseline repeat `20261110T132043628077Z` takes
60.874 ms (field 35.273 ms, mesh 14.129 ms). Baseline variation is substantial;
neither this component comparison nor its four contact rays establishes normal
gameplay stability, GPU improvement or the complete 256-barrel deadline.

An additional already-air sample skipping experiment retained exact bytes but
showed no clear further timing gain (`20261110T131352226262Z_terrain_edit_core_parity.json`)
and was removed. GPU pass costs and renderer stalls remain open: identical mesh
packets are an output-parity check, not proof of reduced GPU time or visual
acceptance in normal gameplay.
Conservative sphere-support row clipping also matched exact outputs but did not
improve the retained 8.5 ms field median; it was removed. Its complete source
patch and comparison remain in
`reports/checks/20261110T132306525089Z_terrain_edit_core_parity.json`. The restored
core hash matches the retained `131658932368` candidate exactly.

### Unfinished full-contract work

- Build the native destruction coordinator with deterministic overlap ordering,
  compact event records, bounded memory, indexed region queries, revision-checked
  snapshots and atomic durability/block/terrain publication. Current store calls
  still synchronously notify independent owners and terrain admits at most four
  brush commands; raising those counts alone is not the required architecture.
- Extend the failed coalesced native/Jolt prototype to the complete building,
  damage and rendered publication workload. Both field work and the worker-to-
  main-thread preparation cadence still exceed the required complete deadline.
  Redesign these paths before replacing the current production admission path.
- Add authoritative event/progress persistence with old-snapshot migration;
  implement the 96-slot debris pool and reset/contact/lifetime regressions.
- Complete instrumentation-on/off comparisons and explicit CPU wait attribution.
  The diagnostic timeline is not yet a measured-zero-overhead recorder.
- Resolve renderer worker/culling/occlusion waits with controlled comparisons and
  scheduling evidence. No experimental worker or renderer setting is installed.
- Test 1/3/32/256 overlapping and distributed blasts, dense mixed materials,
  terrain/cave/water boundaries, integrity on/off, movement, pursuit, driving,
  interrupted saves, visual/contact parity, resource stability and endurance.

The installed package now contains the scoped native store and retirement fixes.
Complete native transactions, pooled effects, next-tick publication and stable
headroom are not claimed complete. Renderer/GPU work and atomic geometry/physics
publication remain the next prerequisites; endurance cannot close the milestone
while these gates fail.

## Scoped verification

- Bounded destruction journal, original trigger deadlines, delayed draw accounting:
  `reports/checks/20261110T113718323996Z` passed.
- Existing rolling-recorder regression:
  `reports/checks/20261110T113743169995Z` passed.
- Combat semantics: 82 checks passed in
  `reports/checks/20261110T113903741454Z`. The preceding launcher run used an
  incorrect required-output substring; its console also had zero test failures.
- Analyzer: eight Python tests passed; trace retention: two tests passed,
  including complete reconstruction, failed-capture preservation and pin rules.
- New Godot identity sidecars were generated by editor import. The import finished;
  its one-off reporting wrapper subsequently rejected a list where it expected a
  required-output string. This was a wrapper error, not a gameplay pass.
- The 256-barrel world gate and coalesced publication deadline tests intentionally
  remain failed. The three ten-minute runs and thirty-minute soak are not run:
  their prerequisite complete-publication and headroom gates have not passed.

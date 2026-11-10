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

The installed package is unchanged by this measurement milestone. Native
transactions, pooled effects, next-tick publication and stable headroom are not
claimed complete.

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

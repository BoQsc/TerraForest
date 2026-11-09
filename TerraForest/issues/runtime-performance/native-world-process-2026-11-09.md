# Native world callback attribution — 2026-11-09

Status: source integration verified; installed verification and uncontended
overhead comparison remain open. This adds attribution, not a frame-rate fix. Stable 60 FPS with
headroom remains open across the world and player.

The [selection comparison](render-stage-attribution-2026-11-09.md) still contains
a 29.868 ms arrival frame with just 0.005 ms of native cover work. Its process
interval is 7.206 ms, draw 17.737 ms and physics 3.662 ms (overlapping intervals).
Improving one planner or collection cannot explain that remaining whole-frame
cost. The next measurements cover world callbacks alongside rendering, physics,
streaming and pursuit.

## Implementation and attribution limits

The rolling recorder now retains three constant-size native profiles:

- Block processing: separate horizon, residency, mesh upload/worker feed,
  collision residency and occlusion phases. These partition its callback.
- Distant model rendering: the actual process callback, kept separate from
  manually requested `advance()` work.
- Pooled lights: the existing callback timer, without per-light record scans.

Each sample retains absolute start/end microseconds. The recorder only marks it
current if the whole interval fits inside the measured process window. Paused,
disabled, absent and stale providers cannot become zero-work evidence. The
analyzer counts current/stale/unavailable samples separately and preserves valid
zero-duration measurements. All timings are nested in whole-frame intervals;
never add them to their parents or interpret wall time as thread CPU work.

Block profiling defaults off and restores its previous setting on recorder
detach. Its disabled path adds no clock reads. Light timing reuses the previous
reads. Model processing adds two timestamp reads even without a recorder. There
are three additional dictionary snapshots per attached recorded frame; overhead
must be checked with matched recorder-on/off runs. No geometry, light intensity,
collision, distance, scheduling budget or authoritative storage policy changes.

## Scoped verification

The [build receipts](../../reports/performance_changes/20261109T190459964938Z_native_world_profile_checks/)
retain the final structures debug/release identities. The first debug build was
superseded after separating manual model advance from process timing; use the
final receipt, not `first_structures_build_template_debug.json`.

- Recorder: 53 checks in debug and release, including late owner attachment,
  restoration of both initially disabled/enabled profiling, interval validity,
  unavailable/stale samples, phase partitioning, unchanged block snapshot,
  bounded rolling history, capture rotation and main-thread counters. Debug
  [run](../../reports/checks/20261109T191508632816Z/run.json).
- Models: 65 headless debug and 68 rendered release checks, including retained
  callback timing through manual advances, 100,000-instance representation,
  archive edits, visual capacity pressure, destruction and teardown. Debug
  [run](../../reports/checks/20261109T191037101901Z/run.json).
- Lights: 36 headless checks including bounded pooling, exact source movement,
  persistence, destruction, disable/re-enable and callback validity. Debug
  [run](../../reports/checks/20261109T191039841190Z/run.json).
- Analyzer: six unit tests, including rejecting stale/missing samples without
  discarding valid zero-duration samples.

The first model check wrapper used an incorrect required console tag and marked
the run failed despite 65 passing fixture assertions. That
[failed wrapper result](../../reports/checks/20261109T191010512007Z/run.json)
is retained; the corrected rerun above passes. No gameplay code changed for it.
A first capture launch deferred before launching a game because another engine
was active; its host receipt is retained. Functional fixture results do not
establish frame-time or visual acceptance in the generated world.

## Integrated result and next targets

The first source capture passed save/shutdown but exposed a real instrumentation
integration defect: the recorder attaches before cooperative startup creates
blocks. All block samples were unavailable. Lazy attachment at the next process
boundary fixes it; the 53-check fixture above reproduces this ordering.
The original [capture and analysis](../../reports/performance_changes/20261109T191158960423Z_native_world_profile_a/analysis.json)
remain retained. PID 20660 overlaps 85 host samples, so this is not an FPS baseline.

The [corrected integrated run](../../reports/performance_changes/20261109T191539218026Z_native_world_profile_lifecycle/run.json)
passes the new `--require-native-process-profiles` gate: all three providers have
6,061 current gameplay samples, with no stale/unavailable gameplay samples.
Normal save and shutdown pass without error/leak diagnostics. Peak sampled
private/GPU allocation is 3,984,162,816 / 1,483,849,728 bytes. This was deliberately
a functional run after another gameplay session had reopened, not a controlled
performance comparison. Short clean teardown does not qualify memory endurance.

In this capture, block/model/light callback maxima are 0.834 / 0.215 / 0.138 ms.
Frame 3193 takes 34.638 ms, with 10.806 ms in physics and 7.217 ms in draw; those
three callbacks total only 0.056 ms. Frame 3135 also retains a 2.182 ms terrain
collision-node attachment. These observations direct the next investigation to
remaining physics, terrain publication and rendering; they do not attribute all
physics to zombies or rule out other structure work outside these callbacks.
Contention and overlapping intervals prevent an additive whole-frame budget.

All four images from each source run were inspected. Buildings, grass, trees,
boulders and the held tool remain visible with no obvious new gaps in these
views. `arrival.png` is the driver's final outdoor endpoint, not a new arrival
photograph. Wind/time differ; continuous motion and world-quality approval are
not established. [Final outdoor view](../../reports/performance_changes/20261109T191539218026Z_native_world_profile_lifecycle/outdoor_2.png)
shows the retained generated fixture at the sweep endpoint. These are original
runtime captures, without image editing; identities and exact selected samples
are retained in [machine-readable evidence](native-world-process-2026-11-09.json).

## Remaining acceptance

Complete matched recorder overhead and installed API/save/shutdown checks.
The recorder-off attempt deferred because another engine was active; do not
present unmatched timings as its cost. Export and installed checks are held for
the user-authorized pistol/player merge window; resume on the merged revision,
verify matching DLLs and rerun the required-profile/save/shutdown gate.
Retain host/GPU telemetry and reject contended comparisons. Inspect generated
images independently from lifecycle assertions. Then prioritize measured
whole-frame costs; pursuit remains one workstream. Dense barrel/collapse
chains, long-session memory growth, wider traversal, outdoor occlusion overhead,
cold pursuit, known water/interaction failures and multiplayer scale remain open
in the [foundation tracker](../../docs/WORLD_FOUNDATION_STATUS.md).

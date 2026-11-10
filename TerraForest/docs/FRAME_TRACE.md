# Rolling gameplay frame trace

Opt-in diagnostic recorder; it does not change graphics, the FPS cap, physics,
world saves or power settings. It is absent in ordinary launches without the flag.

Current source and refreshed package contain the recorder. The previous Kaino
audio import blocker is repaired; [implementation and package evidence](../issues/runtime-performance/foundation-2026-11-09.md)
tracks scoped checks and the remaining shutdown/performance limitations.

From the repository root, open the normal browser with tracing enabled:

```text
python TerraForest/tools/run.py --scene worlds --frame-trace
```

Generate or open a world normally. **Ctrl+Shift+F12** marks a moment to retain.
This uses an unhandled key chord and does not replace the gameplay G-drop action.
Automatic captures also trigger on a frame over 20 ms or a rolling 30-frame mean
over 17.5 ms (about 57 FPS). These are diagnostic thresholds, not acceptance gates:
60 FPS still requires a 16.67 ms budget, with additional margin for headroom.

Default output is a unique session directory under:

```text
%APPDATA%/Godot/app_userdata/TerraForest/frame_traces/<UTC>_<process-id>/
```

The startup console prints the resolved directory. `--frame-trace-dir=<path>`
overrides it; use a new directory for each session. Eight `trace_00.json` through
`trace_07.json` files rotate there, replacing earlier captures from that session.
Copy important captures before continuing a long session. Separate session
directories are retained until explicitly removed; there is no cross-session
deletion of evidence or saves.

The ring retains up to ten seconds / 1,200 frames before a trigger and two seconds
afterward, capped at 2,400 rows per capture. At very high FPS the frame bound
shortens history. A ten-second automatic cooldown bounds output; outliers during
the uncovered cooldown portion request a later capture of their retained history.
Events during an active capture are included in its post window. A busy writer
defers automatic capture; manual overlap attempts increment a skipped counter.
Slow storage can still cause history loss after the bounded ring wraps. Closing
gracefully flushes an incomplete capture with `truncated=true`; a crash or forced
termination can lose unwritten memory. No synchronous per-frame console or disk
logging is added. JSON encoding and file writing run on one worker.

Analyze one session:

```text
python TerraForest/tools/analyze_frame_trace.py <session-directory> --output <summary.json>
```

For an explicit deeper render investigation, the owned-world harness accepts
`--render-stages`. It enables Godot's `--gpu-profile` and adds
`--frame-trace-render-stages` to the recorder. The optional collector reads at
most 256 completed-device timestamps and retains the eight largest adjacent CPU
gaps per frame, with truncation/repetition flags. It neither waits for GPU results
nor inserts timestamps. Missing devices or callbacks on another thread are
reported unavailable. The harness rejects a requested probe that collected no
available marker data. Normal recording does not allocate this collector.

Device frame counters and viewport times can describe earlier work. The analyzer
uses absolute CPU timestamp ranges to match marker gaps only when they fit fully
inside a retained draw interval; unmatched gaps stay unknown. A marker gap is not
an inclusive named scope. Do not sum it with overlapping frame/physics timers.
Recorder medians were about 0.28 ms normally and 0.66 ms with the collector in
separate local runs; this is not an isolated overhead estimate. Engine profiling
also adds its own work.
Use ordinary recording for pacing acceptance; these probes are for attribution.

Godot documents [shared render setup time](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-get-frame-setup-time-cpu)
separately from viewport timers. [Completed-device CPU timestamps](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html#class-renderingdevice-method-get-captured-timestamp-cpu-time)
use microseconds since engine startup. The collector records only CPU timestamps;
it does not assume CPU and GPU timestamp units or frame counters are identical.

The analyzer removes overlapping frame duplicates, retains tail distributions and
outlier stage records, and computes compilation deltas only where the immediately
previous frame is present. Triggered windows are biased toward trouble; use a
continuous observation driver or an external presentation trace for whole-session
statistics. Do not interpret the triggered-window mean as ordinary average FPS.

## Recorded evidence

- Draw-end wall intervals split into before-process, scene processing,
  after-process and drawing intervals. `physics_ms` measures from the SceneTree
  physics signal through the late recorder's callback, not the full physics
  server step. These intervals overlap and must not be added to frame time.
- `physics_tail_ms` closes the gap from the end of that late callback to the
  next physics or process signal. It includes queued work, transforms, engine
  stepping, synchronization and other work; it is not isolated Jolt time. With
  catch-up steps it also includes preparation before the next physics signal.
  Initial synchronization before the first physics signal remains outside both
  measurements. The gap is closed before drawing/frame limiting, accumulated
  across catch-up steps and reset per rendered frame. Segment/step counts and
  `physics_tail_complete` expose incomplete coverage; the analyzer excludes
  incomplete/old unavailable values rather than inventing zero work. Both
  physics fields overlap `before_process_ms`. Ordering is verified against the
  pinned [main loop](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf/main/main.cpp)
  and [SceneTree](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf/scene/main/scene_tree.cpp).
- Root-viewport GPU/render CPU timers, global draw calls/primitives and pipeline
  compilation counters. GPU readings can lag and root timers are not a guarantee
  of complete GPU attribution across every SubViewport.
- Shared render setup CPU time (`render_setup_cpu_ms`) is recorded separately
  from viewport time. Both process-frame and drawn-frame counters are retained;
  the continuous observation driver now uses the same process-frame identity.
- Main-thread cycles and CPU time when the existing native resource probe is
  available. CPU time is quantized; raw cycles are work counts, not milliseconds.
  `before_process_cycles`, `process_cycles`, `after_process_cycles` and
  `draw_cycles` separate the same four wall intervals. Each also has a
  `<phase>_thread_cpu_ms` counter. `physics_cycles`/`physics_thread_cpu_ms` sum
  measured SceneTree physics callbacks in the frame and overlap the four
  intervals. Engine work outside those callback boundaries is not included.
  `physics_tail_cycles` and `physics_tail_thread_cpu_ms` separately report work
  during the post-callback gaps, with the same availability/quantization limits.
  Samples taken off the main thread, missing, unsupported or reversed counter
  readings omit the associated field;
  they never become zero-work evidence. Samples bracket callbacks with small
  measurement offsets. These counters distinguish little measured thread work
  from sustained computation, but do not identify a wait owner or include work
  performed by other engine threads.
- Terrain/controller/loading/vehicle stages, publication queues, forest/cover
  work, zombie phases and newly admitted zombie initialization breakdowns.
- `canopy_shadow` identifies native snapshot preparation by process frame, with
  root count, duration, worker state and rebuild count. Only `current=true`
  attributes that duration to the reporting frame; older values are retained
  explicitly as stale. This measures preparation, not worker rasterization.
- Native block occluder counts, pending/retiring work, accounted geometry bytes
  and publication timing. The geometry limit excludes the engine's acceleration
  structures; use process memory telemetry to assess total memory.
- `native_world_process` retains constant-size callback profiles for blocks,
  distant model pages and pooled lights. Block phases partition its callback into
  horizon, residency, upload, collision and occlusion work. They are nested in
  `process_us` and the frame's process interval, not additional frame costs.
  Absolute `started_us`/`ended_us` must fit inside that frame's process window
  before `current` becomes true. Missing, disabled and stale providers remain
  explicit; the analyzer excludes them from timing distributions and retains
  valid zero-duration samples. Collection-wide statistics are not read here.
  Block timing is enabled on attachment and its previous setting restored on
  detach. Light timing reuses existing clock reads; model callbacks add two
  clock reads even without the recorder. Manual model `advance()` calls do not
  overwrite callback attribution. Recorder overhead includes three provider
  snapshots; matched trace-on/off runs are needed to qualify its total cost.
- Native navigation readiness/support/hazard/clearance times, requested support
  rays versus actual raycasts, and support-cache hits/limits. `zombie_navigation`
  is the last-pass snapshot; `zombie_navigation_ticks.samples` retains every
  planning tick before the draw, capped at sixteen with an explicit `dropped`
  count. Each includes immutable navigation and zombie-phase values, so catch-up
  ticks cannot hide an earlier slow planner pass. Timing categories overlap the
  planner/physics intervals and must not be added to their parents.
- Navigation `query_profile.water_queries` counts individual water-depth calls;
  `water_batches` counts native footprint calls. Each batch evaluates the original
  bounded samples internally, so fewer callback crossings do not mean fewer hazard
  samples. Custom admission and legacy point providers still use individual calls.
- Profiled native navigation passes also include `planning_thread_cycles` and
  `planning_thread_cpu_us` from the current Windows thread. CPU time is quantized;
  cycles are not elapsed microseconds. Compare them with `planning_us` to identify
  wall-time spikes with little measured CPU work without claiming a specific wait
  cause. Ordinary unprofiled passes perform neither OS measurement. The saved-world
  regional journey test retains its 32 slowest passes over 2 ms, in addition to its
  once-per-second route log, so an isolated maximum retains query-category evidence.
- Native navigation invalidation counts, global-reset counts, cumulative and
  maximum invalidation wall time, last affected-query/edge/vertex counts and
  current live/allocated/free graph slots. These appear under the opt-in
  navigation `invalidation` field. Cumulative counters preserve multiple events
  between captures; last-operation values must not be summed across frames.
- Component snapshot measurements on save-capture frames, position, motion,
  focus, menus, entry/loading state, first-person rendering mode and presentation
  settings. Stage parents/children overlap; never sum their maxima.
- Previous recorder callback elapsed time and writer activity, to investigate
  observer effects. The elapsed metric includes navigation-sample capture and
  phase-counter probe time but excludes some stage/callback overhead and
  can include OS descheduling; it is not total recorder CPU time.

The persistent host stays active across browser/world transitions. Temporary
generation SubViewports are not attached as the gameplay world. No background
driver waits are relabeled as gameplay acceptance. Automatic gameplay triggers
are suppressed in menus, inventory, loading, unfocused gameplay and shutdown;
the history and manual marker remain available.

## Investigation and checks

[Fresh-default-world investigation](../issues/runtime-performance/rolling-trace-2026-11-09.md)
records confirmed costs, controls, unresolved waits and the optimization order.
The recorder itself is diagnostic infrastructure, not a stutter fix.
The [phase-work follow-up](../issues/runtime-performance/phase-work-2026-11-09.md)
records the main-thread guards, recorder-off comparison, remaining physics/draw
costs and observed GPU power/thermal limiting. Keep hardware telemetry with future
rendering comparisons; a frame timer alone cannot separate these contributors.

```text
python TerraForest/tools/run_godot_check.py frame_trace --headless --timeout 30 --require "FRAME_TRACE_TEST failures=0"
python -m unittest discover -s TerraForest/tools -p test_analyze_frame_trace.py
```

`tests/frame_trace_world.gd` is an integrated observation driver restricted to
owned `StartupBench_FPS_` fixtures. It opens the normal browser/session and
records stationary arrival and time-based camera turns. It writes its owned
fixture on shutdown and restores the initial yaw. Diagnostic flags for uncapped
presentation and disabling first-person depth correction are test-only controls;
they are not production fixes or saved preference changes.

The wrapper makes a new owned clone of the retained fresh-default fixture and
records source/package hashes, resource counters, console output and trace files:

Before creating files it checks the existing hard free-space reserve plus the
source clone size and planned report allowance (256 MiB with traces, 32 MiB
without). Package/native pairing is checked at the same point. The existing
10 GiB warning is reported and the planned storage retained in `run.json`.
The eight trace files are bounded **per session**, not across report directories;
world clones and historical reports still need an archival lifecycle. See the
[storage audit and open work](../issues/runtime-performance/storage-audit-2026-11-10.md).

```text
python TerraForest/tools/check_frame_trace_world.py --short --save --label source_capture
python TerraForest/tools/check_frame_trace_world.py --short --save --executable --label installed_capture
```

`--save` asserts that a normal gameplay save completes successfully before the
shutdown save. Its observation retains per-component capture costs and initial
zombie setup timings. A successful save does not override a strict shutdown
diagnostic failure; the wrapper retains both results in the report.
The driver's continuous samples retain root GPU/render-CPU timings and draw
counts even with `--without-trace`, enabling a recorder-off control with the same
GPU timing instrumentation. That control is diagnostic, not a quality setting.

`--gpu-profile` also retains the engine's GPU pass summaries. `--light-abba`
compares four five-second stationary phases: guarded light updates, redundant
unchanged setters twice, then guarded updates again, with one-second warmups.
It records root GPU time, draw counts, selected lights and screenshots without
changing light counts, positions, energy, shadows or graphics preferences.
This is a diagnostic control, not evidence that redundant setters dominate GPU
cost. Run one game at a time; concurrent game processes invalidate performance
comparisons. Screenshot readback and optional verbose profiling can perturb timing.

`--render-inventory` records visible scene geometry and conservative point-light
candidate bounds **after** observations are saved; its instance readbacks are
not part of the timed sample. `--render-partition 8` or `16` runs a stationary
ABBA probe that copies nearby cover into smaller render groups with the same
instance records, mesh/material references and shadow settings. The final driver
fails if original/replacement buffers change during measurement, restores original
visibility and frees the prototype pages. `--render-full-detail` requires that
probe and disables automatic mesh LOD for every phase, then restores it.
These are test-only controls, not production rendering changes. The wrapper
retains diagnostic source hashes; observation samples include frame/time IDs.
[Results and native integration requirements](../issues/runtime-performance/cover-render-partitions-2026-11-09.md)
remain separate from stable-frame-rate and visual acceptance.

The production cover renderer uses native 16 m draw partitions. `--legacy-cover`
selects the previous 32 m layout before admission for matched comparisons; use
it with the older `--render-partition` prototype when repeating that experiment.
`--outdoor-cover` adds a deterministic 16 m camera sweep across resident grass,
three stationary views and screenshots. It holds height with fly mode while
world services keep running; it is not a walking/collision check. Screenshots
have a separate phase. The recorder includes each cover batch's native
`render_frame_profile()` as `cover_render_phases_us`, separating selection,
cleanup and upload work from the GDScript cover owner. These are nested costs,
not values to add to total frame time. Recorder overhead includes collecting them.

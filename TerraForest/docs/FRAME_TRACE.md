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

The analyzer removes overlapping frame duplicates, retains tail distributions and
outlier stage records, and computes compilation deltas only where the immediately
previous frame is present. Triggered windows are biased toward trouble; use a
continuous observation driver or an external presentation trace for whole-session
statistics. Do not interpret the triggered-window mean as ordinary average FPS.

## Recorded evidence

- Draw-end wall intervals split into before-process, scene processing,
  after-process and drawing intervals. Physics ticks and elapsed physics work are
  recorded too; they overlap the other intervals and must not be added to them.
- Root-viewport GPU/render CPU timers, global draw calls/primitives and pipeline
  compilation counters. GPU readings can lag and root timers are not a guarantee
  of complete GPU attribution across every SubViewport.
- Main-thread cycles and CPU time when the existing native resource probe is
  available. CPU time is quantized; raw cycles are work counts, not milliseconds.
- Terrain/controller/loading/vehicle stages, publication queues, forest/cover
  work, zombie phases and newly admitted zombie initialization breakdowns.
- Component snapshot measurements on save-capture frames, position, motion,
  focus, menus, entry/loading state, first-person rendering mode and presentation
  settings. Stage parents/children overlap; never sum their maxima.
- Previous recorder callback elapsed time and writer activity, to investigate
  observer effects. That callback timer excludes some stage/probe overhead and
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

```text
python TerraForest/tools/check_frame_trace_world.py --short --save --label source_capture
python TerraForest/tools/check_frame_trace_world.py --short --save --executable --label installed_capture
```

`--save` asserts that a normal gameplay save completes successfully before the
shutdown save. Its observation retains per-component capture costs and initial
zombie setup timings. A successful save does not override a strict shutdown
diagnostic failure; the wrapper retains both results in the report.

`--gpu-profile` also retains the engine's GPU pass summaries. `--light-abba`
compares four five-second stationary phases: guarded light updates, redundant
unchanged setters twice, then guarded updates again, with one-second warmups.
It records root GPU time, draw counts, selected lights and screenshots without
changing light counts, positions, energy, shadows or graphics preferences.
This is a diagnostic control, not evidence that redundant setters dominate GPU
cost. Run one game at a time; concurrent game processes invalidate performance
comparisons. Screenshot readback and optional verbose profiling can perturb timing.

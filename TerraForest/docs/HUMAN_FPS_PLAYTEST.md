# Human FPS baseline capture

For the current player save, use
`python tools/check_frame_trace_world.py --human --in-place --source Hidden_Meadow --label human_latest`.
Choose the current slot explicitly. This opens the existing save with normal
saving, allocates no world clone, and never grants ownership or retirement rights
over the player save. Only the capture traces use the existing archival lifecycle.
Use the current source checkout and matching native binaries; no export is needed.
Windows explicitly retains `Godot/app_userdata/TerraForest` as its user-data
directory so changing the project's display name does not hide existing saves
and settings. This follows Godot's [custom user-directory setting](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html).

Run `python tools/check_frame_trace_world.py --human --label human_baseline` from
TerraForest. Uses the retained seed-1703 fixture and the existing receipt-owned
clone/capture lifecycle. The source fixture stays unchanged. No export is needed.
The default fixture is an earlier generation baseline, not the newest world recipe.

Play for five minutes after arrival: look around, walk/sprint through forest and
settlement, enter buildings, interact and optionally save. Use normal settings.
Ctrl+Shift+F12 marks a problem; Ctrl+Shift+F11 finishes early and saves the owned
capture world. Prefer this finish key over closing the window. Avoid other games,
builds and benchmarks. Loading, focus loss and shutdown are separate from play.

`run.json` records revision, dirty paths, native/driver hashes and launch settings.
`observation.json` retains the full frame sequence; `traces/` contains up to eight
rotating detailed spike windows (10 seconds before, 2 seconds after a trigger).
Automatic triggers: over 20 ms or a 30-frame mean over 17.5 ms. The recorder has
measurable overhead; detailed trace percentiles are biased toward spikes.

Pending after human capture: analyze focused gameplay cadence, p95/p99 frame times,
missed 16.67 ms budgets and worst clusters; correlate detailed CPU/GPU/streaming
stages and player markers. Reproduce problems with a deterministic automated route,
fix evidenced causes, and compare equivalent world/settings/builds. Preserve
quality and gameplay workload. Architectural changes need evidence and regression
coverage; a rewrite alone is not a performance result. A capped 60 FPS pass does
not establish headroom: qualify that separately with an uncapped controlled run.
No performance improvement or 60 FPS acceptance is claimed by preparation alone.

The current capture is performance evidence, not an input replay. Full cadence
includes player positions and menu/loading/focus context, while spike windows
include subsystem timings. Deterministic playthrough recording remains pending:
after a useful human capture, choose a short reproducible route and retain its
initial world state, settings, seed and build identity, then capture simulation
tick inputs/actions and verify resulting world state on replay. Positions alone
cannot reproduce interactions, random outcomes or asynchronous world updates.

Analyze a completed capture with
`python tools/analyze_human_capture.py reports/performance_changes/<capture>`.
This writes `human_analysis.json`, separates full-session percentiles from
rotating-window coverage, excludes focus/menu transitions and records worst
clusters and their positions. Normal game exit retains samples but currently
leaves the driver completion flag false; use the finish shortcut for the complete
driver handshake. An engine error remains a failed check even if samples are useful.
See the [first current-save results](../issues/runtime-performance/README.md#human-hidden-meadow-capture--2026-11-25).

The existing launcher admits planned storage before output, then cold-retains older
receipt-owned worlds and traces after exit, keeping two ordinary ready captures.

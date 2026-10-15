# Continuous physics and independent frame sampling, 2026-10-15

This corrects measurement interpretation from `../actor_crowd_arrival/`, not
runtime performance. No actor code, binaries, save formats or water changed.

The old test awaited physics and then rendering in each loop and wrote a PNG
during measurement. Its largest 632.554 ms interval was row 181, immediately
after PNG capture at row 180. That interval includes test readback/encoding/I/O.
It must not be attributed to actor work or saving. Other stalls remain unresolved.

The revised fixture invokes the normal adapter on every physics signal for 720
updates, independently samples every `frame_post_draw`, records the drawn-frame
counter, and captures images only after sampling is disconnected. Every recorded
draw-counter increment is one. Native profiling breaks down adapter costs; pair
separation probe time is separate. Frame and adapter gates are unchanged.

| Measurement | p95 ms | max ms |
| --- | --- | --- |
| Consecutive rendered frames | 17.657 | 60.289 |
| Actor adapter, with native profiling enabled | 1.048 | 2.487 |
| Native movement | 0.698 | 1.654 |
| Collision readiness | 0.256 | 0.854 |
| Route planning | 0.012 | 0.060 |
| Store publication | 0.004 | 0.009 |
| Transform correction | 0.006 | 0.015 |
| GPU monitor | 5.762 | 7.212 |
| Test separation probes per rendered frame | 0.055 | 0.241 |

These constituent percentiles must not be added together. Native timer overhead
is included in the diagnostic adapter result. Deferred engine avoidance is
outside that adapter measurement.

**Overall FAIL retained:** frame-p95 gate passes, actor adapter p95/max gate fails,
and only 14/16 actors arrive within 720 physics updates. Separation stays at
least 0.783 m, active bodies at most 16, route work at most 12 and readiness holds
zero. The previous render-gated 16/16 result does not qualify continuous-physics
arrival. Do not lengthen the deadline or rerun unchanged to obtain a pass.

Engine `TIME_PROCESS`, `TIME_PHYSICS_PROCESS` and `TIME_NAVIGATION_PROCESS` monitors
are periodically published window maxima, not individual frame samples. The
[installed engine revision's main loop](https://github.com/godotengine/godot/blob/ed1daf0bf/main/main.cpp#L4743)
confirms this. The retained raw file initially labels them `process_ms`,
`physics_ms`, `navigation_ms`; their repeated values and p95 summaries must not
be read as per-frame distributions. The checked-in fixture now names these
`engine_window_*_max_ms` and reports observed maxima only. That reporting-only
change passed Godot `--check-only`; no new timing run was claimed.

`run.json`, `console.log` and compressed raw motion/cost data preserve the failure.
The source canonical save remains unchanged. Fullscreen 1920x1080/cap60; the
rendered world still contains terrain, vegetation and furnished buildings.

Next bounded investigation: trace the two late actors' waypoint progress under
continuous physics, then attribute movement/readiness work if a native change
is justified. Avoidance-only cost needs direct engine profiling or a controlled
comparison, not the periodic monitor treated as a per-frame timer. No headroom,
thermal, endurance or large-crowd qualification is claimed.

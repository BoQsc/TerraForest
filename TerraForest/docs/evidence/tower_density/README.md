# Furnished tower density diagnostic — 2026-10-15

**Result: the instrumented 64-tower case fails the 20 ms frame-p95 diagnostic.**

| Towers | Model placements | Frame p95 ms | Viewport GPU p95 ms | Viewport render CPU p95 ms | Draw calls |
|---|---:|---:|---:|---:|---:|
| 1 | 66 | 16.714 | 1.701 | 0.221 | 44 |
| 16 | 1,056 | 17.091 | 4.135 | 1.131 | 404 |
| 64 | 4,224 | 25.818 | 8.518 | 1.826 | 833 |

Each tower uses the actual three-floor prefab and native staged placement. The
64 case contains 93,888 block cells. Windows, furniture, doors, chests and guards
use the production catalogs. Both sunlight shadows and transparent glass are on.
Camera/focus retain the same relationship to a local tower as population grows.
All population counts are exact and model upload/collision queues settle. The
nearest complete tower has collision coverage in all three cases. Window collision
is nevertheless capped at 256 bodies, deferring 398/837 candidates at 16/64 towers.
This proves local readiness here, not readiness everywhere within the 64 m radius.

Command: `python tools/run_godot_check.py tower_density --timeout 100 --require "TOWER_DENSITY failures=0"`

Each size warms for 120 frames and measures 120 frames, at 1920x1080 capped to 60.
An initial uninstrumented run stayed below 20 ms in all cases; its logs are retained.
The subsequent run adds viewport CPU/GPU timing and complete local collision
readiness. Its worse frame result is retained, not averaged away. Timing-query
overhead, background activity and sampling variability have not been isolated.
Viewport CPU time is not whole-process CPU time; GPU time is not GPU utilization
or thermal behaviour. The generic engine process monitor is retained as raw data
and must not be interpreted as exclusive CPU work.

The 64-tower image was inspected and shows repeated buildings. This is isolated
building rendering with nearby collision: no terrain, forest, actors, traffic,
effects, warm-cache travel or endurance qualification. The 20 ms threshold is a
diagnostic slack threshold, not the project's 16.67 ms target. Next: a controlled
comparison of rendering costs before deciding on runtime changes.

# Skip unchanged block-collision selection

Previously `NativeBlockWorld::update_collisions` scanned all resident visual
chunks for admission/retirement, then scanned them again for remaining work on
every process tick. Settled stationary worlds repeated those searches indefinitely.

The native path now remembers when all work is complete. Focus changes, collision
radius changes, mesh publication and visual retirement wake it again. Identical
focus/radius assignments do not. Collision geometry, readiness queries, one-piece
admission and four-operation retirement budgets are unchanged. This removes an
idle O(resident visual chunks) scan; it does not optimize moving-focus selection
or `is_collision_region_ready` queries. A counter exposes actual selection scans.

Both debug/release structures DLLs rebuilt with Zig and the pinned prebuilt
godot-cpp SDK. Runtime checks below used the debug DLL.

- `building_collision_idle`: 512 independent chunks; 30 idle frames add zero
  selection scans or shape churn. Movement, mesh edit, disable/re-enable resume
  work, then return to scan-free idle. Passed `20261015T213642461195Z`.
- Existing `building_collision_stream`: 480-piece admission, inactive partial
  geometry, interrupted admission, edit replacement, retirement and budget
  rejection all pass (`20261015T213703747734Z`). Build/release compilation overlapped
  part of the headless checks, so their timing is not a benchmark.
- `tower_density --large-only`: 64 towers / 93,888 blocks / 4,480 model placements,
  normal shadows and 1080p cap60. All queues settle and nearest tower collision
  is complete. 120 sampled frames: p50 16.665 ms, p95 16.744 ms, max 16.864 ms;
  viewport GPU p95 3.823 ms, render CPU p95 1.819 ms, 894 draws. Zero collision
  selection scans in the measurement interval. Passed `20261015T213751697442Z`.

The 20 ms diagnostic threshold remains distinct from the project's 60 FPS target.
Previous 64-tower runs varied even without runtime changes, and the current
fixture includes the newer stair rails. Thus this is not a controlled frame-time
speedup claim or closure of the earlier intermittent hitch. It proves removed
idle selection work and this short rendered result. Forest, terrain, actors,
traffic, moving-focus cost, endurance and old-laptop thermals remain unqualified.

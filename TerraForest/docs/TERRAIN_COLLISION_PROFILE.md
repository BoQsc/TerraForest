# Controlled terrain collision diagnostics

An exported startup smoke test logged about 70 ms in synchronous collision shape creation while source-archive compression was also running. That observation was not a controlled geometry benchmark. It has not been reproduced in the following sequential graphical runs, and the cause is not established. Do not describe this change as fixing the spike.

`terrain_stream.profile_collision_pieces` enables a diagnostic signal carrying tile/piece identity, exact recipe faces and match/cook/piece elapsed times. It defaults to false. The profile script retains at most 10,000 small sample records and only the slowest non-reused geometry buffer, bounded by the native 1,024-triangle recipe limit. Diagnostic callback overhead is outside the reported native cook time; the broader streaming-piece metric can include it. No physics work moves into GDScript.

Run `python tools/profile_terrain_collision.py --godot <engine-executable> --sizes 1024 256` with no simultaneous builds or packaging. It runs each temporary world sequentially for 30 wall-clock seconds, requires successful loading and 1920×1080 fullscreen at full render scale, and holds both foreground/background FPS caps at 60. After the terrain worker shuts down, it replays the exact slowest piece 40 times at each supported comparison size. Native shape resolution remains on the main thread. Raw fixture files use `PackedVector3Array.to_byte_array()` encoding.

The backend exposes `configure_collision_piece_size()` before its worker starts and rejects changes while the thread is started or outside 256..1024 triangles. The production default stays 1,024. Smaller pieces trade shorter indivisible cooks for more shapes/nodes; changing the count is not a guarantee against OS scheduling stalls.

## Sequential comparison on this machine

Godot 4.7.2 / Vulkan Forward+ / GTX 1060 Max-Q. Both scenes finished with 292 resident terrain tiles. Reports, exact worst-piece geometry and logs are retained in `docs/evidence/terrain_collision_profile`.

| Metric | 1,024 triangles | 256 triangles |
| --- | ---: | ---: |
| Loading gate ready | 3,446 ms | 3,431 ms |
| Cook samples / resident shapes | 257 | 859 |
| Cook median / p95 / maximum | 0.754 / 0.917 / 1.070 ms | 0.165 / 0.221 / 0.391 ms |
| Scene nodes | 791 | 1,393 |
| Engine static memory | 227,067,619 bytes | 230,528,103 bytes |
| Steady frame interval median / p95 / maximum | 16.663 / 17.330 / 34.189 ms | 16.666 / 16.724 / 17.957 ms |
| Physics monitor median / p95 / maximum | 0.474 / 1.722 / 2.652 ms | 0.412 / 0.619 / 1.591 ms |

Steady samples start three seconds after loading. These are two short stationary runs, not a statistically established speedup, matched original-project comparison, travel benchmark or endurance guarantee. Engine static memory is not total process RSS, native-world allocations or VRAM. Elapsed cook time is wall time and can include preemption; the physics monitor does not isolate collision broadphase. No external power measurement was performed. Shader/driver cache state and desktop scheduling remain uncontrolled. Smaller chunks of a captured piece cannot reconstruct a larger original tile; inspect each report's `worst_faces_triangles` before comparing replay results across runs.

The 70 ms observation remains unresolved. Future diagnosis can preserve the actual offending geometry and distinguish repeatable geometry cost from stalls that disappear in isolated replay. Global physics memory budgets, dense travel and region-streaming tails still need their own measurements.

All 34 integration checks passed, including rejected out-of-range configuration and rejection of recipe-size changes while the actual terrain worker is running. The default exported pack also started successfully with all eight external native libraries; that sequential smoke run did not log a collision-cooking hitch. No native binaries or prebuilt SDK were rebuilt for this diagnostic change.

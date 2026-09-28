# Native terrain collision recipes

Terrain mesh results now include immutable native collision-piece recipes. The
existing backend worker validates finite triangle vertices, splits faces and
computes cache keys in C++. It transfers recipes through the existing locked
result queue and releases the redundant full face array. Encoded mesh caches and
world saves keep their existing formats. Generation checks before and after
preparation discard cancelled results; the existing publication epoch/stamp checks
still reject stale work. Preparation itself is bounded but is not preemptible.

`NativeTerrainCollision.prepare(faces, triangles_per_piece)` returns `ok`, `pieces`
and `prepare_ms`. Invalid input returns `ok=false` with an error. The supported
piece range is 256..1024 triangles and the face limit is 12,000,000 vertices,
matching the mesh decoder's maximum index count. No scene or physics resources
are created by this call. A recipe has no public mutation method; `get_faces()`
returns a copy-on-write array.

`NativeTerrainCollisionPiece.resolve(previous)` runs on the main thread and
returns a shape, reuse flag, token and separate matching/cooking timings. Calls
from other threads and uninitialized recipes fail before accessing physics.
The FNV-1a token is only a cache lookup key: exact faces and two-sided collision
must match before reuse. A mutated or mismatched cached shape is replaced without
changing the old shape. Cache ownership remains per live terrain tile, with no
global growing registry. Edited neighbors still publish together after every
piece is ready; old active collision remains available during preparation.

Physics cooking and node attachment remain on the main thread. Godot's
[thread-safety documentation](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)
requires appropriate server threading settings for threaded physics use and
forbids concurrent interaction with the active scene tree. This change does not
enable threaded physics or assume engine shape construction is safe on a worker.

The runtime reports `collision exact match`, `collision physics cook`,
`collision node attach`, and total `collision piece` stages. The previous
`collision_match_last_ms` metric included hashing and cooking; it now measures
only exact lookup/matching. Total timing includes empty completion calls, so its
sample count differs from the three nonempty substage counts.

## Verified scope

The debug and clean release DLL tests each pass 18 checks: malformed geometry,
piece bounds, empty input, worker preparation, worker physics rejection, exact
piece concatenation including a tail, immutable faces, identical shape reuse,
changed backface state, hash-bucket mismatch, malformed cached values and a real
native terrain fixture. Evidence is in `evidence/terrain_collision/`.

The headless fixture contains 2,356 terrain triangles. Across 12 iterations at
the retained 1,024-triangle size, median main-thread reused-tile work was
0.041 ms debug / 0.040 ms release, versus 0.723 / 0.695 ms for the old
slice/hash/match path. Median preparation was 0.219 / 0.220 ms, now worker work.
These are short CPU microbenchmarks, not frame-rate claims. Smaller sizes (256,
512) were also measured. They require 10 / 5 shapes for this tile instead of 3;
no simulation or long-run dense-world evidence justifies changing the default.

The final 1920x1080 fullscreen integrated construction test passes 148 checks.
It covers buildings and static models, player support, traversable doorways,
authoring, history, vegetation exclusion, persistence and streaming away/back.
In that short run, 435 nonempty collision pieces had cooking p95 0.950 ms,
maximum 1.298 ms; node attachment p95 0.854 ms, maximum 1.148 ms.
Total piece work (623 calls including empty completions) had p95 1.812 ms,
maximum 2.239 ms. The 58.63 ms startup observation retained in the previous
planner evidence was not reproduced in this graphical run. This does not prove
it cannot recur or establish its original cause.

## Remaining limits

Cooking and attachment are non-preemptible inside the facade's 2.5 ms scheduling
budget. That budget is not a hard frame-time limit. Engine resource creation,
physics synchronization, memory pressure and driver/OS scheduling can still
cause stalls. This work does not implement asynchronous physics cooking, disk
collision baking, arbitrary-world regions, city-scale collision LOD, high-speed
vehicle readiness or an endurance guarantee. Windows debug/release extensions
are rebuilt with Zig and the pinned prebuilt SDK; the retained old Linux binary
does not contain these native APIs and is not a supported runtime for the new
terrain facade.

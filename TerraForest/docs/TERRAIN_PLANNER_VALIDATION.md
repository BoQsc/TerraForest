# Native terrain planning

`NativeTerrainPlanner` moves request traversal, LOD hysteresis, request-priority
sorting, coverage fallback and cache-eviction candidate sorting into the terrain
GDExtension. GDScript remains responsible for bounded worker submission,
publication of scene nodes, active collision leaves and deferred retirement.
The runtime no longer uses the recursive GDScript planner or sort callbacks.
The historical implementation is retained only in a test reference script.

The native planner operates on the inherited fixed world: a 2,048-unit grid,
64 roots of size 256, five levels down to size 16, and the existing clipped
2,000-unit generation boundary. A compact 21,824-byte flag array indexes every
possible aligned tile. Inputs are bounded to that tile count and validated for
key type/alignment/domain and flag types. This is not arbitrary-world region
addressing or a new terrain generator.

`requests(focus, require_collision, tiles, split_state, visible_cut)` returns
`ok`, ordered `requests`, `requested_keys` and updated `split_state`. It computes
each visited tile's distance once, retains the 30 percent split hysteresis and
the existing near-collision priority boost. Equal-priority requests preserve
traversal order; the old custom sort did not guarantee tie order. Unvisited
hysteresis state survives. Inputs are not mutated.

`coverage(tiles, split_state, visible_cut)` returns `ok`, ordered `keys`, `hidden`
and `root_coverage`, plus a `covered_roots` membership dictionary. The loading
gate uses this published-cut membership instead of re-running coverage from
GDScript. Dirty visible tiles stay valid until their transaction
publishes; dirty hidden parents cannot reappear. Incomplete child coverage falls
back to a valid parent. Missing parents may use complete descendants. A failed
recursive attempt rolls back its output rather than publishing a partial root.
Hidden membership uses indexed flags instead of repeated linear array searches.

`eviction_candidates(tiles, visible_cut, requested_keys)` returns `ok` and
least-recently-used `keys`, preserving all roots, visible tiles and requested
keys. Scene removal and cache-byte accounting remain in the facade. Invalid
inputs return `ok=false`; the planner owns no nodes, world data or worker queues.
Calls require stable input snapshots, and the facade uses them on the scene
thread. Other threads must not mutate shared Dictionary/Array inputs concurrently.

## Differential and CPU evidence

Debug and isolated release runs pass 129 checks. The tests compare the retained
legacy algorithm with native requests, priorities, hysteresis, complete ordered
cuts, hidden membership and eviction candidates through 36 seeded travel
states. Explicit fixtures cover dirty live/hidden parents, incomplete roots,
15,625 fine tiles covering the clipped world, altitude behavior, malformed
inputs and capacity rejection. Tests also preserve exact input snapshots.

The final matched headless benchmark uses 197 resident tile records and 80
samples of request plus coverage calls. Debug medians are 7.527 ms for the legacy
GDScript implementation and 0.560 ms for native planning; p95 values are 9.975
and 0.854 ms. The isolated release run records 6.699/0.529 ms medians and
7.411/0.742 ms p95. These measurements exclude backend locks/submission, node
publication, rendering and frame presentation. They do not prove the earlier
101.09 ms scheduling event is eliminated, nor imply a similar whole-frame gain.

The facade now emits separate `LOD requests`, `LOD coverage` and `LOD eviction`
stage timings, in addition to `LOD schedule/cut/evict`, so remaining costs can be
distinguished in integrated runs. Evidence and native build hashes are retained
under `evidence/terrain_planner/`.

The integrated world passes 148 checks at 1920x1080 fullscreen, including its
loading gate, construction, collision, history, persistence and travel. Across
347 scheduling samples the combined stage records median 1.448 ms, p95 1.845 ms
and maximum 3.856 ms. Request-stage median/p95/max are 0.585/0.745/2.746 ms;
coverage-stage values are 0.844/1.073/2.947 ms. No scheduling hitch was observed
in this short run. Cache eviction did little work (maximum 0.011 ms), so this is
not a pressured-cache eviction benchmark. The first integration attempt exposed
a missed loading-gate caller of the removed helper; it was corrected to use
published native root membership before the passing run. The validation runner
now retains captured diagnostics when a process reaches its timeout.

All 25 native terrain regression checks pass, including concurrent isolated
worlds, cancellation, reset and serialization. Six mesh/field/snapshot hashes
match the historical legacy bridge evidence exactly. Core addon isolation and
resource-boundary auditing pass as well.
The exported pack starts with eight native libraries. Its headless smoke run
records a separate 58.63 ms `collision piece` construction event, retained in
`pack_smoke.log`. Collision construction is not migrated by this change and
remains an unresolved source of stalls.

## Platform and remaining work

The rebuilt Windows debug/release libraries use pinned Zig and the prebuilt
godot-cpp SDK; no SDK sources are rebuilt. The facade fails startup clearly if
the planner class is missing. The retained legacy Linux library has not been
migrated to the typed binding and does not support this facade revision; a
current Linux build and validation remain outstanding. Existing terrain packet,
mesh, edit and save formats are unchanged, while the DLL-based derived-cache
fingerprint changes as usual on native rebuild.

Native queue ownership, sparse region streaming, generator redesign, collision
readiness under high-speed travel, remaining GDScript hot paths and multi-hour
performance verification are still unfinished.

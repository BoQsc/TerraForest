# Regional 3D water connectivity and opening elevations

2026-10-11. NativeWaterTopology extracts the next geometry-compiler intermediate:
positive-density tetrahedra and their open shared faces below the source ceiling.
For each node it records the lowest positive-air elevation; each connection records
its opening elevation. All values derive from the retained sampled3D terrain, not
an outdoor height field. Shared face adjacency is now defined once for lake flooding
and graph extraction. Original implementation remains0BSD with no new dependency.

42 checks pass in debug and a clean release project. A sampled ridge disconnects
two basins below3m and connects them above3m. A sealed lower chamber stays excluded;
a side shaft connects stacked spaces while the roof stays solid. Independent graph
traversal validates the elevations. Budget1 and32 output identical graphs. Two
regional pieces, deduplicated by endpoint/elevation, reconstruct the full edge set
exactly. Restored bake geometry produces identical nodes/elevations/connections.
Caller mutation does not modify the retained native graph.

A separate headless integration carves a sphere through the actual native terrain
API, samples its edited density in45 slices, and extracts a16-cubed regional graph.
The seed and cross-region connections are present. It has11,636 nodes,22,961 edges,
640 external regional connections and368,620 retained graph-buffer bytes.64 calls
at budget64 complete extraction; the largest measured call is140us on this host.
This is an in-memory terrain edit, not a saved-world fluid simulation.

## Bounds and contract

Regions are1..16 cells per axis. A call processes1..256 cells, checking elapsed time
against2ms every32 cells. Each cell has six tetrahedra and at most24 face visits.
Buffers are preallocated before stepping and trimmed on publication: maximum
1,376,256 bytes for a16-cubed region, excluding its retained immutable source.
The2ms check is not a hard wall-clock bound. Region setup and final publication are
bounded but not split into separate steps. Completed tasks do zero further work;
partial graphs are not published. Typical2048-cell analytic fixture retains181,904
bytes; largest measured budget32 call98us debug,47us release. These are short
headless extraction timings, not game frame/thermal or large-world qualification.

Edge tuples are (min_tetrahedron_id,max_tetrahedron_id,opening_mm). Node IDs are
indices in ONE immutable source grid, not world-persistent/network identities.
Only graphs from the same source geometry may be joined. IDs/ports from different
grids or edit versions must never be silently merged. Boundary connections reference
neighbor nodes outside the regional piece, allowing explicit later stitching.
Opening elevations round upward to millimetres; positive aperture requires head
strictly above that threshold. This may conservatively delay opening by up to1mm
and belongs in the future geometry/profile approximation budget.

## Still incomplete

This graph is not the compact basin hierarchy or storage profile. Next reduce
height-connectivity events into basin groups, assign storage without double
counting and compile bounded-error capacity curves for NativeWaterSettling. Do not
turn every tetrahedron into a persistent independently simulated basin. Intermediate
graphs need bounded build concurrency and retirement after compact data publishes.

The current input is a ready NativeLakeVolume, so it describes its seed-connected
potential region below its fixed ceiling. It does not yet compile arbitrary open
world regions directly from raw terrain. The future raw-terrain input must preserve
outgoing boundary ports instead of requiring an entirely sealed lake. This is
necessary for flow between source domains and cannot be replaced by enlarging a
single global lake indefinitely. Terrain invalidation/rebuild/remapping, external
port readiness and authoritative quantities across regions remain unimplemented.
No gameplay, world save format, bucket interaction or transient flow changed here.

The first test compared a restored graph against a script dictionary whose packed
array had deliberately been edited. The test now retains the native task, verifies
its published graph stays unchanged, and compares restoration with an untouched
copy. The failed fixture log is retained; no native connectivity expectation was
relaxed.

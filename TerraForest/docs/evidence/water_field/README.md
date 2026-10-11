# Open raw-terrain water geometry and versioned boundary addresses

2026-10-11. NativeWaterField admits immutable raw 3D density without requiring a
closed lake, initial water level occupancy or seed-connected flood. NativeWaterTopology
and NativeWaterProfiles share a read-only density view for the existing lake source
and this new source. Unconnected caves are preserved rather than discarded by a
selected seed. Original implementation remains 0BSD with no additional dependency.

36 debug/clean-release checks pass. Two independent adjacent fields agree on 288
reciprocal face openings in world-grid coordinates. Every outgoing graph edge has
an address record. Partial border data, nonfinite density, reconfiguration and
integer-extreme region coordinates are rejected; caller mutation does not change
published samples. Budget 1 and 128 preserve graph/port output exactly. Open terrain
is marked as requiring stitching. Two disconnected caves remain two roots. An
enclosed raw cave passes the existing storage compiler and retains an exact finite
1,000,000 ml input through native settling. Existing topology (42), profiles (44)
and same-snapshot joins (36) regressions pass with the new density abstraction.

11 further checks use the actual native terrain API. Sampling an open outdoor area
publishes 6,859 nodes in 27 budget-256 calls (largest measured call 375 us). Its graph
has 12,000 air nodes and 1,005 outgoing ports. Excavating while a different snapshot
is partly sampled cancels that builder with status -4, and the cancelled builder
cannot publish a graph. A fresh snapshot completes at the new revision. Switching
TerrainCore objects between slices is also rejected.

## Input and ownership contract

A field owns 3..18 cells per axis, plus corner samples, at integer spacing 1..8.
Topology owns 1..16 cells per axis strictly inside the field: one sampled border
cell is mandatory on every side. Snapshot samples are finite and bounded by
absolute density 1,000,000. World coordinates remain within +/-100,000 metres;
ceiling is an explicit millimetre value. Density payload is at most 27,436 bytes.
configure publishes an already-sampled field; its finite-input scan is bounded
but synchronous. This is immutable geometry, not the presence or quantity of water.

begin_terrain and sample_terrain provide a native worker-owned incremental adapter.
The current TerrainCore domain is still x/z 0..2000, y 1..255; unsupported grids
are rejected rather than silently shifted. Calls accept 1..2,048 nodes, check
elapsed time every 32 nodes, and verify revision AND cancellation epoch before and
after each slice. Terrain object identity is bound on the first slice. No partial
or cancelled snapshot may enter topology compilation. World IDs supplied by the
caller still require an authoritative world/region registry; they are not proof
of ownership by themselves.

Graph metadata carries world ID, geometry revision, cancellation epoch, spacing,
ceiling and lattice origin. Internal node IDs remain local to that snapshot.
world_ports contains nine integers per outgoing face:
(owner_cell_x, y, z, tetrahedron, neighbour_cell_x, y, z, tetrahedron, opening_mm).
Coordinates are integer lattice coordinates; spacing converts them to world metres.
The owning endpoint is first, so neighbouring records are reciprocal, not identical
in direction. Matching must include world/grid compatibility and expected revisions;
coordinate equality alone must never authorize exchange.

Topology preallocates at most 110,592 extra bytes for world-addressed boundary
records, in addition to the existing bounded graph buffers. Native sampling and
extraction have operation limits with soft 2 ms checks, not hard real-time deadlines.
Latest raw extraction peaks were 1.382 ms debug and 0.579 ms release; an earlier
build observed a 3.114 ms call. No sustained frame, thermal or large-world claim.

## Remaining integration

Legacy begin_join deliberately rejects raw fields: it only joins pieces of the same
closed source and cannot validate independent world-region ownership. A versioned
region registry, reciprocal-port readiness, exchange/backpressure and stale-update
rejection are next. Open or disconnected raw forests are still ineligible for the
closed NativeWaterProfiles/NativeWaterSettling handoff; they must not be falsely
sealed to bypass this limit. Quantity remapping/displacement after edits, controlled
profile accuracy, water runtime/rendering, buckets and atomic saves remain open.
Playable lakes still use their static path.

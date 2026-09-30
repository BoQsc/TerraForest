# Large-area region reuse feasibility

The native probe covers two 256 m areas (origins 896 and 1280), each containing
64 independently reconstructed 32 m columns. It simplifies each column with the
pinned meshoptimizer, border locking enabled and component pruning disabled.
Three successive radius-2.5 excavations exercise an interior, an edge and a corner.
Affected columns immediately use fine geometry; other columns retain their coarse
indices. No runtime addon defaults or gameplay integration change.

## Decision: do not adopt this column aggregation as the mining solution

- All six edits selected exactly 1, 2 or 4 columns. Full fresh reconstruction of
  all 64 columns after each edit matched every retained geometry and normal array.
- Neighbor boundary edge multisets matched. However, four cave-area columns gain
  edges incident to **four triangles** during simplification. These are internal
  nonmanifold edges, not neighbor cracks. Exact witness coordinates are retained.
- The mountain area's coarse aggregate has **67,086 triangles**, versus **5,846**
  from the old 256 m mesher. These representations are not quality-equivalent;
  the 11.5x count is a headroom warning, not a measured FPS ratio.
- After the three edits, visible triangles rise to 177,366 in the mountain area
  and 239,038 in the cave area. Deferred coarsening is absent in this experiment.
- A corner edit replaces 67,374 / 104,868 triangles and an estimated 2.75 / 4.28 MB
  of packed render data. This counts compacted v5 vertices and indices, excludes
  collision, and assumes independently replaceable region buffers. Repacking one
  combined draw buffer would add work that this experiment does not measure.

The small 15-mesh simplification corpus did not expose these four nonmanifold
outputs. Preserve these larger fixtures in subsequent simplifier qualification.
The probe intentionally exits 1; do not mask failure by only checking neighbors.

## Architectural consequence

Local reconstruction must be bounded vertically as well as horizontally. A small
excavation should not rebuild an entire 256 m tall column, including its remote
caves and underside. Distant aggregation also needs a hierarchy that can remove
internal fine boundaries; fixing every 32 m boundary at full detail is not yet a
qualified distant representation. These are separate requirements: smaller edit
regions alone do not establish distant rendering headroom.

## Measurement limits and reproduction

`python tools/probe_terrain_region_aggregate.py` uses pinned Zig/prebuilt SDK
discovery and builds only a native probe. It does not launch a human playtest.
The report separates reconstruction/normal time from diagnostic edge-map time.
Cold preparation includes simplification; legacy `build_patch` also includes
shading, so the timing columns are not an equivalent-work speed comparison.
Single-case observations are not latency percentiles. Error bounds, material
preservation, snapshot capture, shading, packing, GPU upload, collision, retirement
and fullscreen/endurance performance remain unqualified. Evidence and source
hashes are retained in `evidence/terrain_region_aggregate/report.json.gz`.

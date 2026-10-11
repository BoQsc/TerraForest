# Connected partial-cell water: verification and costs

2026-10-11. Native Windows debug/release builds use the pinned Zig/prebuilt SDK.
Original failure remains in ../water_shoreline_queries at commit e551349.

## Change

Six tetrahedra per cell share a consistent cube diagonal. Flooding crosses only
faces with positive-density area below fill elevation. Published boundary queries
select one tetrahedron and interpolate four retained density values; fully wet
cells keep a byte lookup. Surface extraction intersects that same representation.
No runtime terrain reads, surface scans or per-cell simulation were added.
Root queries use connected volume plus the existing 0.35m ground-contact tolerance,
instead of vertically extruding a wet column through potentially dry chambers.

Bake version 2 retains connectivity and density. Version 1 is rejected/rebuilt;
canonical lake definitions/IDs are unchanged. Derived file bound is now 8 MiB.
The checksum is corruption detection, not authentication. The decoder validates
shape, finite data, masks, seed and mesh indices; it does not recompute the entire
connectivity graph for deliberately forged, correctly checksummed local data.

## Evidence

- Shoreline: zero missing answers at all four original depths: 0/718, 0/175,
  0/84 and 0/62; the fixed 128-by-128 cross-section also has no missing free-space
  points. Cold/restored results agree. These are samples, not area percentages.
- Water regression: all checks pass, including bounds, negative/scaled coordinates,
  islands, roof, open-boundary rejection, actual terrain and local cache invalidation.
- Topology: cold/restored partial shore, solid shore, sealed chamber, thin dividing
  wall, disconnected basin, shared cell faces, fill boundary and root contact pass.
- Codec: 32 debug and 32 clean release checks pass, including old-version rejection,
  invalid tetrahedron bits and nonfinite retained density.
- Vegetation and smooth surface fixtures pass. Surface winding, UVs and solid
  exclusion are checked independently against the analytic field.
- Actual generated cave creation/edit/save/reload: 17 checks; fresh process: 3 checks.
  Source world unchanged. Surface screenshot inspected at 1920x1080; no obvious
  shoreline holes or cell-sized staircase outline in this view.
- Cold generator4/seed1703: all four lakes ready at 5.368s, under the unchanged 30s
  gate. Water-page removal/restore checks pass. This run is not an A/B speed claim.

## Costs and limits

Retained volume = 2*cell_count + 4*node_count bytes, excluding surface and the
legacy one-byte-per-column index. At 64 cubed: 1,622,788 bytes (1.55 MiB), compared
with the previous 262,144-byte occupancy. Sixteen such volumes would use roughly
24.8 MiB before surfaces/indexes. Boundary flood queue adds at most 6*cell_count
uint32 entries while baking; it is freed before publication.

Measured on current hardware, not an older-laptop qualification:
- Curved 32x12x32 basin: 3.206ms bake, 81,204 volume bytes, 21,600 surface bytes.
- Full 64-cubed budget: 96.102ms bake. Finalization is still indivisible worker work.
- 100,000 partial-cell queries: 42.918ms including GDScript construction/dispatch;
  this is not isolated native timing or an in-game frame budget.
- Four-lake cold worker total355.134ms, maximum slice39.132ms, maxqueue310.014ms.
  A terrain receive hitch66.82ms appears during restoration and remains recorded.

The old water tests compared the legacy whole-cell rectangle surface with the now
more accurate point queries. Those two failing expectations were replaced with
explicit conservative-cell geometry checks; the smooth-surface regression remains
separate. Old one-byte memory expectations were replaced by the exact new formula.
The formerly accepted sub-cell edge opening now rejects the lake as unsealed;
this is a deliberate stricter correctness policy, not a fallback to a smaller mesh.
Original contract failures are retained beside passing logs.

One loading run omitted generator4, created zero lakes and failed/timed out.
Its log is retained as incorrect_invocation, not a runtime regression comparison.
The fixture now exits cleanly if the required four records are absent.

This closes the measured shoreline/query mismatch. It does not qualify arbitrary
sub-grid terrain, maximum-size worker latency, long-run frame/thermal performance,
mass conservation, drainage, dynamic fluids, swimming presentation or all seeds.
Keep the bounded static representation; assess maximum-size finalization scheduling
before increasing lake limits or promising hitch-free edits.

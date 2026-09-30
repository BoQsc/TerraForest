# Independent incremental dual prototype: not qualified

This is project-authored 0BSD code with no Transvoxel dependency or lookup
tables. The Transvoxel experiment remains on `codex/experimental-transvoxel`.
No runtime addon behavior changes here.

The prototype combines a fixed adaptive cell layout, canonical shared grid
edges, one box-constrained regularized QEF vertex per cell, and a spatial index
of edge dependencies. Fine cells are 1 m in a central 16 m cube; surroundings
use 8 m cells. Faces connect the incident cell vertices around a shared edge.
An edit queries dependency buckets, reevaluates intersecting edges, refits their
dependent vertices, and identifies affected faces. It does not scan every cell
or rebuild an entire coarse patch during an edit.

## Combined gate results

`python tools/probe_terrain_incremental_dual.py` tests 32/64/128 m volumes using
an analytic sphere and the actual World field. Each scene receives three
successive excavations. Fresh reconstruction after every edit checks exact
vertex, edge crossing, normal, sign, and face-index equality.

- All 18 incremental updates match their fresh reconstruction.
- All 12 sphere rows and three initial real-world rows pass the topology checks.
- All nine edited real-world rows fail topology. The command intentionally
  exits 1 and `adoption_qualified` remains false.
- The 64 m and 128 m real-world cases perform identical local work:

| Successive edit | Reevaluated edges | Refitted cells | Field samples |
| --- | ---: | ---: | ---: |
| Interior | 13,926 | 176 | 30,582 |
| Boundary | 5,076 | 46 | 11,958 |
| Corner | 3,084 | 27 | 7,644 |

The complete layout grows from 4,600 to 8,184 leaves and from 14,994 to 24,618
shared edges between those two volumes. This is evidence of local update work
for a fixed layout, not a proof for arbitrary travel, growing edit histories,
or adaptive layout changes. The 32 m domain truncates some outer dependencies.

Initial construction still costs roughly 78–307 ms in the retained run. The
prototype uses map/set containers and repeatedly samples density; its cold
construction and memory usage are not suitable runtime performance claims.
Local timings are individual observations, with diagnostics and fresh-build
oracles excluded. Collision, materials, snapshot capture, upload, and publication
are also excluded. There is no new FPS or end-to-end mining result.

## Defects identified before integration

World page creation quantizes procedural samples. Sampling the procedural field
without the same quantization can therefore change geometry outside the edit's
reported bounds when a page is first allocated. The probe now canonicalizes
every lattice sample with the world's float rounding and uses those values for
trilinear evaluation. Exact incremental/fresh equality now holds in all cases.

The one-vertex-per-cell representation is not sufficient for the edited field.
Recorded witnesses include an edge shared by four triangles between two 1 m
cells with corner sign masks 122 and 18. Coarse cells also produce invalid edge
incidence. Vertex-link checks expose disconnected or branching neighborhoods.
No triangles are discarded or failures hidden to make these cases pass.

The next representation must retain multiple surface components per cell and
connect them consistently across shared faces. Refining only the coarse cells
cannot resolve a witness already present at 1 m. This requirement must be
tested with the retained witnesses before integrating the prototype into the
worker or stream. The local dependency index can be retained independently.

Missing gates include component preservation, feature/error bounds, hidden
surfaces with no sampled edge crossing, geometric self-intersection, arbitrary
neighbor configurations, moving/adaptive layouts, allocation limits, physics,
and the existing fullscreen mining/travel acceptance workload.

Reports, witnesses, build command and source hashes are retained under
`evidence/terrain_incremental_dual/`. The source is deliberately an isolated
prototype under `tests/native`, not a new production terrain backend.

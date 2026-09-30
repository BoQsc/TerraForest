# Independent incremental dual prototype: not qualified

This is project-authored 0BSD code with no Transvoxel dependency or lookup
tables. The Transvoxel experiment remains on `codex/experimental-transvoxel`.
No runtime addon behavior changes here.

## Current compact storage result

Neighbor ownership is now stored once for a shared edge interval instead of
repeated in every unit segment. A sweep over leaf-edge endpoints builds these
intervals. Unit segments retain stable IDs and sign flags, while crossing
positions and normals occupy reusable slots only when a crossing exists.
Dependency buckets and cell adjacency refer to intervals. Exact unit-segment
dependency filtering still determines which densities must be reevaluated.

The real-world sampler caches immutable procedural heights for its fixed world
instance. Editable density pages are read live; density values are not cached.
No worker/snapshot integration or reset lifecycle is implied by this test helper.

The profile compares the same 24 geometry cases and retains a source snapshot
for the measured pre-compaction version. All 24 geometry fingerprints match,
all 18 updates match fresh reconstruction, and every interval's ownership is
checked against independent unit-segment neighbor lookup. The existing topology
and missing-boundary-component gates remain enabled.

| World extent | Cold build before / after | Edge + dependency array capacity before / after |
| --- | ---: | ---: |
| 32 m | 63.0 / 44.6 ms | 2,348,944 / 2,285,728 bytes |
| 64 m | 129.3 / 81.3 ms | 3,896,080 / 2,514,912 bytes |
| 128 m | 625.6 / 326.7 ms | 17,965,072 / 6,064,736 bytes |

These are individual CPU observations, not timing percentiles or an FPS gain.
Capacity includes allocated edge/run, crossing-pool, and dependency array
storage, but excludes allocator/hash-node overhead, transient construction
buffers, field height caches, total process memory, collision and rendering.
Measured real-world local updates remain approximately 14.6–30.1 ms. This
prototype is still **not performance-qualified for the game**.

A separate 64-cycle carve/restore test reproduces the expected geometry, verifies
unique ownership of live/free crossing slots, and confirms stable allocated edge
capacity after warm-up. The final pool has 444 slots, 126 free. This is a storage
reuse test, not an endurance qualification or a demonstration of bounded memory
while exploring new terrain.

Evidence is in `profile_before/`, `profile_after.json` and
`profile_comparison.json`. Cold stage order is layout, indexing, sampling,
component fitting. Face connectivity construction and cold-streaming cost remain
substantial; moving layouts, feature fidelity and runtime publication still need
qualification before adoption.

## Component-aware result before compaction (`31b665c`)

The initial one-vertex implementation described below is superseded by a
component-aware prototype. Each active cell traces its boundary on a canonical
unit triangulation and fits a separate constrained QEF vertex per connected
surface component. Shared grid edges are represented as unit segments, so an
8 m edge can retain multiple crossings. A shared face uses identical samples,
diagonals and zero handling on both sides. The prototype rejects unassigned
active crossings and boundary loops without corresponding crossing ownership.
This does not detect wholly hidden surfaces in cells without active crossings.

All 24 existing rows now pass edge incidence, winding, nondegeneracy, and
vertex-link checks. The nine recorded real-world mining failures are fixed in
these fixtures. All 18 incremental updates still match fresh reconstruction
exactly, including component assignments. No faces are deleted to force a pass.

Connectivity depends on face samples in addition to edge intersections. Edits
therefore also visit active cell owners near changed samples. A cell whose
positions and component assignments remain unchanged does not dirty all of its
incident faces. Sorted edge keys and hashed owner/dependency lookups reduce
construction overhead while retaining deterministic output.

The final 64 m and 128 m real-world cases perform identical work:

| Successive edit | Reevaluated edges | Refitted cells | Affected faces | Field samples |
| --- | ---: | ---: | ---: | ---: |
| Interior | 13,980 | 465 | 822 | 39,778 |
| Boundary | 5,356 | 237 | 952 | 21,154 |
| Corner | 3,420 | 198 | 804 | 18,544 |

The correctness improvement has a cost. Shared edge records grow from the
baseline 24,618 to 99,840 in the 128 m scene. The first unoptimized component
implementation took about 2.6 seconds for that real-world cold build. After
removing recursive per-segment owner queries and tree-based edge insertion,
the final observation is 625 ms. Real-world local updates measure approximately
15–27 ms across the three volume sizes in the final run. These are individual
CPU observations, not percentile or end-to-end results. The new representation
is **not performance-qualified**, despite fixing the recorded topology failures.

`component_final.json` retains the final verified report and source hashes.
`component_initial.json` is an intermediate measurement report; its intermediate
source version was not separately snapshotted. The original failure report below
remains unchanged and is reproducible at commit `f49c628`.

The next requirements are compact hierarchical edge/face summaries, explicit
memory and cold-streaming budgets, and feature/error qualification. Unit edge
expansion across every coarse region must not become the production strategy
without proving its storage and traversal costs acceptable. Dynamic refinement,
coarsening, arbitrary layout changes, hidden features and runtime publication
remain unqualified. The existing fullscreen mining acceptance gate is still open.

## Historical one-vertex baseline (`f49c628`)

The prototype combines a fixed adaptive cell layout, canonical shared grid
edges, one box-constrained regularized QEF vertex per cell, and a spatial index
of edge dependencies. Fine cells are 1 m in a central 16 m cube; surroundings
use 8 m cells. Faces connect the incident cell vertices around a shared edge.
An edit queries dependency buckets, reevaluates intersecting edges, refits their
dependent vertices, and identifies affected faces. It does not scan every cell
or rebuild an entire coarse patch during an edit.

### Combined gate results

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

### Defects identified before integration

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

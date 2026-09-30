# Bound the candidate's crossing map to one height layer

The isolated tetrahedral candidate now retires crossing-map entries after each
cell layer. An edge can be referenced by a later cell only if both endpoints are
on the completed layer's top plane. Canonical endpoint IDs increase with Y, so
entries whose lower endpoint is below that plane are erased. Vertex/index output
remains intact; only temporary deduplication entries are retired.

For a region of width `size`, a layer has `size*size` cubes, each containing six
tetrahedra with six edges. Therefore `36*size*size` is a conservative bound on
crossing entries active during a layer, including retained shared-plane edges.
This is independent of height. It bounds entries, not allocator bytes or total
mesher memory. The unordered map still allocates individual nodes and retains
its peak bucket capacity.

## Measured evidence

Both implementations include the earlier sign-scan optimization. Five paired
alternating-order runs compare the rolling map against the retained whole-region
map for each of fifteen fixtures. All 75 pairs preserve every position/index byte;
all fifteen immutable geometry hashes and topology/partition tests still pass.
The probe passes 22 checks.

| Fixture | Retained-map peak entries | Rolling-map peak entries |
|---|---:|---:|
| Cave 32 m | 20,878 | 4,225 |
| Mountain 32 m | 8,450 | 4,225 |
| Edited mountain 32 m | 8,808 | 4,225 |
| Synthetic 8 m, 256 alternating layers | 73,984 | 289 |

The synthetic field changes sign at every height layer, forcing geometry through
the entire vertical extent. Its output is byte-identical between implementations.
Peak bucket counts fall from 102,877 to 397 in that case. The synthetic fixture
tests deduplication lifetime and storage, not realistic terrain quality.

There is no demonstrated speed improvement: sums of fixture median meshing times
are 32.60 ms for the retained map and 32.78 ms for the rolling map (0.6% slower).
Individual ratios range from approximately 0.93 to 1.10. Map retirement occurs
inside rolling meshing; final result destruction is outside both timed sections.
These are warm-field microbenchmarks with timing noise, not gameplay measurements.

Keep this as a candidate memory tradeoff. It prevents temporary map growth with
vertical surface complexity without changing geometry. Dense density buffers,
output vertices/indices, allocator behavior and overall latency remain separate
work. The diagnostic retains both control and candidate results, so its process
memory is not a production memory measurement. No game DLL changes or adoption
qualification follow from this probe.

Run `python tools/probe_terrain_tetra.py`. Evidence and source/toolchain/executable
hashes are in `docs/evidence/terrain_tetra_edge_storage/`; previous evidence remains
unchanged. Earlier reports compare sign scanning against the original loop;
this report compares rolling versus retained maps with sign scanning on both.

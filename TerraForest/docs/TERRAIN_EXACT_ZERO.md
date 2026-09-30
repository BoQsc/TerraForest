# Exact-zero lattice merging: partial correction, collision still rejected

An opt-in `MeshLimits::exact_zero_vertices` mode merges intersections attached to
an exact-zero sample at that lattice vertex. A checked two-plane vertex table
shares its index across incident tetrahedra. Triangles whose indices collapse
are omitted as part of that merge; no area threshold removes noncollapsed faces.
The default displaced-zero behavior and its immutable fixture hashes are unchanged.

Run `python tools/probe_terrain_exact_zero.py` for topology, then
`python tools/probe_terrain_candidate_collision.py --exact-zero --godot PATH`.
The retained reports are in [evidence/terrain_exact_zero](evidence/terrain_exact_zero).

All fifteen variant meshes pass duplicate-face, zero-area, edge incidence, winding,
vertex-link and interior-boundary checks. All three parent/four-child partitions
match exactly. The unchanged default candidate also passes its existing 54 checks.
These results establish fixture behavior, not general validity for arbitrary
zero plateaus or saddle configurations.

All 21 original failed ray locations now hit within the original 0.002 m tolerance.
Those rays are copied from frozen failure evidence rather than regenerated from
new triangle indices. The variant's 180 newly sampled triangle-center rays yield
179 hits and one miss. The remaining miss is mountain parent triangle 8960 near
(1300,108,1306), with cross-product length 3.757097e-5. It is away from the bottom
zero plane, demonstrating that exact-zero merging alone does not solve thin-face
intersection robustness. Overall collision report: 66 passing checks, one failure.

Keep this mode experimental. Its additional allocation, cancellation, normal
behavior at exact lattice vertices, arbitrary zero configurations and collision
conditioning need qualification. No production default or acceptance threshold
changed. Next investigate the surviving nonzero thin triangle and an explicit
collision/geometry conditioning contract, retaining topology and local partition
constraints; do not treat recovery of the original 21 rays as overall success.

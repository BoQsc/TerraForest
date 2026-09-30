# Direct coarse terrain feasibility — archived experiment, not adopted

Preserved on `codex/experimental-transvoxel` at the user's request. Do not resume
runtime adoption of this experiment without further direction. The active
foundation work continues without these tables or this experimental dependency.

The existing fullscreen brick run still fails the mining acceptance gates.
This experiment asks whether coarse reconstruction can avoid extracting and
simplifying the fine surface of an entire 256 m patch. It changes no runtime code.

## Real terrain measurement

`python tools/probe_terrain_transvoxel_world.py` builds two 256 m patches at
origins (896,896) and (1280,1280), before and after a radius-2.5 excavation.
It samples the actual World density at steps 4 and 8 and constructs regular
Marching Cubes cells using the official Transvoxel regular tables. No fine
surface or simplification pass is constructed.

Initial measurement, before adding the explicit zero-density tie rule:

| Step | Samples per patch | Sampling + geometry, observed | Triangles |
| --- | ---: | ---: | ---: |
| 4 m | 274,625 | 62.6–72.0 ms | 17,652–23,078 |
| 8 m | 35,937 | 9.4–11.3 ms | 4,362–5,774 |

All eight cases have zero internal open edges, overused edges, inconsistent
shared-edge winding, or zero-area triangles. Diagnostics run after the timed
construction. Sampling currently calls World.sample independently per point;
it does not reuse column heights. These cases contain no exactly zero samples.

These are single observations, not percentiles or a matched comparison with
legacy build_patch, which also performs other work. The probe does not measure
normals, shading, materials, snapshot capture, collision, upload, publication,
loaded edit history, frame rate, or endurance. Edge checks do not prove vertex
manifoldness or approximation quality. Small caves and excavations can be lost
by coarse sampling; triangle counts alone cannot establish feature preservation.

## Transition evidence and missing gate

The separate join probe originally checked 512 sign patterns in six orientations
and three nonzero magnitude/coordinate profiles: 9,216 synthetic assembled cases.
It uses an expanded transition slab and extruded densities. Exact edge incidence,
winding, and nondegeneracy pass for these profiles.

Two additional profiles expose the exact-zero requirement. With raw zeros,
101 of 512 patterns fail per orientation, including degenerate triangles and
overused edges. The same inputs pass when the regular and transition primitives
both replace zero with positive half a density quantum (0.5/1024). This shared
tie rule is now implemented in the test wrapper, with an explicit raw bypass
for the rejection witness. No triangles are silently discarded. The exhaustive
runner deliberately exits 1 because it includes that raw rejection profile;
the nonzero and zero-biased profiles all pass. This is not a guarantee against
every tiny-face or physics failure.

`python tools/probe_terrain_transvoxel_field_join.py` additionally builds 96
single-face interfaces in the actual terrain: two sites, before/after mining,
six directions, and fine steps 1/2/4/8 m. All cases contain geometry and pass the
edge/winding/degeneracy checks. All 48 edited cases change their mesh. The test
uses regular Marching Cubes on both sides, not the current tetrahedral mesher.

The fine boundary is displaced inward by one quarter of its step and the coarse
boundary stays at the shared world plane. This bounds that prescribed boundary
movement to 0.25/0.5/1/2 m, but does not bound surface approximation error.
The maximum sampled absolute trilinear density residual at transition vertices
and centroids is approximately 0.60/0.65/1.73/3.82 for those four steps. Those
numbers are density units, not distance bounds. No normal-projected displacement
or visual/error admission policy has been implemented. Multiple transition faces
meeting at corners remain untested, as do vertex manifoldness and physics.

The coarse tables alone must not be connected directly to the existing fine mesh.

## Six-face assemblies and displacement correction

The final corner probe assembles a complete fine cube, six transition faces,
and an enclosing coarse shell. It checks paired edges, winding, nondegeneracy,
and connected vertex links. Negative controls distinguish two closed surfaces
touching at one vertex from a manifold surface and detect a removed face.

All 56 cases pass these structural checks with both displacement modes: 32
synthetic plane/hash/sphere cases and 24 real-terrain cases. Each of six real
excavations changes density samples and the resulting meshes at all tested
steps. Excavations cover an interior, a face, and a three-face corner.

The inward-only placement visibly distorts even planes. A shared optional
vertex projection now removes the normal component of that displacement,
using central-difference gradients at the canonical undisplaced position.
The real-world fixture evaluates the continuous trilinear density for these
gradients. Matching faces use identical positions and calculations.

At 1 m fine resolution, maximum sampled plane error falls from 0.14434 m to
0.000177 m. At 2 m it falls from 0.28868 m to 0.000177 m; at 4 m from 0.57736 m
to 0.00527 m. Remaining coarse sampling error is significant: the worst sampled
sphere-to-mesh distance remains about 0.338/0.675/1.280 m for those three steps.
Mesh-to-sphere maxima with projection are about 0.335/0.670/1.263 m.

These are sampled witnesses, not certified Hausdorff bounds or an accepted
visual-error policy. The error metrics do not contribute to the structural
`passed` field. Adaptive mixtures of fine/coarse neighbor masks, geometric
self-intersection, rendering normals, cost of the extra gradient queries,
physics, streaming and end-to-end mining latency remain unqualified.

Run `python tools/probe_terrain_transvoxel_corner.py` for projected placement,
or add `--unprojected` for its comparison. Both final reports and source hashes
are retained. The earlier exhaustive and single-face outputs remain unchanged
after introducing the optional projection callback.

## Licensing boundary

Project-authored code remains under the existing 0BSD license. The isolated
test vendor directory contains Eric Lengyel's MIT-licensed Transvoxel tables,
pinned by commit and SHA-256, with their license preserved alongside them.
They are not part of the runtime extension. Distribution of these third-party
files retains their MIT notice requirements; they are not 0BSD material.
Using them in a future runtime would require preserving those notices there too.

Evidence and source hashes are retained under `evidence/terrain_direct_coarse/`.
None of these reports qualifies this algorithm for runtime adoption.

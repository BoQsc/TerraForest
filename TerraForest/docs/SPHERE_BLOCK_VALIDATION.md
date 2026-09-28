# Native sphere blocks

Shape code 6 adds a one-metre-diameter spherical building cell to the structures
addon. Meshing remains in the native worker, using a shared 91-vertex indexed
template with 120 nondegenerate triangles. Shading normals are radial, while
physics uses the same faceted triangle mesh. Integer longitudinal texture repeats
avoid a discontinuity at the UV wrap. There is no per-sphere scene or physics node.

Debug and isolated release runs of `tests/structures.gd` pass 209 checks,
including all existing building/streaming/prefab/history checks and new coverage:

- All four rotations and materials, fixed vertex/triangle counts and clockwise
  winding. Radius readback error was zero at the tested tolerance; maximum normal
  readback error was about 0.000103, checked against a 0.0002 threshold.
- Exact sphere snapshot round trips, rotated native prefab capture/placement,
  negative chunk seams, and undo/redo.
- Curved geometry omitted behind six full cube neighbours and restored after
  removing an enclosing face in another chunk.
- Physics rays reaching the top pole/equator while missing the cell corners.
- A 4,096-sphere chunk exceeding a 1 MiB mesh admission budget retains authored
  cells while keeping its oversized visual mesh out of residency.

These tests establish bounded geometry and integration, not equivalence to the
cost of cubes. A dense cube chunk can merge into 12 triangles; a dense sphere
chunk can require 491,520. Sphere LOD and analytic sphere physics are not present.
Native build reports retain the exact debug/release DLL hashes and confirm zero
godot-cpp sources rebuilt against the pinned Zig/prebuilt SDK.

Existing saves remain readable. Older builds reject the newly assigned shape
code, so saves containing spheres require this or a later structures build.
The editor still requires nearby collision to finish admission before reliable
surface picking; high-speed collision readiness remains pending.

The integrated main-world test passes 135 checks at 1920×1080 fullscreen and full
render scale. It selects shape 6 through the actual editor input handler, waits
for the construction support collision, places all four material variants,
confirms terrain density is unchanged, and validates/restores the compound world
snapshot. Geometry and vegetation reconciliation settle after restoration.
The sphere screenshot, logs and build hashes are retained in `evidence/spheres/`.
The screenshot is visual evidence, not a dense-sphere frame-rate benchmark.

# Round column validation — 2026-10-16

Native shape 7, 12 sectors, 54 vertices, 48 triangles. Debug and release DLLs rebuilt with Zig and prebuilt godot-cpp. Graphical debug check rendered at 1920x1080 fullscreen, capped at 60 FPS; this is functional evidence, not a timing benchmark.

- Four materials and four rotations use the production paid placement coordinator.
- 48 top/side rays match actual physics collision and authored picking within 1 mm.
- Nondegenerate outward winding, empty corners, normal block removal/undo, exact native snapshot restore and rotated prefab placement pass.
- Solid sampling/hull export regression covers all seven shapes and four rotations, plus transformed/unavailable cases.
- Existing block lattice geometry hashes remain exact.
- Inspected materials.png: all four material rows render with visible caps and curved sides.

The rejected first test registered later inventory item types after mutations, which the inventory rejects; it also started top rays inside stacked columns and called free on a RefCounted inventory. The corrected fixture registers the catalog first, separates columns and lets reference counting release inventory. No product change was made to make those failures pass; the rejected log is retained.

Limits: no dense-column frame/thermal qualification, no dedicated curved LOD or adjacent-cap merging. Existing world save IDs stay valid; newly authored shape 7 requires updated binaries. Main-world manual selection and human traversal of column assemblies are not covered here. Water remains deferred.

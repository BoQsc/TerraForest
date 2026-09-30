# Native LOD decision probe

Tested Godot 4.7.2's ImporterMesh generator on all 15 C++ candidate meshes before
implementing a new simplifier. SurfaceTool generates normals natively first.
The timed LOD generation is native code; GDScript only drives the test and writes
results. No game/addon implementation changed.

The generator produced 67 LODs. All 15 base meshes retained exact input geometry.
**61 LODs preserve exact boundary edge multisets, component counts, Euler
characteristic and absence of overused edges. Six fail.** The runner exits 1;
passing individual levels are candidates for further testing, not qualified LODs.

| 32 m input | Input triangles | Coarsest generated triangles | Complete LOD generation ms |
|---|---:|---:|---:|
| Cave | 40,858 | 894 | 78.66 |
| Mountain | 16,384 | 514 | 37.03 |
| Edited mountain | 17,100 | 534 | 40.86 |

These parent outputs preserve the tested boundaries and topology counts. In
contrast to the current terrain simplifier's edit pinning, the native generator
can reduce edited geometry. Shape error and rendered appearance have not yet been
accepted, so triangle reduction alone does not justify using these levels.

## Concrete rejection

The coarsest LOD of three cave children changes from three connected components
to one, removing 256–258 boundary edges. Removed boundaries span the bedrock
underside and upper terrain. Three edited children change from two components to
one, removing 128 boundary edges on the underside. Component loss, not just a
different triangulation of the same boundary, is measured here.

The engine source for the running revision enables both border locking and
component pruning. Its public generate_lods binding does not expose a pruning
switch. This is consistent with the observed component removal; border locking
alone must not be assumed to preserve an independently streamed region's whole
surface. See the [pinned engine implementation](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf001b61586d9930840f2f1394092c079/scene/resources/3d/importer_mesh.cpp)
and [public API](https://docs.godotengine.org/en/stable/classes/class_importermesh.html).

The prototype includes underside geometry that the existing mesher often omits;
underside removal is not itself proof of a visible gameplay hole. Nevertheless,
the cave cases also lose upper boundaries, and component pruning violates this
test's explicitly conservative independent-region contract. Do not silently
select every LOD returned by the importer.

## Decision and limits

Reuse of mature native simplification is promising. The next candidate needs
explicit boundary locks, component pruning disabled, and a geometric error
criterion suitable for edited caves. Earlier passing levels remain useful
comparison points; failure of the last levels does not invalidate the entire
simplification approach.

This test does not establish Hausdorff error, tunnel clearance, material/UV
preservation, self-intersection freedom, full vertex-link topology, collision
behavior, GPU headroom or integrated edit latency. Engine LOD size/error values
are recorded but are not independently verified distance bounds. Normals and LOD
timings are separate single-run observations, not percentiles. All graphical
qualification still requires 1920×1080 fullscreen and full rendering scale.

```text
python tools/probe_terrain_tetra.py
python tools/probe_terrain_lod.py --godot PATH
```

The second command intentionally rejects the six outputs. Raw metrics, input and
output mesh hashes, script hashes, engine version and logs are retained in
`docs/evidence/terrain_native_lod/`. The report's eligible_levels means eligibility
under boundary/topology-count checks only; adoption_qualified remains false.

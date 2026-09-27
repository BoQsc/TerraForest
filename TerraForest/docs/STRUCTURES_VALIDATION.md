# Independent block structures validation

This implementation replaces the proposed terrain-stamp direction for construction. `addons/structures` has no dependency on the terrain addon. It keeps crisp, textured geometry and distinct block data; terrain density is not modified.

## Reproduce

Using the existing Godot executable with `--godot PATH` where necessary:

```text
python tools/build_native.py --addon structures --target all
python tools/validate.py --test structures --godot PATH
python tools/test_native_release.py --addon structures --godot PATH
python tools/test_isolation.py --godot PATH
python tools/run.py --scene structures --godot PATH --capture-structures
```

The native test checks actual mesh surface area and triangle winding, positive/negative chunk seams, material boundaries, shape rotations, rejected edit atomicity, RLE/checksum round trips, stale worker rejection, empty chunk/queue reclamation, physics ray hits on staircase treads and slopes, physics residency and static model input validation. The same script runs against the release DLL in a fresh project containing only the structures extension. No terrain library is present in that release test.

The 100,000-instance check is an API/storage/batching test using a shared box mesh, not a GPU city benchmark. Its 49 MultiMesh groups contain 4,800,000 bytes of transform payload; that excludes renderer overhead and source mesh resources. Dense 16³ solid cubes become 12 triangles and a 60-byte checksummed RLE snapshot. Those results describe regular solid geometry, not worst-case fragmented buildings.

The graphical capture uses the existing GTX 1060 Max-Q, Forward+, 1920×1080 exclusive fullscreen. It records 240 frame intervals after baking, with a stationary camera. Recorded frame intervals are wall-clock presentation-loop timings, not isolated GPU timings. No terrain, moving population, networking, city streaming or high-speed travel workload runs in this scene. Debug/release headless timing samples may overlap other checks and are diagnostic only.

Current logs, measurements, native build hashes and original screenshots are retained under [evidence/structures](evidence/structures). The showcase comprises a house with openings and porch, a tower frame with interior floors/stairs, a ramp, shape examples, and 344 static fence/ladder pieces in seven spatial model batches. It is an architecture/authoring demonstration, not a finished architectural asset library.

Recorded result: **86/86 native checks in debug and release**, four independent addon startup checks, and 31 existing terrain/forest integration checks. The final showcase contains **9,469 block cells in 51 chunks, 7,502 triangles, and 417,792 bytes of cell payload**. The stationary graphical sample recorded a 2.372 ms median and 2.596 ms p95 frame interval under the restricted workload described above. These figures are not a city-scale performance guarantee.

## Remaining limitations

All resident building meshes remain loaded up to the explicit 2,048-chunk cap; region eviction, disk bake caching and distant LOD are absent. Wedge boundaries are conservative. Collision generation is near-focus and limited to one new body per frame, but high-speed readiness is not implemented. Imported meshes can share the static batching API, but asset catalogs, stable placement IDs, incremental placement edits, collision proxies and serialized model references are pending. The standalone showcase's basic block save is not integrated with the crash-resilient compound world archive. No multiplayer or long-duration production claims are made.

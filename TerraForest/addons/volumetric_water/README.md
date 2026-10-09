# Volumetric water — static lake implementation

Independent C++ GDExtension built with the pinned Zig/prebuilt godot-cpp toolchain. Windows x86-64, Godot 4.7, single precision. Copy this addon alone to use `NativeLakeVolume` with your own sampled density fields. `lake_world.gd` optionally integrates with TerraForest's terrain worker protocol.

This implementation stores a **three-dimensional connected water volume**, not an infinite plane. Water occupancy and depth queries use the volume; its surface mesh is a rendering derivative. No simulation runs over resident water cells each frame.

## Representation

- Finite voxel grid; maximum 262,144 cells per lake, dimensions up to 128×64×128 within that total.
- Density nodes use X-fastest indexing: `x + (width+1) * (y + (height+1) * z)`. Positive density is air.
- A cell is eligible only when all eight corners are air and its bottom lies below fill elevation. This conservatively erodes the shoreline by roughly one cell. Features thinner than the sample spacing are unresolved.
- Six-connected flood fill from an explicit submerged seed selects a single component. Disconnected chambers stay dry. Connected cave cells can be occupied below the fill elevation.
- Reaching any lateral or bottom boundary rejects the entire bake. Water is never silently truncated at an unsealed region edge. The top is above the fill level by configuration.
- Successful volumes retain one byte per cell; density and flood queue scratch are freed. Published volumes cannot be reconfigured or rebaked.
- Query cost is constant per volume. The scene adapter checks at most 16 bounded lake records (default 8). Idle lakes have no per-voxel update loop.
- Surface extraction greedily merges occupied rectangles in X/Z, emits only the fill-level surface, and omits submerged internal faces. Rectangular basins need one quad; islands and irregular shorelines stay dry. Extraction uses a bounded 16 KiB local mask and leaves published occupancy immutable. One MeshInstance per lake allows whole-lake frustum culling.

## Native API

| Method | Contract |
| --- | --- |
| `configure(origin, cells, spacing, fill_level, seed)` | One-shot bounded builder; spacing 1–8 m; fill strictly inside vertical extent; seed below fill and inside bounds |
| `bake_density(PackedFloat32Array)` | Complete finite density field; atomic rejection of malformed inputs |
| `sample_terrain(core, budget, revision, epoch)` | Worker-only adapter to the inherited terrain ABI; integer-aligned grid and spacing; up to 2048 nodes per slice |
| `contains(point)` | True only inside a ready occupied cell and below fill level |
| `depth_at(point)` | Fill elevation minus point Y when occupied; zero outside |
| `surface_arrays()` | Native-generated Godot ArrayMesh channels; main thread creates the rendering resource |
| `statistics()` / `bounds()` | Budget, bake state and AABB information |

Status codes: `0` needs another slice, `1` ready, `-1` invalid input/protocol, `-2` seed cell is blocked, `-3` unsealed boundary, `-4` stale terrain revision/cancellation epoch. A filled seed cell after editing can cause a rebake to fail; changing the basin definition/seed is then required.

Builders belong to one thread at a time. Never query or mutate a builder while a worker owns a slice. The scene adapter submits one slice at a time and only publishes a ready immutable volume after the matching completion. Read-only published queries can be shared if the owner retains the volume.

## Terrain adapter and demo

`LakeWorld.terrain` accepts the TerraForest public terrain facade. `add_lake(origin, cells, spacing, level, seed)` returns a session handle; `remove_lake(handle)` releases it. Coordinates are world coordinates and LakeWorld must retain an identity transform.

Terrain retains ownership of its native object. The worker samples in C++, with at most 512 nodes per scene-adapter request and a roughly 2 ms sampling deadline checked every 32 nodes. Flood-fill finalization is a separate bounded operation, not subject to that sampling deadline. Editing takes admission priority. Revision and cancellation checks discard stale results. Accepted edits immediately hide overlapping water volumes and surfaces; publication triggers a new bake. World epoch changes invalidate all lakes.

In the demo, aim at ground and press **L** to carve a radius-12 m basin and bake a lake. This changes terrain. Lake definitions and their persistent ID cursor are now stored with terrain in the compound world snapshot; occupancy and surface meshes rebake on load. Use `python tools/run.py --temporary` for disposable experiments. `prepare`, `snapshot_validator`, `empty_snapshot`, `capture_snapshot` and `restore_snapshot` connect the optional runtime persistence adapter; the water addon still works independently with caller-managed density and storage.

## Rendering and remaining work

The shader uses opaque water, animated lighting normals and a grazing-angle color adjustment. This avoids screen-reading refraction and transparency sorting, but is not a physically complete water renderer. Shorelines are voxel-stepped. The integrated player has basic depth-based swimming/passive buoyancy, and `water_camera.gd` supplies camera-local underwater environment feedback. These are not general rigid-body buoyancy or finished underwater presentation. No water collision body, flow/pressure solver, draining or cross-region fluid exchange is included.

Generator 4 supplies four deterministic lake basins in the integrated world; `Play Lake World.cmd` selects that profile. Generated-lake readiness and combined rendering remain unqualified. There is no baked-water disk cache or replication yet. Fixed fill elevation can create/remove water volume on rebake; this is a static basin model, not a mass-conserving fluid solver. Those limitations must remain explicit in any published feature list. Compound persistence and its limits are documented in `docs/WORLD_STORAGE.md`.

## Build and verify

From the project root:

```text
python tools/build_native.py --addon volumetric_water --target all
python tools/validate.py --test water
python tools/test_native_release.py --addon volumetric_water
python tools/validate.py --test water_integration --gpu
python tools/test_isolation.py
```

See [initial water validation](../../docs/WATER_VALIDATION.md) and [native rectangle-mesh validation](../../docs/WATER_MESH_VALIDATION.md) for recorded evidence. Code license: 0BSD. Linked godot-cpp license: MIT, included beside this file.


NativeLakeVolume now exposes capture_bake(identity) and restore_bake(bytes, identity). Version 1 retains occupancy plus shoreline vertices/indices, reconstructing normals, UVs and the column exclusion index. Identity must be a caller-derived 32-byte digest covering terrain content, lake definition and implementation version; a runtime revision alone is insufficient. Decode is bounded to 6 MiB, validates dimensions/finite coordinates/indices/occupancy and checks a corruption checksum before publishing. Restore requires a fresh instance and rejection leaves it reusable. This is a derived-data codec, not a connected disk cache or a network trust boundary. Worker identity derivation, cache storage/quota and main-world reuse remain to be implemented. Test: tests/water_bake.gd; clean release: python tools/test_native_release.py --addon volumetric_water --test water_bake.

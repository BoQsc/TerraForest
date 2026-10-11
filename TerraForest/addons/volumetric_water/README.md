# Volumetric water ā€” static lake implementation

Independent C++ GDExtension built with the pinned Zig/prebuilt godot-cpp toolchain. Windows x86-64, Godot 4.7, single precision. Copy this addon alone to use `NativeLakeVolume` with your own sampled density fields. `lake_world.gd` optionally integrates with TerraForest's terrain worker protocol.

This implementation stores a **three-dimensional connected water volume**, not an infinite plane. Water occupancy and depth queries use the volume; its surface mesh is a rendering derivative. No simulation runs over resident water cells each frame.

## Representation

- Finite voxel grid; maximum 262,144 cells per lake, dimensions up to 128Ć—64Ć—128 within that total.
- Density nodes use X-fastest indexing: `x + (width+1) * (y + (height+1) * z)`. Positive density is air.
- Each cell uses six consistently connected tetrahedra with linearly interpolated density. Flooding includes connected positive-density subregions below fill elevation. Features thinner than the sample spacing remain unresolved; seed admission still requires eight air corners.
- Face connectivity from an explicit submerged seed selects a single component. Disconnected chambers stay dry. Connected cave cells can be occupied below the fill elevation.
- Reaching any lateral or bottom boundary rejects the entire bake. Water is never silently truncated at an unsealed region edge. The top is above the fill level by configuration.
- Successful volumes retain two bytes per cell plus four bytes per density node, excluding surface channels and a one-byte-per-column legacy index. The 64-cubed fixture retains 1,622,788 volume bytes. Flood queues are freed; density is retained for local boundary queries. Published volumes are immutable.
- Query cost is constant per volume. The scene adapter checks at most 16 bounded lake records (default 8). Idle lakes have no per-voxel update loop.
- Smooth surface extraction cuts the same connected tetrahedra at fill elevation, clips solid regions and greedily merges fully wet rectangles. Boundary triangles preserve sub-cell shores. The legacy surface_arrays method still emits conservative whole-cell rectangles. One MeshInstance per lake allows whole-lake frustum culling.

## Native API

| Method | Contract |
| --- | --- |
| `configure(origin, cells, spacing, fill_level, seed)` | One-shot bounded builder; spacing 1ā€“8 m; fill strictly inside vertical extent; seed below fill and inside bounds |
| `bake_density(PackedFloat32Array)` | Complete finite density field; atomic rejection of malformed inputs |
| `sample_terrain(core, budget, revision, epoch)` | Worker-only adapter to the inherited terrain ABI; integer-aligned grid and spacing; up to 2048 nodes per slice |
| `contains(point)` | True only in connected positive-density space below fill level |
| `depth_at(point)` | Fill elevation minus point Y when occupied; zero outside |
| `smooth_surface_arrays()` | Connected fill-plane boundary mesh used by the renderer |
| `surface_arrays()` | Legacy conservative whole-cell rectangle mesh |
| `statistics()` / `bounds()` | Budget, bake state and AABB information |

Status codes: `0` needs another slice, `1` ready, `-1` invalid input/protocol, `-2` seed cell is blocked, `-3` unsealed boundary, `-4` stale terrain revision/cancellation epoch. A filled seed cell after editing can cause a rebake to fail; changing the basin definition/seed is then required.

Builders belong to one thread at a time. Never query or mutate a builder while a worker owns a slice. The scene adapter submits one slice at a time and only publishes a ready immutable volume after the matching completion. Read-only published queries can be shared if the owner retains the volume.

## Terrain adapter and demo

`LakeWorld.terrain` accepts the TerraForest public terrain facade. `add_lake(origin, cells, spacing, level, seed)` returns a session handle; `remove_lake(handle)` releases it. Coordinates are world coordinates and LakeWorld must retain an identity transform.

Terrain retains ownership of its native object. The worker samples in C++, with at most 2048 nodes per scene-adapter request and a roughly 2 ms sampling deadline checked every 32 nodes. Flood-fill finalization is a separate bounded operation, not subject to that sampling deadline. Editing takes admission priority. Revision and cancellation checks discard stale results. Accepted edits immediately hide overlapping water volumes and surfaces; publication triggers a new bake. World epoch changes invalidate all lakes.

In the demo, aim at ground and press **L** to carve a radius-12 m basin and bake a lake. This changes terrain. Lake definitions and their persistent ID cursor are now stored with terrain in the compound world snapshot; occupancy and surface meshes rebake on load. Use `python tools/run.py --temporary` for disposable experiments. `prepare`, `snapshot_validator`, `empty_snapshot`, `capture_snapshot` and `restore_snapshot` connect the optional runtime persistence adapter; the water addon still works independently with caller-managed density and storage.

## Rendering and remaining work

The shader uses opaque water, animated lighting normals and a grazing-angle color adjustment. This avoids screen-reading refraction and transparency sorting, but is not a physically complete water renderer. Shorelines interpolate the sampled density lattice. The integrated player has basic depth-based swimming/passive buoyancy, and `water_camera.gd` supplies camera-local underwater environment feedback. These are not general rigid-body buoyancy or finished underwater presentation. No water collision body, flow/pressure solver, draining or cross-region fluid exchange is included.

Generator 4 supplies four deterministic lake basins in the integrated world; `Play Lake World.cmd` selects that profile. Generated-lake readiness and combined rendering remain unqualified. Windows worker-side baked-water reuse is available; replication remains unimplemented. Fixed fill elevation can create/remove water volume on rebake; this is a static basin model, not a mass-conserving fluid solver. Those limitations must remain explicit in any published feature list. Compound persistence and its limits are documented in `docs/WORLD_STORAGE.md`.

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


NativeLakeVolume now exposes capture_bake(identity) and restore_bake(bytes, identity). Version 2 retains full-cell occupancy, tetrahedron connectivity, density nodes and shoreline vertices/indices, reconstructing normals, UVs and the legacy column index. Version 1 is rejected and rebuilt; canonical lake IDs/definitions are unchanged. Identity must be a caller-derived 32-byte digest covering terrain content, lake definition and implementation version; a runtime revision alone is insufficient. Decode is bounded to 8 MiB, validates dimensions/finite coordinates/indices/occupancy and checks a corruption checksum before publishing. Restore requires a fresh or identically configured unsampled instance and rejection leaves it reusable. The terrain worker derives identity from native local terrain content keys, the full lake definition and terrain/water binary fingerprints. Lake files share the 512 MiB derived cache quota and atomic publication policy. Up to 16 completed bakes / 16 MiB may wait for accounting; cache failure falls back to baking. This is rebuildable local data, not a network trust boundary. Cold, fresh-process warm and corrupt-entry fallback checks cover four generated lakes. Windows binaries are fingerprinted; other platforms currently fall back to baking. Cache I/O and identity queries are worker-owned but not individually time-sliced; maximum-size latency and eviction policy remain open. Test: tests/water_bake.gd; clean release: python tools/test_native_release.py --addon volumetric_water --test water_bake.


## Optional development UI

`lake_editor.gd` is a bounded, event-driven integration with TerraForest's session
menu; it is not required by NativeLakeVolume. Escape > Water (development mode)
shows lifecycle state, failed-bake reasons, retry and water-only removal. The World
tool HUD links to the same page. `LakeWorld.catalog_changed`, `descriptions()` and
`retry_lake(id)` expose metadata and controlled retry without reading worker-owned
builders. Retries retain persistent IDs/definitions and cannot duplicate pending or
ready work. Existing compound snapshots retain edits; terrain carving is unaffected
by removing a definition. No new native or per-frame simulation path is introduced.


Cold loading service is available before each background worker job in every terrain
meshing mode, as well as between regional mesh pieces. It cannot cross a queued
mutation/save barrier. The four-lake generator4/seed1703 case improved from 2/4 ready
at30s to all four at5.889s with fresh caches; see
`docs/evidence/lake_startup_scheduling/README.md`. This does not qualify all generated
worlds, maximum lake sizes or overall frame/thermal behavior.


Actual generated lake/cave coverage: a disconnected excavated pocket remains dry;
a submerged connecting tunnel fills it after rebake. Player/camera queries and the
vegetation mask agree, and normal reload plus fresh-process reopening retain6m
water depth. Reproduce with `tools/run_lake_cave_check.py` and `--reopen`; evidence
in `docs/evidence/lake_cave_world`. This is one static connected basin, not flow or
unbounded regional water. The boundary correction and its measured memory/bake costs are documented in
`docs/WATER_BOUNDARY_QUERIES.md`. Lattice precision and static-fill limits remain.

## Finite water work in progress

`NativeWaterQuantity` provides exact integer-millilitre transfers, stable identities
and bounded versioned snapshots. It is registered in the same native addon but is
not yet connected to lake levels, spatial flow, world saves or player buckets.
The current playable lakes still have fixed fill elevations. The expanded required
behavior and remaining gates are in `docs/FINITE_WATER.md`.

# Typed terrain binding and independent native worlds

Windows terrain now builds with pinned Zig and prebuilt godot-cpp. The existing
native generator, mesher and packet/save formats are retained. The typed bridge
replaces manual Variant/ABI plumbing. It owns a cancellation counter outside its
World state so reset/load cannot replace that counter. Native mutations and queries
serialize on each instance's mutex; cancellation and its query bypass that mutex.
Allocation-error flags are thread-local. No godot-cpp sources were rebuilt.

## Evidence

- 25 native checks pass in each clean debug/release test project.
- Seven legacy checks establish six field/snapshot/mesh SHA-256 fingerprints.
  Both new variants match those fingerprints exactly. The baseline DLL is read
  from published commit e1181687e14e2dac03598af2e35044d47917e721.
- Two simultaneous cold native mesh jobs are observed inside their native calls.
  Cancelling one aborts that job while its neighbor completes. The neighbor's
  complete render/collision packet matches a fresh sequential world byte for byte.
- 200 concurrent same-world block edits preserve all blocks and revisions; their
  render/collision output matches a sequential build.
- 1,000 native resets lose none of 1,000 concurrent cancellation increments.
- 31 terrain/forest integration checks, 45 water checks and all three addon
  isolation checks pass with the rebuilt terrain DLL.
- 43 compound-save checks pass in both debug and clean release configurations.
  The release test now loads release terrain, runtime and water libraries.
- 13 real-scene checks pass at 1920 x 1080 fullscreen, 100% render scale. The
  [inspected screenshot](evidence/terrain_native/water_lake.png) retains the forest,
  excavated lake and expected voxel shoreline. No frame-rate speedup is claimed.
- The exported PCK starts with six external native libraries (debug/release
  variants of terrain, runtime and water).

## Scope and remaining limits

This proves native isolation for these operations and fixtures, not multiplayer
readiness. The public TerrainWorld facade still enforces one active scene world
per process until cache paths and save-slot ownership support multiple scenes.
The historical Linux DLL has not been rebuilt or migrated. The raw standalone
core retains a global cancellation fallback for legacy tools without an owner.
Each caller must keep its native object alive until its operation finishes.

The fixed world dimensions, inherited native containers and their allocation-failure
limitations remain; this work is not an allocator fault-injection certification.
Networking, region ownership, primitive prefab editing, revised generation,
native scheduling and long-run capacity tests remain outstanding.

## Reproduce

From the project directory, after stopping processes that use its DLLs:

```text
python tools/build_native.py --addon volumetric_terrain --target all
python tools/validate.py --test terrain_native
python tools/test_terrain_bridge.py
python tools/validate.py --test integration
python tools/validate.py --test world_persistence
python tools/test_native_release.py --test world_persistence
python tools/validate.py --test water
python tools/test_isolation.py
python tools/validate.py --test water_integration --gpu
python tools/export_pack.py
python tools/record_terrain_native_validation.py
```

The legacy comparison requires Git history or `--legacy-dll PATH` to a retained
baseline DLL. Other tests work directly from the source archive. Raw results,
build metadata and tested file hashes are in `docs/evidence/terrain_native`.

# Native water surface rectangle merging

The water mesher merges adjacent occupied surface cells across both X and Z.
It preserves the voxel shoreline, central islands and uncovered cave roofs.
The native operation uses a fixed 16 KiB local mask and does not modify the
published water occupancy. It runs when a surface is extracted, not every frame.

## Verified geometry reduction

| Sealed rectangular basin | Previous row strips | Current rectangles | Triangle count |
| --- | --- | --- | --- |
| 8 x 6 x 8 cells | 6 | 1 | 12 to 2 |
| 64 x 64 x 64 cells (maximum cell budget) | 62 | 1 | 124 to 2 |

Previous counts follow the prior one-strip-per-occupied-row algorithm.
Current counts are asserted by native API tests. This is a geometry reduction,
not a matched frame-rate benchmark; irregular lakes need multiple rectangles.
Greedy merging does not promise the globally smallest rectangle partition.

## Validation

- Native debug: 45 checks passed.
- Native release in a clean Godot project: 45 checks passed.
- Real terrain/vegetation scene: 13 checks passed at 1920 x 1080 fullscreen, 100% render scale.
- Zig compiled the changed extension source against the pinned prebuilt godot-cpp library for both variants.

The coverage oracle checks every grid-cell center against volume occupancy,
requires exactly one covering rectangle for each wet surface cell and none for
dry cells, and compares total area. It also checks index winding, normals,
world-space UVs and deterministic repeated extraction. Cases include a rectangle,
disconnected chamber, irregular cave roof, central island, negative coordinates,
scaled lattice with an integer fill elevation, and the maximum-cell basin.
The scene test covers edit invalidation, rebaking and removal during sampling.

The inspected [1920 x 1080 screenshot](evidence/water_mesh/water_lake.png)
shows the bounded excavated lake. The voxel-stepped shoreline remains visible.
These tests do not establish flow, smooth shorelines, multiplayer or long-run
performance. The broader outstanding scope remains in [delivery status](DELIVERY_STATUS.md).

## Reproduce

From the TerraForest project directory:

```text
python tools/build_native.py --addon volumetric_water --target all
python tools/validate.py --test water
python tools/test_native_release.py --addon volumetric_water
python tools/validate.py --test water_integration --gpu
python tools/record_water_mesh_validation.py
```

Reports and tested source/DLL hashes are preserved in `docs/evidence/water_mesh`.

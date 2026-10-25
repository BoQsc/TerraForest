# A0 original vs A2 thin-roof proposal — 2026-10-25

**A2 is awaiting explicit user approval.** It is not in the production prefab
catalogue or generator. Existing houses and player saves are untouched. B1 remains
the only approved addition; rejected A1 is neither reused nor promoted.

Open `python tools/review_modular_buildings.py --roof`. Original A0 is on the left,
proposal A2 on the right, with the same cameras and labeled signs. Exterior,
Interior and Detail inspect the roof and underside. `Remove ONE roof block`
removes exactly one candidate cell; `Restore that block` restores it. No player
save is loaded or written. The review directory remains excluded from exports.

## Geometry

The original full wedges exposed metre-scale staircase undersides at the gable
overhang. A2 replaces that shell with native thin slope/ridge sections and separate
seam pieces clipped to their own integer grid cells. The 45-degree skin is 1/8 m
thick vertically, about 8.8 cm normal to the slope. Top and underside both join
continuously. Nothing is stretched across neighboring cells or covered by a
house-sized cosmetic mesh.

New stable shape IDs:

- **15 Thin roof slope:** diagonal slab clipped to the unit cell.
- **16 Roof seam infill:** the small triangular part in the cell below a slope.
- **17 Thin roof ridge:** two joined slopes in one central ridge cell.
- **18 Ridge seam infill:** the two small edge portions in the cell below a ridge.

All support 24 proper grid rotations, existing material payment and normal timed
tool damage. Each shape is one independent block; destroying a slope does not
automatically remove separately owned infill or its neighbors. Rendering batches
and shared immutable geometry do not merge their ownership. Existing shape IDs
and geometry are unchanged, including B1's older ridge/corners.

The A2 prefab contains 555 blocks. Walls below the eaves, stairs, footprint, rooms,
doors, windows, furniture and storage retain the original data. The upper gables
are rebuilt as continuous timber backing rather than alternating brick steps and
exposed wood wedges. Gable closure uses separate ordinary blocks, not a complete
triangle mesh. Tiny infill cells complete the outer eave corners without replacing
solid wall blocks. This is a roof assembly change, not A1's porch redesign.

Native C++ templates supply worker meshes, collision and authoritative picking /
water-solid hulls. GDScript authors the review resource offline and scaffolds the
review UI; no runtime script builds roof meshes or simulates individual cells.

## Verification

| Check | Result | Evidence |
| --- | --- | --- |
| Native debug and release builds | Passed | `build/` |
| Modular component suite, debug | 1,978 checks passed | `component_debug/` |
| Modular component suite, release DLL | 1,978 checks passed | `component_release/` |
| Continuous roof assembly, debug and release | 19 checks each passed | `seams_debug/`, `seams_release/` |
| Graphical A0/A2 comparison and native player traversal | 21 checks passed | `comparison/` |
| Separate-process exact compound restoration | 3 checks passed | `comparison_restore/` |
| Actual source-game placement/destruction | 153 checks passed | `gameplay_source/` |
| Actual exported-game placement/destruction | 153 checks passed | `gameplay_pack/` |
| Separate-process exported block restore | Passed, exact bytes | `pack_restore/` |
| Broad structures regression | 294 checks passed | `structures/` |
| Seven legacy mesh fixtures | Original mesh hashes retained | `legacy_mesh/` |
| Legacy solid samples and R1 comparison | Passed, R1 41 checks | `legacy_solids/`, `legacy_review/` |
| Pack export/startup | Passed; both new DLLs copied | `pack/` |

The modular suite checks all 240 extended shape/orientation combinations, cached
grid-bounded previews, outward triangle winding, every triangle's solid/empty
sides, physical-vs-authored rays, material/word roundtrips, invalid-word atomicity,
binary regions, history, and earlier arch/panel behavior. The 36-cell roof fixture
checks continuous top and underside across slope/ridge and signed chunk seams,
exact exterior surface area (no hidden phase caps), actual holes after one-cell
removal, undo/redo and exact storage.

The gameplay suites select all ten modular shapes through actual ALT controls,
place with RMB and charge one material each, then use animated axe contacts to
damage and destroy each cell independently while neighboring support survives.
They restore the complete structures store; the separate PCK process verifies
exact saved block words. Gameplay worlds are temporary and explicitly skip saves.
The candidate house itself is not installed in those worlds.

Inspected `images/exterior.png`, `edge_detail.png`, `interior.png` and
`one_block_removed.png`: the new edge and ridge form uninterrupted thin slopes,
the underside no longer has the old staircase, and removal opens the selected
overhang cell while the original stays intact. These are actual Godot renders,
not mocked-up or generated illustrations. This engineering/image inspection does
not substitute for the user's design approval.

`failed_fixture_parse/` preserves the initial seam-test parse failure: GDScript
could not infer cells derived from an untyped array loop. Explicitly typing the
loop origin fixes that test; it did not require changing the native geometry.
The failed run is not counted as a pass. Final runs and hashes are retained in
`manifest.json`. No performance claim is based on a 60-FPS cap or explicit bake
flush timings; sustained populated-world budgets remain outside this review.

## Still pending

- User approval before A2 replaces an original or enters generation.
- Terrain-fit, populated-world traversal and performance evidence for adoption.
- Arbitrary/shallow roof pitches and structural-collapse behavior are not supplied.

## Reproduce

```text
python tools/build_native.py --addon structures --target all
python tools/run_godot_check.py modular_blocks --headless --timeout 120 --require "MODULAR_BLOCKS checks="
python tools/run_godot_check.py thin_roof --headless --timeout 90 --require "THIN_ROOF checks="
python tools/run_godot_check.py cottage_roof_review --timeout 120 --require "COTTAGE_ROOF_REVIEW checks=" -- --review-output=res://reports/cottage_roof_review/recheck
python tools/run_godot_check.py cottage_roof_review --headless --timeout 60 --require "COTTAGE_ROOF_RESTORE checks=" -- --restore-review --review-output=res://reports/cottage_roof_review/recheck
python tools/run_godot_check.py modular_blocks_world --timeout 180 --require "MODULAR_BLOCKS_WORLD checks=" -- --modular-output=res://reports/thin_roof_game
python tools/review_modular_buildings.py --roof
```

`--bake-roof` on the comparison test explicitly regenerates its review-only prefab.
Ordinary viewing and tests without that flag only load the baked resource.

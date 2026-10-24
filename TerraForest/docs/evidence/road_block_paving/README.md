# Road blocks and smooth terrain ramps

2026-10-24. User direction: built construction consists of destructible parts;
retain smooth terrain ramps rather than forcing sloping roads into stairs.
Changes apply to newly generated worlds. Existing saves, including old decorative
sidewalk instances, are preserved, not silently migrated. The user requested this
flat-plate baseline committed on 2026-10-25; the rejected shallow-ramp experiment
is excluded.

## Implementation

### Flat-only restoration, 2026-10-25

The rejected ramp experiment is absent from the native shape decoder, geometry,
planner API and player prefab list. Its code, images and separate seed-1703 trial
save are archived locally outside the playable build and this commit. The original
seed-1703 save's 261 recorded files retain their hashes. Existing worlds are not
migrated. Smooth volumetric terrain slopes remain; no experimental ramp parts do.

Fresh results are in `flat_baseline_20261025/`: 83 plate checks pass in debug,
release and exported builds; all nine seed/profile plan digests exactly match
the pre-experiment baseline. Support/air checks, seven-seed raw-lot planning,
legacy lattice, region/worker lifetime, solid queries, inventory and vegetation
regressions pass. Export/startup passes and all four source/pack DLL hashes match.
These tests restore the previous flat-plate behavior, not expand acceptance.

Retained incomplete attempts: `headless_ui_incomplete/` records a rendered test
mistakenly run headless, stopped while awaiting `frame_post_draw`. It is not a
passed UI rerun; prior rendered evidence is retained. That process temporarily
locked the DLL during relinking; after stopping only that owned test, rebuilding
succeeded. Initial rollback reconstructed identical cells in a different order;
restoring the original X/Z/Y ordering made all nine plan digests match exactly.
An initial PowerShell GUI launch did not wait or produce pack reports; the final
bounded Python subprocess runs use absolute paths and verify successful exits.
Local attempt logs remain under `reports/flat_plate_baseline_20261025/` and
`reports/rejected_ramp_20261025/`. No rejected ramp implementation is staged.

- Native street planner chooses feasible integer node heights under unchanged
  earthworks bounds, then connects grades with the existing cubic terrain curves.
  Longer subdivisions allow integral rises without locking every market street
  to one height. Shared midpoint/junction nodes remain connected.
- Native paving planning emits packed integer cells on flat street-side strips,
  with crossing clearances. Support beds are part of master earthworks before any
  construction publication. Sloped side sections remain editable terrain.
- Shape 8 is an upper-quarter plate: one metre square, y=0.75..1 in its integer
  cell. Concrete word 192 uses bit 7 plus the existing rotation/material bits.
  Old words and binary container layouts are unchanged; older executables cannot
  read new plate words. Existing cell capacity and streaming budgets are unchanged.
- Native solid queries, picking, mesh/collision baking, inventory cost extraction,
  prefab counts and save validation understand the shape. Standard attack and
  construction handlers need no plate-specific bypass. Normal undo/redo works.
- Greedy chunk meshes remain a rendering optimization, with shader seams showing
  individual plates. There is no per-plate Node or rigid body. Plate chunks use
  the existing quarter-cell scratch bake lattice; that costs more worker work
  than cube-only chunks. No unsupported whole-frame speedup claim is made.
- Generation cache version 3 separates the new plan. Plate publication batches
  at most 1,024 cells per yield, refuses occupied cells and has counted progress.

## Verification

| Evidence | Scope and result |
| --- | --- |
| `paving_debug.log`, `paving_blocks_release.log`, `pack_paving.log` | 83 checks each: four materials/four rotations, exact solid bounds, native ray surfaces, costs, neighbor preservation, undo/redo, binary world/region restoration, planner determinism, non-overwrite and invalid input |
| `inventory.log` | 24 checks, including concrete plate debit and free removal |
| `matrix_source.log`, `pack_matrix.log` | Seeds 0/42/1703 × profiles 19/20/21: northern + market + connection plans succeed; cached digests and paving cells match |
| `raw_lot_planner.log`, `earthworks.log` | Seven-seed terrain-fitting search; native prepared support, asphalt/plate surfaces and terrain snapshot roundtrip |
| `legacy_lattice.log`, `block_regions.log`, `block_worker.log`, `solid_queries.log` | Legacy mesh bytes unchanged, region/history/lifetime and solid-query regressions |
| `vegetation_invalidation.log`, `loading_ui.log` | Bounded edit invalidation and counted generation-stage presentation |
| `create.log`, `reopen.log` | Production seed 42/profile 21: 20 buildings, 327 earthwork commands, actual pickaxe/brick interaction, real ramp walking and fresh-process complete-signature equality |
| `export.log`, `pack_smoke.log`, `road_blocks_native_hashes.json` | Updated PCK starts; all four changed debug/release native DLLs match their packaged copies |

The northern site has 748 independently keyed paving tiles and 18 non-flat
segments left as terrain ramps. Four normal pickaxe contacts remove the selected
concrete tile, leave its neighbor, and charge four wear. A normal brick placement
consumes one item and has exact shared-face alignment above the neighboring plate.
The player walks about 10.6 m along a descending shoulder from about 48.96 m to
48.06 m, without flight or jump. This is one local walking check, not vehicle or
whole-world navigation qualification. `world_signature.json` is captured before
save and compared unchanged in a new process, including all block-region hashes,
static model collections, generated-region metadata and water state.

Source/package integration ran on Godot 4.7.2, Vulkan Forward+, RTX 4050 Laptop GPU,
at 1920×1080 for rendered checks. Screenshots/readback are not performance samples.
Native build manifests identify the compiled libraries and source baseline.

## Inspected images

`road_plate_before.png`, `road_plate_removed.png`, `road_plate_building.png`,
`road_plate_overview.png` and `road_smooth_ramp.png` were inspected. The removed
one-metre tile exposes underlying editable soil without deleting the adjacent
strip; the brick meets its plate and the overview shows square seams and crossing
gaps. The close brick image retains the normal next-placement preview, not a
missing solid. The ramp view preserves a smooth, unplated transition. Separate
north/market loading photographs were also inspected in the retained local run.

These images establish only the local plate change. Repeated architecture,
unfinished landscaping/entrances and raw road ends remain visible/unqualified.
No broad aesthetic, multi-seed traversal, vehicle approach, thermal/endurance or
lower-end performance acceptance is inferred. Player playtesting remains necessary.

## Retained failed attempts and corrections

- Initial 0.3 m support-bed depth violated the existing native minimum of 1 m;
  corrected to supported dimensions, without relaxing admission. Half-width 0.75 m
  provides interior density samples on the integer terrain lattice.
- The old decorative-slab underside probe was inside the new 0.25 m plate.
  Support is now sampled 0.24 m below the top (1 cm inside its underside), and air
  only 0.02 m above. The final native earthworks test has zero mismatches.
- Too-short snapped street segments forced integer rise zero and rejected market
  layouts. Corrected subdivision, not cut/fill limits. The former seed-42 comparison
  against a particular continuous-grade site was replaced with grid-grade/plate
  assertions; general raw-earthworks/reservation/slope gates remain.
- Initial interaction harnesses left the hidden generation screen processing;
  it forced a visible mouse and correctly cancelled combat. The test disables that
  screen's processing during play, then restores it. Another test expected cube
  word 1 despite retained 180-degree rotation (word 17); it now checks that rotation.
- Initial reopen commands incorrectly used production-generation initialization,
  then omitted qualification expectation sidecars. Final tests use read-only
  verification and expectations captured from the original generation, not from
  the reopened state. No existing player save was targeted.
- First pack-only checks attempted writing to read-only `res://reports`; all
  plate assertions had passed before reporting failed. Explicit writable report
  paths correct the harness. Only owned failed test children were stopped.
- Early legacy-lattice/region runs requested a nonexistent `failures=0` text
  marker; they exited zero with no failed assertions. Reruns with their real
  completion markers pass.
- **Open pre-existing broad-suite failure:** `legacy_structures_failure.log`
  reports 18 failures from obsolete invalid-word-7 fixtures. The identical suite
  with the original `ab32f4e3` DLL reproduces all 18 in `baseline_structures.log`.
  Those fixtures were not changed. The two tests that used word 128 as an invalid
  sentinel were updated to still-invalid 129 because 128 intentionally now means
  the brick plate; their atomicity/invalidation assertions remain intact.

Failed local runs remain under `reports/road_blocks_review2` through `review5` and
the recorded check timestamps; representative failure logs are retained here.
The final integrated run is `reports/road_blocks_review6`, with a fresh disposable
slot recorded in `create.json`; it is test evidence, not an automatic player-world
replacement. Only this task's five recorded check slots were moved out of the
world selector into each run's `owned_test_save` directory, retaining every
`.trw`/backup/archive artifact rather than deleting failed evidence. Reopen
commands assume those same basenames are restored to the original worlds folder.
No other slot was moved. Remaining review requirements and triggers are in
`../../WORLD_FOUNDATION_STATUS.md`.

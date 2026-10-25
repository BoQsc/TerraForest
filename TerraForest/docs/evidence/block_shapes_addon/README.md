# Building-shape addon assessment — 2026-10-25

## Decision

Reuse selected mathematical shape recipes, not the standalone world backend.
This is a completed initial assessment and a corrected portable source archive,
**not a deployed native shape expansion, approved building kit or house redesign**.
Existing houses, generation defaults, trusted road plates and player saves are
unchanged. No plugin or additional world implementation is installed in the game.

The supplied `block_shapes_r3_cc0_0bsd.zip` contains 224 stored meshes across
18 families, 24 proper cube rotations and complete numeric build inputs. Declared
licences are 0BSD for software and CC0 for geometry/project content; the policy
audit passes but is not independent legal clearance. The original archive is
retained in `source/`; its SHA-256 is
`f55e25b8945438a64d3450bc7fefe317a3f0f4e0d2f5a1b508551237019f47cb`.

## Mandatory modular construction

Every architectural component is an individually addressable building-grid block.
Arches, frames and roofs are assemblies of 2, 4, 6, 8 or more blocks, not a
whole feature stretched across an opening. The source catalogue's complete arch,
door-frame and window-frame entries are **not accepted construction blocks**.
Quarter curves, straight segments and corner trims can instead form assemblies.
Chunk mesh/collision batching is permitted; per-cell identity, removal, damage
and persistence must remain authoritative. See `../../WORLD_BUILDING_STANDARD.md`.

`final/rendered/modular_blocks.png` shows actual Godot rendering of four assemblies:

| Assembly | Individually stored cells | Ingredients |
| --- | ---: | --- |
| Arch crown | 2 | Quarter curves |
| Archway | 4 | Two quarter curves and two straight jambs |
| Rectangular doorway | 6 | Four straight jambs and two corner trims |
| Window surround | 8 | Four corner trims and four straight segments |

Every piece occupies an integer one-metre cell with a grid-preserving rotation.
`assemblies_before.json` stores 20 cells. Removing only `(4,1,0)` gives 19 records,
each byte-equivalent in parsed value to its original record; the neighboring arch
segment and jambs remain. A physics ray hits the segment before removal and misses
afterwards. Restoring the first file restores the missing cell. See
`modular_block_removed.png` and `console.log` in the same directory.

These deliberately contrasting colors expose block boundaries. The pictures are
component proofs, not proposed house artwork. Visible faceting and dark/shadow
artifacts on the curved and lower frame surfaces remain unqualified; do not treat
this rendering as the desired final visual quality. Native damage, player item
placement and binary world saves are not exercised by this standalone proof.
Each redesigned house and revision still requires explicit user approval.

## Geometry findings

- Catalogue bounds are `[0,1]^3`, Y-up. Godot's adapter reverses the source CCW
  triangles to CW while retaining outward normals. There are 7,656 triangles
  in total, with 6–128 per shape.
- `catalogue_analysis.json` finds three exact-triangle duplicate groups, leaving
  221 classes under the 24 rotations. This is not general geometric uniqueness:
  different triangulations can conceal further equivalent solids.
- Roof corners, ridges, ramp segments, thin panels, beams, trims and quarter
  curves are useful source material. Do not dump all 224 variants into player UI.
- Thin shallow panels do not automatically tile on the integer lattice. For
  `panel.r0.5.t0.125.w1`, one edge is at Y=0/.125 and the opposite at Y=.5/.625.
  Repeating it requires a half-metre offset, which is not a valid next cell.
  Grid-clipped phase/transition blocks or a suitable multi-cell recipe are needed;
  fractional cell placement or stretching is not an acceptable workaround.
- Solid segmented ramps already provide progression but fill the wedge; they
  are not a solution for a hollow shallow roof. This assessment changes no roads.
- The source's one-cell doorway obstructs a 1.8 m player capsule. Physical rays
  correctly pass through frame openings and hit jambs, but that does not make a
  complete frame an acceptable TerraForest building block.

## Runtime and measured cost

The standalone world uses synchronous GDScript meshing/collision reconstruction,
sparse dictionaries and JSON saves. It lacks TerraForest's native region storage,
damage integration, worker budgets and greedy merging. Boundary culling only
handles fully covered faces: two adjacent half slabs produce 24 triangles instead
of the 20 needed after removing the shared boundary. Concave triangle collision
does not supply native solid-volume/convex-part queries for navigation and water.

Same-machine Godot 4.7.2, i5-12450H / RTX 4050 Laptop GPU; identical 16³ solid cube,
collision enabled, six alternating boundary-cell removals/restorations:

| Final headless run | Standalone addon | Native reference |
| --- | ---: | ---: |
| Author 4,096 cells | 19.444 ms | 5.293 ms |
| First explicit flush | 35.696 ms | 140.209 ms |
| Subsequent edit + explicit flush | 28.264–32.951 ms | 0.145–0.279 ms |
| Completed cube triangles | 3,072 | 12 |

The native first flush is **slower** in this run; its cause is not isolated here.
Do not hide it or claim every native operation is faster. The repeat-edit result
supports retaining native greedy/worker paths rather than replacing them with the
addon backend. Explicit native flush waits for worker completion. These are small
CPU probes, not frame-time/FPS results, arbitrary-shape benchmarks or a sustained
large-world qualification. Earlier retained headless edits measured 29.446–32.929
ms versus 0.214–0.550 ms. Raw values, engine/test hashes and commands are retained
under `initial/` and `final/`; visual setup is outside the timed portion.

## Windows portability correction and verification

The original full gate stops on generated-document CRLF/LF differences after the
Python tests and byte-identical geometry rebuild. The review archive changes only
explicit LF output in `tools/generate.py` and `tools/preview.py`, review status/docs,
and their provenance/manifests. Catalogue, recipes and runtime remain unchanged.
The corrected archive is `source/block_shapes_r3_windows_review.zip`;
`source/review_changes.diff` records the non-manifest edits. `artifact_hashes.json`
records retained artifact hashes and the serialized-cell comparison.

- Final corrected full gate: **PASS**. 75 Python tests discovered, 74 passed,
  one symlink test skipped because this host lacks permission to create symlinks.
- Full-project/addon inventory and licence policy, byte-identical catalogue and
  generated-document rebuild: **PASS**.
- Actual Godot import, runtime smoke, demo startup, export and isolated-PCK run:
  **PASS**. The smoke reports 557,080 assertions, largely per-vertex/bounds checks;
  these are not 557,080 independent gameplay scenarios.
- Source-component headless and rendered checks plus native reference: **PASS**.
  Rendered assembly pictures were inspected. Original engine checks were also
  run separately after the original full gate failed; that does not retroactively
  make the original all-in-one gate pass.

Retained failures: `logs/original_check.log` is the real Windows portability
failure. `failed_fixture/` records an assessment-fixture typo using nonexistent
`block.h0.5.w1`; corrected to the real `slab.4of8.edge` before final runs. These
failures are not counted as passes or hidden. The main-project import log retains
pre-existing duplicate-UID warnings from the rejected road-ramp report directory.

## Native integration still required

1. Define a small stable block catalogue and bake selected geometry, boundary
   coverage, UV/normal data and collision/solid parts into native resources. Resolve
   curve shading and shallow-roof continuity before declaring a kit visually ready.
2. Preserve every legacy block word and existing save. Current cell arrays already
   use `uint16_t`, but `block_word.hpp` accepts only the legacy low-byte encoding:
   eight shapes, four yaw rotations, four materials. An extended, versioned ID
   scheme must audit raw shifts, prefab rotations, serializers and all consumers;
   do not use upstream catalogue array indices as persistent IDs.
3. Integrate worker meshing and partial-face culling, collision/raycast and solid
   queries, independent damage/removal, inventory/placement/preview, water and
   navigation. Keep geometry preparation off runtime GDScript hot paths. GPU work
   is not a substitute for eliminating redundant rebuilds or preserving ownership.
4. Test legacy and new save roundtrips, all supported rotations, cell/chunk edges,
   individual destruction and collision holes in real gameplay. Resolve the
   previously recorded 18 legacy structure-suite failures without weakening the
   assertions; record baseline versus integration changes.
5. Benchmark mixed-shape neighborhoods, cold first-use and repeated edits, then
   present one proposed house at a time. A house cannot replace the current design
   or become a generator default without the user's explicit approval.

These steps are pending because the initial assessment identified compatibility,
runtime and visual prerequisites, not because the standalone tests failed to run.
Return with native component integration after the block contract above; close
only with real-game engineering evidence and separate per-house human acceptance.

## Reproduction

Extract the corrected archive to an isolated directory outside the live project.
Run `python tools/check.py --godot "<Godot editor executable>"`. To repeat the
external component proof, use that directory as `--path`, the repository's
`tests/block_shapes_addon_review.gd` absolute path as `--script`, then
`-- --shape-review-output=<absolute output directory>`. Omit `--headless` to render
the modular proof. For the native reference, use TerraForest as `--path` and add
`--native-reference` after `--`. Exact executed commands are in `final/*/run.json`.
Use a disposable output directory, not a player save directory.

# Building expansion E2 review — 2026-11-01

Status: engineering verification complete for the proposed scope; ready for review.
Exact E2 artwork and building revisions await user approval.
The direction and five civic R1 designs were already approved on 2026-10-30.
This review concerns the changed buildings and expansion only. Existing approved
resources and saves retain their original cells and appearance.

## What changed and why

| Addition | Demonstrated use | Cost and decision |
| --- | --- | --- |
| 1:2 slopes, seam pieces and ridge (19–23), closed shallow gables (32–34) | School library roof falls from a 45-degree pitch to a 1:2 pitch; its crest is 2.25 m lower and joins the taller school wall | School has 24 fewer cells. Keep for review |
| Shallow hip phases (24–25) | Town-hall entrance canopy has finished sloping corners | Individual native cells, shared material. Keep for review |
| Crown/corner and coping/corner (28–31) | Town-hall frontage and parapets get a continuous profile | Hall adds 166 cells including canopy. Corners remain individually removable. Keep for review |
| Closed pitched gables (35–36) | Roof finish continues across roof ends while exposed end faces remain timber | Same solid volume as their legacy slopes/ridges; all yaw orientations verified. Keep for review |
| Eight grim appearances | Brick, weathered plaster, limestone, timber, slate, zinc, clay and aged trim distinguish building uses | Shared lazy 512-pixel array; separate from structural/crafting material. Keep for review |
| Search, families, orientation and assembly previews | Players can find and orient 36 native shapes without a live render viewport for each button | Baked images; original numeric identities and prefab controls preserved. Keep for review |
| Shallow valleys (26–27) | Assembly fixture only | Retain as optional prototypes; no default-building adoption proposed without a useful populated-world example |
| Beams/braces, chamfers and heavier arches | No first-pack building requires them | Assessed follow-up, not additional catalog entries in this pack |
| Normal/roughness arrays, parallax/displacement | No measured benefit established for this pack | Not enabled. Preserve current silhouette/collision and keep albedo cost bounded |

## Exact building revisions

The [candidate manifest](../reviews/building_expansion/provenance.json) identifies
source and E2 hashes, the recipe and material manifest. None inherits an approval
flag from its R1 source. E1's rejected procedural art, prefabs and provenance are
archived under `reviews/building_expansion/rejected_e1/` and excluded from the game.

| Candidate | Player-visible change | Cells R1 → E2 |
| --- | --- | ---: |
| Trader T1 E2 | Aged brick, timber and clay roof; same counter and one resident merchant | 1019 → 1019 |
| Town hall T1 E2 | Weathered civic finish, slate roof, shallow entrance hip, cornice and coping | 3028 → 3194 |
| Church C1 E2 | Coursed masonry with slate roof and timber gable ends | 3011 → 3011 |
| School S2 E2 | Lower library roof, complete wall junction, weathered plaster and slate | 2615 → 2591 |
| Warehouse W1 E2 | Brick walls and continuous zinc roofing across all roof pieces | 3505 → 3505 |
| Cottage A2 E2 | Aged masonry/timber and clay roofing | 555 → 555 |
| Shop B2 E2 | Brick, slate and timber ends on the existing thin roof | 1028 → 1028 |
| Shop B1 E2 | Brick/slate hipped roof with all four slope directions retained | 963 → 963 |
| House C1 E2 | Weathered civic materials and slate on the existing large house | 1914 → 1914 |

The five civic buildings retain their furniture, windows, doors, stairs and partial
basements (81 m² school, 99 m² hall/church/warehouse). The trader's full finite-stock
buy/sell implementation and player-based NPC are covered by the earlier
[Civic final review](CIVIC_FINAL_REVIEW.md). Expansion appearance does not change
inventory costs, damage or salvage. Approved R1 remains the comparison baseline.

## Material decision

All eight textures were individually authored with imagegen, with separate masters,
exact prompts and generation/edit lineage. The first eight-board timber trial was
rejected and retained; the selected edit uses four broader boards. Godot only
normalizes resolution and builds runtime assets; the rejected procedural generator
is retained solely to reproduce E1 evidence.

All eight 3×3 repeats were inspected. Roof courses follow the slope's local drainage
orientation through every mounting direction. Vertical courses use downward image V.
The repeat is one projected grid metre; slope length stretches it by the documented
pitch ratio. Some repeated weathering remains visible on broad surfaces: material
variety does not remove grid repetition or solve the surrounding forest rendering.

The 512/1024 study uses the same trader roof and hall wall at 2, 8 and 20 m.
At two metres the extra detail is slight; 512 is the proposed runtime choice.
The 20 m cameras are obscured by foliage and are not used to claim distant detail
equivalence. The larger array is loaded only for the study and both arrays coexist during those
captures. The report distinguishes actual additional allocation from logical RGB
byte counts; it does not subtract two totals with both arrays resident.

New original assets carry the project's CC0-1.0 contribution grant, with an offline
credits notice. External image-generation tooling is recorded separately. Existing
project license exceptions and unresolved provenance are not relabeled.

## Verification and remaining limitations

Current exact results and captioned comparisons are maintained in the
[stable issue](../issues/building-expansion/README.md). Source/release shape, material,
contact and persistence checks are mandatory before export. The latest native
focused check passes 490 cases, including exhaustive word decoding, legacy identity,
all new mounts, roof UV direction, structural costs and atomic archive validation.

The completed populated route pass verifies all five civic NPC routes, player
entrance/return routes for all eight civic/market buildings, all civic basement
stairs and both warehouse vehicle bays. Three older market NPC routes did not
finish planning. Shop B1 reproduces this on unchanged R1: this is an existing
navigation limitation, not a demonstrated expansion regression. Do not claim that
all NPC access is qualified. Actual player paths passed for these buildings.

Full-world frame pacing remains an open project issue. Report the matched frame
p95/worst, CPU/GPU render times, geometry, draw calls, memory and publication costs;
do not interpret a smaller native edit time as proof of 60 FPS. Camera-distance
captures and actual-player travel are distinct evidence. Incremental E2 replacement
means neighbors may still be R1 in early screenshots; every target lot is named.

The [captioned gallery](../issues/building-expansion/GALLERY.md) contains all nine
matched revisions, the local damage/undo sequence, a basement, roof undersides,
actual-player travel and 512/1024 close-ups. [Measured costs](../issues/building-expansion/PERFORMANCE.md)
retain all frame, geometry, memory and publication values. Civic/market frame p95
is 18.04–18.68 ms for E2 versus 17.98–18.77 ms for R1 in this capped sample;
background workload was uncontrolled. The appearance array adds 10.69 MiB of
measured texture allocation; a 1024 array would consume 42.69 MiB.

Final source/release gates pass 30 contact checks and 490 expansion checks each,
plus 80 source catalog, eight material and 45 candidate-asset checks. The PCK
passes all 45 asset checks and startup with 14 external libraries. Modular
regressions pass 1978 cases, construction costs 26, and actual UI placement 30.
C1 passes 30 route/basement checks after fixing microscopic clipped-face slivers.
The final geometry rejects these residual triangles at their shared source;
it does not suppress physics errors. All nine candidates receive joined-mesh
validation in the mandatory export gate.

The actual player walks 221.22 m in R1 and E2 with zero collision-readiness holds
and no unsupported fall. Both isolated E2 clones save and reopen with exact cells;
the original saves remain byte-identical. Exact artifact identities and source
reports are recorded in [verification.json](../issues/building-expansion/verification.json).

## Review and adoption

`python tools/review_building_expansion.py` opens the verified E2 civic/market clone;
`--house` opens its separate verified C1 clone. The launcher
refuses a stale native, candidate or save hash. It opens read-only checkpoints;
test edits are discarded when closing. The runtime prefab list exposes
candidates through `--building-expansion-review`; ordinary generation does not
silently adopt changed resources. No automatic repainting of saved worlds is added.

The implementation and art are review candidates. Approval should identify the
pack and exact building revisions; adoption as generation defaults follows that
decision. No renewed approval of the previously accepted R1 designs is needed.

Contracts: [world/building standard](WORLD_BUILDING_STANDARD.md),
[material standard](BUILDING_MATERIAL_STANDARD.md),
[native format](BUILDING_EXPANSION_FORMAT.md). The earlier assessment is retained
[in the authoring archive](../reviews/building_expansion/assessment_2026_10_30.md).

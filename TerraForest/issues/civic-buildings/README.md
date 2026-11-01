# Trader house and civic buildings

- Status: R1 and E2 approved; normal-generation integration installed; scoped source/PCK checks pass.
- Updated: 2026-11-01. Branch `codex/trader-civic-buildings`.
- User review: Approved 2026-10-30: Trader T1 R1, Town Hall T1 R1, Church C1 R1,
  School S2 R1 and Warehouse W1 R1, plus the expansion direction. Finished E2
  changes approved 2026-11-01 and connected to ordinary new-world generation.
- Scope: One player-based trader with full commodity buying/selling, four large
  civic buildings with 81–99 m² partial basements, and shared terrain contact enforcement.

[Final review, decisions and launch command](../../docs/CIVIC_FINAL_REVIEW.md).
[Complete-world engineering evidence](../../docs/evidence/civic_buildings/world/README.md).
[Recurring terrain/block correction](../terrain-building-contact/README.md).

## Current production evidence

Use **Connected countryside**, seed **1703**, with **Generate & play**. The exact
approved E2 buildings, one resident trader, normal construction choices and saved
trading are now connected. Combined packaged checks pass 6 creation, 53 gameplay
and 22 fresh-restore assertions. [Current evidence, screenshots and installation
status](../building-expansion/README.md#production-integration-correction--2026-11-01).
The views below preserve the earlier approved R1 review.

## Complete-world views

All current views: `CivicReview_1703_8ae64a06`, seed 1703, civic plan 29,
Godot 4.7.2 Forward+, 1920×1080. Captured after native publication and fresh-process
restore. Images were inspected by Codex; the user approved all five R1 designs
on 2026-10-30. Historical capture statuses remain preserved in the manifest.
[Hashes, source runs and earlier images](images/manifest.json).

![Trader house in its surveyed lot](images/world_trader_t1_street.png)
Trader T1: covered arrival, public room, counter and stockroom. The connected
approach was walked in both directions. Broad landscape and texture refinement
remain distinct from the verified contact correction.

![Trading inside the actual world](images/world_trader_world_trade.png)
The normal E interaction opens quantity-based buying/selling. Stock and both purses
are finite. This capture follows test transactions in the disposable review save.

![Player-based trader](images/world_trader_world_counter.png)
One idle Human R11 trader. The visible pickaxe belongs to the player camera;
the trader has no equipped tool. Existing character provenance remains unchanged.

![Town hall](images/world_town_hall_t1_street.png)
Town Hall T1: portico, two floors and 99 m² basement; street-to-interior player and
native-NPC routes pass. The concrete appearance is an explicit texture-study target.

![Church](images/world_church_c1_street.png)
Church C1: tower, supported cross, nave and side vestry; 99 m² basement. The
original disconnected cross and overwritten shared wall remain below as rejected history.

![School](images/world_school_s2_street_final.png)
School S2: two-storey classroom block, library wing and 81 m² basement. This closer
street camera avoids a foreground tree that obscured the earlier traversal capture.
No tree was hidden for the photograph.

![Warehouse](images/world_warehouse_w1_street.png)
Warehouse W1: three thin-roof bays, two working vehicle entrances and 99 m² basement.
The exposed concrete apron no longer contains the earlier soil patch. Each driveway
was tested with the real vehicle.

![Surveyed civic streets](images/world_school_s2_overview_final.png)
Overview retains separate lot grades and forest between buildings. This remains a
review layout: irregular road shoulders, repetitive concrete/timber appearances
and full-world frame pacing are not presented as finished world-quality acceptance.

![Actual basement](images/world_town_hall_t1_basement_final.png)
Town-hall basement after continuous stair descent: retained block floor, walls,
ceiling, staircase and storage. No cutaway or hidden upper floor in this view.
[Church](images/world_church_c1_basement_final.png),
[school](images/world_school_s2_basement_final.png) and
[warehouse](images/world_warehouse_w1_basement_final.png) basement captures use the
same room-facing camera; all four actual capsules reach supported lower floors.

## Earlier rejected preparation

![Earlier trader preparation](images/preparation_before_trader_t1_street.png)
Earlier preparation trial, preserved as historical evidence; a different review
save/view from the final capture. Roof/arrival tree clearance was incomplete.

![Earlier warehouse apron](images/preparation_before_warehouse_w1_street_final.png)
Earlier warehouse preparation with terrain crossing the apron. The fix now lives
in shared native contact/earthworks and publication validation, not a private
warehouse offset. See the linked terrain issue for rejected experiments.

## Earlier isolated design review

All images below are Godot 4.7.2, Forward+, 1920×1080, on the same isolated review
ground with no terrain seed. They are proposals, not an accepted populated world.
Sources and SHA-256 hashes are retained in [the manifest](images/manifest.json).

![Trader house exterior](images/trader_t1_0.png)
Trader T1: covered arrival and an enclosed house, built from 1,019 native cells.

![Trader inside](images/trader_t1_3.png)
One retained Human R11 player model at the sales counter, using full-body idle.
The stockroom is behind the partition. Character asset notices remain unchanged.

![Trading interface](images/trade.png)
Actual approach-to-counter/UI test, after buying and selling three wood.
Finite coins and stock, quantity selection and per-item bid/ask prices.

![Town hall](images/town_hall_t1_0.png)
Town hall: portico, two floors, public hall and council room; 99 m² basement.

![Basement](images/town_hall_t1_4.png)
Town-hall basement cutaway: three-metre clear room, two-metre-wide stairs and
storage. This view removes upper blocks temporarily; it is not missing geometry.

![Church](images/church_c1_0.png)
Church: tall nave, side vestry, entrance tower and supported multi-cell cross.

![Church interior](images/church_c1_3.png)
The low annex meets a continuous nave wall. Central aisle remains traversable.

![School](images/school_s2_0.png)
School: two-storey classrooms and a library wing, with an 81 m² basement.

![School plan](images/school_s2_2.png)
Reversible cutaway shows the main corridor, classrooms, library and stair zone.

![Warehouse](images/warehouse_w1_0.png)
Warehouse: three thin-roof bays, two five-metre loading openings and 99 m² stores.

## Isolated design verification

New building arrangements/metadata are original CC0-1.0 assets with reproducible
[authoring and provenance](../../reviews/civic_buildings/provenance.json). New
code is 0BSD. Existing player, textures, furniture and native libraries retain
their prior terms and provenance qualifications. There are no imported assets.

Engineering evidence is in [docs/evidence/civic_buildings](../../docs/evidence/civic_buildings):

- Whole-set walkthrough: 125 checks, zero failures. Native combined block/model
  publication, independently removed cells, reversible cutaways, doors, approaches,
  every authored staircase both ways, landings and room entrances.
- Final church follow-up after the shared-wall/cross corrections: 20 checks,
  zero failures. Fresh-process complete-set restoration: 38 checks, zero failures.
- Trader inventory: 16 checks on debug and release; 15 on release fresh-process
  restore. Includes out-of-stock rollback preserving both byte snapshots and
  revisions, full backpack, lack of funds, stale offers and work bounds.
- Existing player-inventory regression: 32 checks on debug and release.
- Actual walking/UI test: 10 checks, zero failures. Walks from public approach,
  opens the NPC panel, buys/sells through its controls, refuses a wall-occluded
  transaction, and verifies no duplicate trader or stock refill on return.
- 26 rendered views captured; representative exteriors, interiors, basement,
  cutaway and UI inspected by Codex. No user visual acceptance is inferred.

Rejected trials remain visible: API call misuse in initial setup, windows under
adjoining roofs, an old traversal time budget too short for the church aisle,
and a quantity test that assigned a SpinBox value without editing its text.
Those logs are retained with their passing replacements. The route check now
uses actual path length, without teleporting between intermediate positions.

## Earlier rejected images

![Initial church exterior](images/church_initial_exterior.png)
Rejected initial proposal: unsupported/disconnected cross pieces. The final
cross uses connected oriented native panels and a grid-owned support block.

![Initial church interior](images/church_initial_inside.png)
Rejected initial proposal: the annex roof overwrote the shared nave wall.
Authoring now restores the full shared wall and its intended doorway.


## Review and future work

The user approved the implementation, all five exact R1 designs and the expansion
direction on 2026-10-30. No renewed approval is needed for those exact designs.
The [shape and texture proposal](../../docs/BUILDING_EXPANSION_REVIEW.md) recommends
shallow roofs/joints, cornices, searchable baked previews, and a four-slot material
study before a versioned eight-appearance system. The pack remains to be
implemented. Its next review must demonstrate justified gains in actual populated
worlds, with matching before/after views, gameplay and measured costs; the
[acceptance requirements](../../docs/BUILDING_EXPANSION_REVIEW.md#required-real-world-review)
are mandatory before final expansion approval.

Prices and stock balance remain reviewable. The current trader intentionally sells
eight commodities; equipment durability, quests and automatic restocking are not
part of this commodity catalog. Existing saves and approved buildings are intact.
General frame pacing remains open in the [runtime issue](../runtime-performance/README.md).

From TerraForest: `python tools/review_civic_world.py` opens the exact review world.
Use `--create` only for another uniquely named review save. Press M for the named
building markers; E near the trader opens trade, Escape closes it. The earlier
isolated viewer remains available with `python tools/review_modular_buildings.py
--civic --persistent-review`; it is historical asset evidence, not the integrated world.

# Trader house and civic buildings

- Status: Implemented review candidates / world integration pending.
- Updated: 2026-10-30. Branch: `codex/trader-civic-buildings`.
- User review: Not yet reviewed; none of these R1 designs is a generation default.
- Scope: One functioning commodity trader in a house, plus four large buildings
  with medium partial basements. This is an isolated playable architecture review.

## Current images

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

## Changes and verification

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

## Remaining / resume here

1. Obtain each building's visual decision before adopting it as a default.
   Review the massing, furniture, roof junctions and palette at player scale.
   The narrow material palette remains visible; see the
   [shape/material expansion review](../../docs/BUILDING_EXPANSION_REVIEW.md).
2. After approved revisions, integrate exact prefab cells into surveyed lots,
   master-plan basement excavation, roads and landscape. Verify actual-world
   arrivals, basement access, persistence and local removal. No existing save
   should be rebuilt or repainted automatically.
3. Register currency before the first player inventory grant and register the
   merchant native snapshot in the compound world save. Connect the one authored
   trader identity/anchor to bounded activation and live world reach/readiness.
   The present trader is stationary in the review, not a roaming world resident.
4. Measure a populated 1080p route: p95/worst frame, CPU/GPU costs, memory and
   streaming/near-far behavior. No no-regression claim is made from these checks.
5. Extend trade to equipment only with wear/fill-preserving transfers and a
   declared valuation policy. Quests, replenishment and multiplayer are not part
   of the current commodity transaction contract.

These pending requirements are also linked from `WORLD_FOUNDATION_STATUS.md`.
The production world is deliberately not promoted from these isolated results.

## Reproduce

From TerraForest in the attached worktree:

```text
python tools/review_modular_buildings.py --civic --persistent-review
python tools/run_godot_check.py civic_buildings --headless --timeout 300 --require CIVIC_BUILDINGS
python tools/run_godot_check.py trader_interaction --require TRADER_INTERACTION
python tools/check_trader_release.py
```

The persistent review uses its own `civic_trader_review_v1.tfworld`, never a
gameplay slot. F5 saves coins and stock together; no automatic restocking.
All temporary test outputs stay under `reports/`; original failed evidence is
retained separately above. Existing approved buildings and user saves are intact.

# Additional large house C1

- Status: Proposal / engineering checks passed; user visual approval pending.
- Updated: 2026-10-27. Base: `baa8a247`; C1 source/image hashes in `images/manifest.json`.
- Two above-ground storeys, 7 × 3 m supported balcony, open 5 m garage entrance,
  two upper rooms with simple timber bed frames and a stair-accessed storage cellar.
- 1,914 native destructible grid cells; 41 attached doors/windows/furniture/storage
  objects. Offline recipe bakes once; no per-frame scripted building generation.
- Existing houses, generation recipes, player saves and installed game are unchanged.

## Images

![C1 exterior](images/exterior.png)
Isolated C1 proposal, 1920 × 1080, TerraForest materials and daylight; no world/seed.
Both roofs use existing thin slope/ridge/seam blocks, not one building-sized mesh.

![C1 cutaway](images/cutaway.png)
Same proposal/settings. Deliberately removed roof, near walls and front floor
sections expose three levels and stairs. It is a reversible illustration, not the
actual damaged/save state. Attached objects over removed parts are hidden too.

## Verification / reproduce

- Review: `python tools/review_modular_buildings.py --large-house`.
- `python tools/run_godot_check.py large_house --headless --timeout 60 --require "LARGE_HOUSE checks="`.
- Final [native check](../../reports/checks/20261027T124625429496Z/console.log): 43/43;
  both stairs up/down, nine opening doors, all room routes, balcony, garage link,
  a vehicle-sized clearance envelope, individual roof removal and compound storage.
- [Fresh-process restore](../../reports/checks/20261027T124637292469Z/console.log): 21/21.
  [Eight rendered views](../../reports/large_house/render_final/console.log): 28/28;
  exterior, cutaway, ground floor and bedroom inspected. Review launcher also passes.
- Earlier parse/attachment/route failures remain in `reports/checks/20261027T1232*`
  through `20261027T1243*`; first renders remain in `reports/large_house/render_r1`.
  Corrected furniture positions, door swing direction and rear bedroom entrance.

## Remaining / resume here

- Approval of this exact house is required before adding it to generation/catalogue.
- Then survey a suitable lot and implement the declared basement excavation before
  construction. Floor is 4 m below grade; its conservative cell envelope is 5 m deep.
  No automatic excavation or migration of existing saves is implemented here.
- Garage is intentionally open; no functioning sectional garage door is claimed.
  Vehicle-envelope clearance is not an integrated driving/terrain qualification.
- Beds are timber frames, not finished mattress/linen models. Populated-world terrain
  fit, performance, navigation and player-quality acceptance remain untested.
- Authoring: `reviews/modular_buildings/large_house_recipe.gd`; baked native resource:
  `reviews/modular_buildings/baked/large_house_c1.tres`; checks: `tests/large_house.gd`.

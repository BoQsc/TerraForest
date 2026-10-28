# City building proposals

- Status: Review-ready architecture drafts; **not integrated into generation**.
- Updated: 2026-10-28. Version: R1, commit introducing this folder; base `9872f8dd`.
- User review: Pending individually for S1, P1, H1, R1, F1 and A3.
- Scope: Six additional medium/large buildings. Existing approved houses, city clustering and player saves are unchanged.

## Designs

| ID | Building | Main footprint | Layout | Native cells |
| --- | --- | --- | --- | ---: |
| S1 | Storage warehouse | 18 × 27 m | Two loading bays, high storage hall, receiving office, shelves/chests | 1,982 |
| P1 | Police station | 27 × 19 m | Two-storey station, reception, interview/holding room, attached vehicle garage | 1,972 |
| H1 | Medical centre | 25 × 25 m L-plan | Two storeys, waiting area, consultation/treatment rooms, ward, rear stair wing | 2,360 |
| R1 | Pharmaceutical research | 23 × 23 m including annex | Three storeys, separated bench rooms, sample/archive storage, service annex | 2,748 |
| F1 | Factory | 35 × 29 m overall | Three production/loading bays, two-storey dispatch office, separate chimney | 3,501 |
| A3 | Apartments | 23 × 19 m plus balconies | Four storeys, sixteen compact studio layouts, common stairs, six balconies | 3,903 |

Footprints describe the main building envelope, not the future lot requirement.
Canopies, balconies, roof overhangs and a three-metre clearance are included in
each prefab's actual bounds/`lot_clearance`. Furniture is provisional existing
table/chair/shelf/chest models and grid-built bed platforms. These are architecture
proposals, not implemented medicine, research, manufacturing, policing or apartment
simulation. The industrial bays are deliberately open, not working roller shutters.

## Review images

Actual 1920×1080 Godot renders from the R1 isolated architecture stage, not a
generated world/seed. Same daylight and material settings; framing changes with
building size. The flat green stage and floating labels are review aids, not
proposed city terrain, roadside strips or persistent building components.
Current exteriors and floor cutaways were inspected; user visual approval remains
pending. Original pixels and hashes are retained in `images/manifest.json`.

### S1 / Warehouse
![S1 exterior](images/storage_s1_0.png)
[Ground-floor cutaway](images/storage_s1_2.png): receiving office and storage aisles.

### P1 / Police
![P1 exterior](images/police_p1_0.png)
[Ground-floor cutaway](images/police_p1_2.png): station separated from the garage.

### H1 / Medical centre
![H1 exterior](images/medical_h1_0.png)
[Ground-floor cutaway](images/medical_h1_2.png): waiting space, treatment rooms and rear stair wing.

### R1 / Research centre
![R1 exterior](images/research_r1_0.png)
[Ground-floor cutaway](images/research_r1_2.png): lab bench rooms, circulation and service annex.

### F1 / Factory
![F1 exterior](images/factory_f1_0.png)
[Ground-floor cutaway](images/factory_f1_2.png) · [Production hall](images/factory_f1_3.png).

### A3 / Apartments
![A3 exterior](images/apartments_a3_0.png)
[Ground-floor cutaway](images/apartments_a3_2.png) · [Fourth-floor cutaway](images/apartments_a3_floor_4.png).

### Rejected internal draft
![Rejected early P1 floor gaps](images/rejected_police_floor_gaps.png)
Earlier uncommitted draft, same stage/camera. Thin floor cells mistakenly replaced
perimeter wall cells and left horizontal facade gaps. Corrected by closing the
floor perimeter, not by adding a cosmetic facade mesh. This image is not a candidate.

[Rejected factory valley](images/rejected_factory_valley.png): the earlier overlapping
gable modules left a visible strip of sky. Separate adjacent nine-cell bays now
meet without overwriting each other's slope cells. The archive retains both views.

## Implementation and checks

- [Offline recipes](../../reviews/city_buildings/recipes.gd) bake six native resources under `reviews/city_buildings/baked/`. No authoring loop runs during normal gameplay.
- Fabric, roof slopes, floor slabs, stairs, balconies and chimney remain individual native grid cells. Furniture, windows and doors use existing native model collections.
- Uses existing chunk baking, cache, geometry LOD, collision and combined block/model persistence. No new renderer, per-block scene nodes or native binary changes.
- [Review viewer](../../reviews/city_buildings/viewer.gd) loads one prefab at a time; exterior/rear/interior and per-floor cutaway views, door toggle, orbit/zoom. Cutaway changes restore exactly. No mouse capture, cursor warp, save loading or world regeneration.
- [Tests](../../tests/city_buildings.gd) compare every baked record/model, native publication, byte-identical combined persistence, independent top-block destruction, facade closure, roof seams, both directions through every door, all stair flights, their return landings and loading-bay walking routes.
- Corrected draft issues: overlapping windows at door cuts, inward double-door hinge obstruction, shelves intersecting beds, floor perimeter gaps, and overlapping gable modules leaving open valleys. Roof tests also require a solid vertical wall at intentional annex roof-height changes.
- [Rendered checks](../../reports/checks/20261028T143542520020Z/run.json): 86 assertions, zero diagnostics; 32 exterior/rear/interior/per-floor images in `reports/city_buildings_r1_release_images/`.
- [Final full regression](../../reports/checks/20261028T144026493626Z/run.json): 247 assertions, zero failures or runtime diagnostics. [Factory roof/route check](../../reports/checks/20261028T143706719072Z/run.json): 22 assertions, zero diagnostics.
- Launcher dry-run and actual headless `--city` startup pass. Godot generated the three new script UIDs. Its editor import retained existing nested-ZombieLab/archived-ramp duplicate-UID warnings in `reports/city_buildings_uid_import.log`; these are outside the city prefab work.
- Earlier failures retained: [doors/furniture](../../reports/checks/20261028T141611436888Z/run.json), [attachment isolation](../../reports/checks/20261028T141817060199Z/run.json), and [roof test initially rejecting a solid stepped annex junction](../../reports/checks/20261028T143303901161Z/run.json). Images exposed additional defects after basic engineering checks; passing checks alone is not design approval.

## Reproduce

From TerraForest's project directory:

```text
python tools/review_modular_buildings.py --city
python tools/run_godot_check.py city_buildings --headless --timeout 420 --require "failures=0"
```

Use S1/P1/H1/R1/F1/A3 or the arrow keys to select a building; right-drag to orbit,
wheel to zoom, Next floor for upper cutaways, Doors to operate hinges, ×/ESC to exit.
Explicit `-- --bake-city` regenerates review resources only; it is not a gameplay step.

## Remaining / resume here

- Obtain individual design approval, revising only the rejected proposals. Production integration is deliberately gated by that approval.
- Then place approved assets on terrain-fitting city lots with bounded cut/fill, street-facing entrances, loading/vehicle access, district role quotas and no city-sized flat pad. The existing rejected northern-pad layout is **not** fixed by these buildings.
- Require populated-world screenshots, entrance-to-street and NPC/vehicle access checks, native loading/streaming/LOD budgets and save/reload verification before city acceptance. Isolated capsule routes do not prove whole-world NPC navigation or vehicle access.
- Functional room furnishing, bathrooms/kitchens, equipment, loot balance and service gameplay remain separate work. Roof access and garage roller doors are not implemented.
- Return trigger: building approval; evidence needed: exact approved prefab hashes plus real generated-city terrain-fit, traversal and performance results. Current packaged game is intentionally unchanged.

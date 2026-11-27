# Three buildings larger than Homestead Manor

- Status: Engineering verified; user visual review and populated-site acceptance pending.
- Updated: 2026-11-27. Fix/build: R1 source additions; focused commit in repository history.
- User review: Not reviewed.
- Brief: Add a many-flat building, a cathedral at least twice the mansion in every dimension with a large basement and multiple levels, and a tall residential building suitable for a crowded street.

## Changes and verification

[Original offline recipes and baked prefabs](../../addons/structures/grand_buildings/README.md)
add Foundry Court (60 flats), Saint Brigid (two crypt levels, two nave galleries
and twin bell towers), and Needle Street (eight shops/workrooms and 58 flats).
The ordinary construction catalog registers all three. No existing building or
save is replaced; generation defaults retain their approved designs.

Initial headless check
[`20261127T102401660912Z`](../../reports/checks/20261127T102401660912Z/console.log)
passed strict apartment/tower placement and restoration but rejected cathedral
door/masonry overlap. The west/east buttresses obstructed tower-gallery doors;
the chapel shell also covered a previously cut opening. Authoring order and the
buttress extent were corrected. The targeted cathedral repeat
[`20261127T102706076027Z`](../../reports/checks/20261127T102706076027Z/console.log)
passes placement, exact restoration, block removal and landing headroom.
Final rendered run
[`20261127T103514993703Z`](../../reports/checks/20261127T103514993703Z/console.log)
passes **81 checks**, including strict compound placement, independent-owner
restoration, individual block removal, headroom, up/down walking at the first and
last flight of every core, nine bounded captures and restoration after cutaway.
The final recipe also closes the formerly open nave gable, groups glazing into
arched lancets, adds a porch/cross, and separates crypt/archive chambers.

[`20261127T103806398067Z`](../../reports/checks/20261127T103806398067Z/console.log)
passes all six hash/exact-restoration checks for those final snapshots in a fresh
process. The normal player-world test
[`20261127T102745559328Z`](../../reports/checks/20261127T102745559328Z/console.log)
finds every entry in the ordinary Building / Prefab selector without developer
content switches and preserves the source player-save hash. Eight launcher and
eight retention Python tests pass; startup dependencies, credit notices and exact
building provenance are current. Godot-generated script identities were retained.

| Building | Editable cells | Attached objects | Clear supported floor columns | Mansion ratio |
| --- | ---: | ---: | ---: | ---: |
| Foundry Court | 31,664 | 1,307 | 12,222 m² | 7.68× |
| Saint Brigid | 50,245 | 572 | 19,488 m² | 12.24× |
| Needle Street | 38,146 | 1,449 | 17,707 m² | 11.12× |

The mansion baseline is 1,592 m², measured by the same independent support and
two-metre headroom check. This counts fabric floor columns before furnishing
occupancy, not net lettable area. The cathedral's full bounds are 107.02 × 88.02 m
and 66.02 m high (including crypt levels), versus the mansion's full 49.74 ×
37.02 × 15.02 m envelope. Each axis clears the requested 2× threshold.

## Images

All nine final images were inspected. These use the same fixed daylight, cameras,
Forward Plus renderer and 1280 × 720 retained RGB resolution on flat fixture
ground. No world/seed or populated-street result is implied. Exact image hashes,
captions, source and the rejected gable comparison are in
[`images/manifest.json`](images/manifest.json).

![Foundry Court exterior](../../reports/checks/20261127T103514993703Z/courtyard_flats_exterior.png)
Foundry Court R1: five residential floors and roof service rooms; 60 furnished flats.

![Saint Brigid exterior](../../reports/checks/20261127T103514993703Z/grand_cathedral_exterior.png)
Saint Brigid R1: cruciform footprint, twin bell towers and covered main arrival.

![Needle Street exterior](../../reports/checks/20261127T103514993703Z/street_tower_exterior.png)
Needle Street R1: ten occupied floors, podium setbacks, balconies and roof stair pavilion.

Additional inspected views: [flat section](../../reports/checks/20261127T103514993703Z/courtyard_flats_plan.png),
[flat interior](../../reports/checks/20261127T103514993703Z/courtyard_flats_interior.png),
[closed nave and galleries](../../reports/checks/20261127T103514993703Z/grand_cathedral_interior.png),
[lower crypt](../../reports/checks/20261127T103514993703Z/grand_cathedral_basement.png),
[shops section](../../reports/checks/20261127T103514993703Z/street_tower_plan.png),
[tower flat](../../reports/checks/20261127T103514993703Z/street_tower_interior.png).
The rejected initial nave and its original receipt are preserved at
`reports/checks/20261127T103108609006Z`; use its archive receipt if cold-retained.

## Remaining / resume here

- User approval of the exact revision remains open. Generation promotion requires an approved terrain-fitting site, street/entrance traversal, basement excavation/contact review and sustained populated-world performance evidence. Return when a site and generation integration are requested; these prefabs remain additional construction choices meanwhile.
- The cathedral exceeds the existing corner-selection capture volume, while remaining within the sparse native prefab cell budget. Reuse its catalog preset; whole-building corner recapture remains unqualified, with no budget increase proposed.
- The final engine run passed, then its post-run archival was blocked by an active ordinary player process. The fresh-process repeat completed the archival after that process exited, retaining the rejected comparison in `20261127T103108609006Z/homestead.archive.json` and reclaiming 7,910,755 loose bytes. The runner now records a future active-game block as pending and preserves its output for the next idle retry; unrelated archive errors still fail visibly. No player process was stopped.

## Reproduce / history

Use the commands in the [asset README](../../addons/structures/grand_buildings/README.md).
No saved world is allocated by the prefab test. The normal catalog test opens
`Hidden_Meadow` read-only and verifies its hash. Every capture/fixture belongs to
the runner's receipt and two-ready cold archival lifecycle. Earlier failed checks
and images remain at their original receipt locations.

# Object packs, outdoor objects and Homestead mansion

Work requested 2026-11-26. Original code is 0BSD; original assets are CC0-1.0.

This task covers folder-based admission for all ten Homestead packs, an Outdoor
01 pack (bird nest, duffel bag, cardboard boxes, tires, litter, trash cans and a
large refuse container), selectable object-name inspection, a new mansion with
rooms using every Homestead model, outdoor scattering and measured player-facing
reliability/performance. Existing houses and saved worlds remain unchanged.

Implemented: eleven discovered packs / 110 objects, seven native outdoor container
types, a native spatial inspection query, selectable labels, explicit outdoor
scattering and Homestead Manor R2. The mansion is an additional Building preset
for review, not an approved generation default. Saved houses are not refurnished.

Hold Backtick, choose **2 / Objects / inspection** (or point at that card), then
hold Alt to access **Show nearby object names**. Alt alone never selects the
mode, and releasing Alt keeps the selected setting. A short Backtick tap retains
the developer switch; the original centre / 1 / F choice retains flight. Turn
inspection off to place or remove objects. Inspection suppresses the placement
ghost and mouse edits in Dev Objects; the explicit scatter button and undo remain
available. In gameplay, E opens a nearby outdoor container; E/Esc/Tab closes it.

Inspection prioritizes the aimed object and places at most 24 nearby labels in a
24 m radius. It reserves HUD space, tests text overlap and occlusion, and updates
its layout at 6.7 Hz. The native spatial index scans at most 8,192 records and
returns at most 128 candidates. Dense scenes disclose the cap. It names registered
placeable model collections; terrain cells, vegetation and loose pickups retain
their existing tools. No label or script node is created for every placed object.

Outdoor storage uses one existing native container store per object type, with
4,096 content rows per type and 4–32 slots per container. Equal placement ids in
different collections remain independent. Nonempty objects are protected from
removal, and native container bytes restore alongside the structure save. Eggs,
tires, litter, bin lids and wheels are static parts; this adds no animal, rolling,
hinged-bin or automatic loot-refill simulation.

The scatter button proposes 20 objects in a seeded 6 m patch at aim, then checks
loaded collision, support, slope, water, existing structures, player clearance
and planned roads. Candidates run one per physics frame; there is no ambient
scatter loop or automatic refill. Each successful placement uses ordinary native
edit history and can be undone. Offline authors may supply exclusion bounds;
the mansion uses the same proposal generator for its service yard.

## Folder workflow

Place a complete folder in `addons/structures/packs/` and restart the game. A
folder named `example_pack` has manifest id `terraforest.example_pack`. Do not
rename an installed folder or change its item ids: they are save identities.
The folder supplies `pack.json`, `models/<slug>.tres`, `icons.trtex`, and its
license/provenance. The 1280-pixel-wide atlas has five 256-pixel tiles per row in
manifest order. Meshes carry original-size `authored_size` and `collision_boxes`
metadata. No pack script executes during discovery. Existing author/catalog
scripts remain editable authoring and compatibility helpers.

The shared registry supplies inventory names/ids, placement menus, pack filters,
crafting/salvage, durability, icons and bounded resident-light sources. Malformed
or conflicting manifests fail admission before publishing a partial item schema.
Native model keys retain `packs/<folder>/<slug>/v1`. Keep packs required by a save
installed; removal/migration is a separate operation. New material still follows
the repository intake policy; dropping a folder does not waive provenance review.

Use `outdoor_01/pack.json` as the working example. Schema 1 requires a name,
unique numeric inventory id >=720, slug, positive health, material, recipe and
salvage. Ingredients are existing ids 101–104 or 201–228; salvage cannot exceed
cost. Optional `mount`, `container` and `light` fields drive the shared systems.
Discovery admits at most 64 packs / 192 objects, leaving native model capacity
for the base game. Each mesh needs 1–64 finite, nonempty collision AABBs. These
are explicit capacities, not permission to increase native limits silently.

No central inventory/catalog/light file needs a new per-object entry. Restart
after adding the folder, run `object_pack_registry`, and regenerate distribution
notices with `tools/build_credit_notices.py` (it discovers adjacent pack notices).
The export preset includes pack manifests; this change has not produced a new
full export. Baked native meshes and the atlas are runtime inputs; author scripts
are optional authoring sources. Resource identity changes/removal need migration.

## Mansion and visual review

Homestead Manor R2 has two storeys around a courtyard, a broad central stair,
balcony, kitchen/pantry, dining room, study, garden salon, workshop, utility room,
principal suite, bathroom, dressing room, guest rooms and upper sitting room.
Its 5,280 editable cells and 265 model attachments include all 100 distinct
Homestead objects and 20 outdoor service-yard objects. Walls, floors, windows,
doors and thin roof parts use the existing native construction system.

[Visual history and current captures](../issues/homestead-manor/README.md) retain
the rejected stone-floor R1, the nest/bag refinements, the cutaway hide-limit
correction and corrected furnishing support heights. Engineering checks do not
constitute user visual approval or terrain-fit acceptance.

## Evidence

All paths below are under `reports/checks/`; receipts include engine, source and
native hashes. Tests use temporary worlds or native fixtures, never player saves.

| Check | Evidence | Result |
| --- | --- | --- |
| Final registry, identity, recipes, icons and malformed manifest rejection | `20261126T115256881616Z` | 230 checks |
| Outdoor model placement, legacy save compatibility, 1,000 records and final atlas | `20261126T115044082821Z` | 91 checks, 5,226 µs native insertion; 56,898-byte structure snapshot |
| Container isolation/protection/restoration; scatter repeatability/roads; dense query cap | `20261126T113710977185Z` | 45 checks; 8,300-record fixture scans <=8,192, returns 8; about 2.15 ms |
| Existing Homestead 07 and bounded light behavior | `20261126T115325954583Z` | 103 checks |
| Universal drop/recollect/native persistence | `20261126T115354298277Z` | 1,273 checks |
| Physical item drops | `20261126T115411514562Z` | 196 checks |
| Rendered G/input/menu regression | `20261126T115430276102Z` | 35 checks |
| Ordinary game, input, live terrain scatter, storage transfer and measured traversal | `20261126T114720440938Z` | 26 checks; 20 terrain-supported scatter placements |
| Fresh-process structures and filled duffel restoration | `20261126T114847008189Z` | Byte-exact structure state, contents and removal protection pass |
| Final mansion and furnishing support / six captures | `20261126T115544624062Z` | 26 checks; stair up/down and six contact rays pass |
| Final inspection UI, controls, terrain scatter and timing | `20261126T120200048287Z` | 32 checks; panel fit, no placement ghost, no mouse removal in inspection |
| Fresh process with the final native fixture | `20261126T120312118423Z` | Exact structure state, stored contents and protection pass |

Both structures native configurations were rebuilt. Retention tests pass (3).
Headless editor import `object_system_uid_import_20261126T115919Z` passed and
generated matching Godot identities. All ten existing Homestead provenance files,
new Outdoor/mansion provenance and all 33 bundled notices pass their check modes.
Final inspection captures are in `20261126T120200048287Z`; the fixture input
event reuse warning in preceding run `20261126T120000726928Z` was removed.
Harness parse failure `20261126T115723689836Z` remains in its receipt; an explicit
packed-byte-array type corrected it. No production error was hidden.

## Player-facing timing scope

The successful initial ordinary-game run `20261126T114720440938Z` used Godot
4.7.2 Forward+, an RTX 4050 Laptop GPU and 1920×1080, with VSync/frame limiting
disabled for measurements. Initial loading took 19.1 s. The same courtyard walk
covered 13.75 m in both legs. Captures occur outside the timed intervals.

| Scene | Frames | Median ms | p95 ms | p99 ms | Worst ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Courtyard walk, names off | 694 | 3.36 | 5.36 | 6.45 | 8.99 |
| Courtyard walk, names on | 560 | 4.23 | 6.06 | 7.61 | 16.13 |
| 1,000 additional outdoor objects, names on | 216 | 18.39 | 20.59 | 21.96 | 24.99 |

The native query plus label-layout p95 was about 2.05 ms when enabled (last query
cost sampled each frame, not an amortized per-frame cost). Draw-call p95 was
1,982 / 2,037 / 1,754. Measurements are a short local comparison, not a universal
performance guarantee: the manor fixture is above terrain to isolate placement;
the dense final leg is stationary with the ordinary world physics tick disabled.
The walking legs use normal gameplay physics. The 1,000-object scene does not
meet a 16.7 ms frame budget on this machine. The final UI refinement is remeasured
separately so the earlier result remains reproducible.

Final run `20261126T120200048287Z` used the same scope and hardware. Loading was
18.5 s; both walking legs again covered 13.75 m. The final native-state fixture
SHA-256 is `3ace2e8a9ea472d05cd7df1a61871b27b7a0e0be30db3c5ced9df139fdf0b62a`.

| Final scene | Frames | Median ms | p95 ms | p99 ms | Worst ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Courtyard walk, names off | 644 | 3.66 | 5.32 | 7.82 | 12.49 |
| Courtyard walk, names on | 650 | 3.70 | 5.03 | 6.33 | 9.23 |
| 1,000 additional outdoor objects, names on | 222 | 17.84 | 19.79 | 20.53 | 21.80 |

Draw-call p95 was 1,975 / 2,029 / 1,755. Enabled query/layout p95 was 1.76 ms on
the walking leg and 2.29 ms in the dense view. The small on/off timing difference
is within short-run variation; it does not establish that labels improve speed.
The JSON counts assertions before cleanup; the console's 32 also includes the
successful shutdown assertion. The dense frame-budget limitation remains.

## Remaining acceptance and return triggers

- User visual review of the mansion is pending. Before making it a generation
  default, fit a real lot to terrain and roads, then verify all entrances, room
  circulation, ground contact and generated neighbouring views. Current tests
  cover prefab clearance, the main stair in both directions and a courtyard walk.
- Dense rendering needs optimization before claiming 60 FPS with 1,000 extra
  mixed props. Profile mesh/material/shadow cost and resident pages against this
  retained route, then repeat player traversal with full simulation and longer
  samples. Do not hide this limitation behind fast native insertion timings.
- Package/export discovery remains to be exercised by the next requested build;
  manifests are included by the preset, but this task creates no full export.
- Interactive cabinet lids, cloth, individual litter, rolling tires and loot
  population remain separate designs. These are static props plus shared storage;
  existing Homestead interaction limitations still apply.

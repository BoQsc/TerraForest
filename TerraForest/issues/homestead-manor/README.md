# Homestead Manor, outdoor pack and inspection review

- Status: Improved-partial.
- Updated: 2026-11-26. Fix/build: implemented by the commit adding this issue, `feat: integrate object packs, outdoor storage and Homestead Manor`. Captures used base `e671b37d` plus the exact source/native hashes in their receipts.
- User review: Not reviewed. Engineering verification is not visual approval.
- Symptom: The first large furnished-house draft had stone floors throughout;
  intermediate captures exposed unsupported tabletop details, a misleading
  cutaway and an over-wide inspection panel.

## Images

These are actual Godot 4.7.2 Forward+ captures, 1920×1080. Mansion views use the
authored native fixture on a plain level stage, not a generated settlement or
player save. Camera changes are identified below. Sources and SHA-256 hashes are
recorded in `images/manifest.json`. Reports remain under their original receipt
and retention lifecycle; cold captures can be restored into a new inspection
directory using their adjacent `homestead.archive.json`.

![Rejected R1 salon](../../reports/checks/20261126T113606125927Z/mansion_salon.png)

Rejected R1: stone walls/floors made the living space feel unfinished. This
baseline is explicitly retained. No player-save modification was involved.

![R2 courtyard mansion](../../reports/checks/20261126T115544624062Z/mansion_exterior.png)

Current R2: courtyard, two garden wings, thin slate roof parts, timber balcony
and separate service yard. The wider exterior camera includes the whole building;
it is not a same-view performance comparison.

![R2 ground floor](../../reports/checks/20261126T115544624062Z/mansion_plan.png)

Current ground-floor section: kitchen/pantry, utility, workshop, arrival hall,
dining, study and salon. Upper records are temporarily removed and then restored
byte-exactly. The earlier visual-hide method hit a 32-record cap per collection
and left some upstairs windows floating in the cutaway; that was a capture bug.

![R2 salon](../../reports/checks/20261126T115544624062Z/mansion_salon.png)

Current salon: timber floor/ceiling, grouped seating, chess and reading/music
objects. Same room camera as R1. Existing materials and original pack models
retain their notices; this is not a new third-party texture intake.

![Rejected floating blanket and bottle](../../reports/checks/20261126T115201989434Z/mansion_bedroom.png)

Rejected intermediate R2 detail: using the bed's overall height placed blankets
above its headboard height. The same error affected a stove splashback, mirror
backstop, sink tap and trolley handle. The bedroom camera now avoids the screen
which obscured the earlier view.

![Corrected bedroom support](../../reports/checks/20261126T115544624062Z/mansion_bedroom.png)

Corrected R2, matching the immediately preceding camera: blanket stack sits on
the mattress, bottle stands beside the bedside clock, mirror sits on its tabletop.
Six downward contact checks accompany native whole-prefab collision admission.

![Rejected outdoor shapes](../../reports/checks/20261126T110320093900Z/outdoor_01.png)

Rejected Outdoor 01 baseline: nest read as a solid bowl and refuse bag was boxy.
This comparison is explicitly retained.

![Current outdoor pack](../../reports/checks/20261126T115044082821Z/outdoor_01.png)

Current Outdoor 01: irregular twig nest and rounded refuse bag; ten original
objects with dimensions and labels. Seven types have shared native storage.

## Changes and verification

The native prefab uses all 100 Homestead objects with 265 total attachments and
5,280 independently editable cells. The final mansion check
[`20261126T115544624062Z`](../../reports/checks/20261126T115544624062Z/console.log)
passes 26 assertions including strict placement, exact restoration, local block
removal, six furnishing contacts and the main stair up/down. Six rendered views
were produced; all relevant rooms have been visually inspected during this work.

The ordinary-game check reaches both the normal Building preset and folder-based
Outdoor menu; input, storage transfer, native reload and a terrain-supported
20-object scatter are exercised. The first isolated test's three failures were
test-fixture mistakes: it expected mouse capture prohibited by isolated mode,
and tried to drag a belt slot excluded from the backpack grid. Fixed rerun:
[`20261126T114720440938Z`](../../reports/checks/20261126T114720440938Z/console.log).
Fresh-process contents/guards:
[`20261126T114847008189Z`](../../reports/checks/20261126T114847008189Z/console.log).

The first inspection picture also showed its title overlapping the status HUD,
a long-name dropdown widening the side panel and an object-placement ghost.
The revised overlay reserves HUD regions; the dropdown clips its displayed
selection; Dev Objects inspection suppresses the ghost and mouse edit actions.
The final ordinary-game run
[`20261126T120200048287Z`](../../reports/checks/20261126T120200048287Z/console.log)
passes 32 checks. Final fixture restoration passes in a separate process at
[`20261126T120312118423Z`](../../reports/checks/20261126T120312118423Z/console.log).

![Current inspection UI](../../reports/checks/20261126T120200048287Z/object_names.png)

Final ordinary temporary game, seed 1703, salon camera. Name labels avoid each
other and the HUD; aimed object has priority, and Alt only accesses the controls.
The manor is above terrain in this route, not evidence of an accepted building lot.

## Rendering follow-up

![Matched material comparison](../../reports/checks/20261126T133656440181Z/combined_materials.png)

Actual six-camera render comparison after material consolidation. The matching
[source materials](../../reports/checks/20261126T133656440181Z/source_materials.png)
differ by at most one RGB level; the camera faces the cabinet glazing. Matched
[distant source](../../reports/checks/20261126T133656440181Z/lod_source.png) and
[distance LOD](../../reports/checks/20261126T133656440181Z/lod_render.png) views
were also inspected. Shader-discard and lamp-edge failures remain in the image
manifest with their original cold-archive receipts.

![Full-game mixed-object walk](../../reports/checks/20261126T134609137005Z/names_on_out.png)

Actual normal-game walking view with 1,000 added objects from all eleven packs,
plus the existing world. This temporary test floor at Y=44.25 is not a mansion
lot or a save edit. All 3,506 model records remained rendered, with normal AI,
physics, vegetation, actors, vehicle fleet and pickups enabled. The HUD's
instantaneous FPS does not qualify the run: slow-frame p95/p99 gates failed.
The [performance report](../../docs/OBJECT_RENDERING_PERFORMANCE.md) records
the complete four-leg data and zero-added-object control.

The [Outdoor 01 v1.0.1 sheet](../../reports/checks/20261126T124759765199Z/outdoor_01.png)
shows the reduced tessellation at unchanged authored dimensions. Its 94 checks
pass. Icons use the original authored meshes, so render-cache changes do not
require rebaking them; source/output hashes are refreshed in pack provenance.

## Remaining / resume here

User visual approval remains open. Before generator adoption, fit a real lot,
verify ground/road contact and traverse every room/entrance with full gameplay
collision and doors. The main-stair and courtyard checks do not cover every
possible route. Do not replace established houses or refurnish player saves.

The [full-game rendering follow-up](../../docs/OBJECT_RENDERING_PERFORMANCE.md)
reduces outdoor geometry and consolidates compatible materials, adds distance
LODs and tests four walking legs with all normal systems enabled. Its strict
1,000-extra-object p95/p99 frame gate still exceeds 16.7 ms. Continue from the
retained CPU/GPU measurements and control route before claiming dense-scene
60 FPS. Material/LOD comparison pictures are engineering checks; mansion user
approval remains open. No new runtime
simulation is implied for individual litter, eggs, cabinet lids or tires.

Detailed controls, pack-folder contract, evidence and timing scope:
[Object pack integration](../../docs/OBJECT_PACK_INTEGRATION.md).
Code: [mansion author](../../addons/structures/mansion/author.gd),
[pack registry](../../addons/structures/pack_registry.gd),
[inspection overlay](../../addons/player_runtime/object_inspector.gd).

## Reproduce / history

### Future-house population, 26 November

The user selected **future houses only**. Ordinary new construction and generation
now add pack furnishings to the existing residential designs, with original cells
and inherited objects retained. Existing saves receive no automatic additions.

| House preset | New pack objects |
| --- | ---: |
| Basic brick cottage | 18 |
| Furnished basic / enclosed cottage | 19 |
| Large two-storey house | 30 |
| Residential tower | 26 per floor (52 / 78 / 104 for the current 2 / 3 / 4-floor variants) |
| Sixteen-unit apartments | 153 |

Shops, trader and workshop add 3–6 work-surface objects. The current mansion
already has its full pack layout. Generate & play additionally targets 16 outdoor
objects per lot through seeded side/rear proposals, with terrain footprint,
tree-root, water, road/approach, parking and encounter exclusions. Unsuitable
positions are skipped; removed objects do not refill.

- `20261126T172449697845Z`: 98 checks pass across twelve catalog variants, all
  four placement rotations, every apartment/tower sleeping space, native object
  persistence and the ordinary upstairs introduction exit. Three actual interior
  images were captured and inspected. They show the retained house designs with
  added furnishings on a native fixture, separately from landscape acceptance.
- `20261126T172604199876Z`: a fresh process restores the exact fixture and object
  identities, SHA-256 `5d76733279a07444c38c1aad292bebe846c3735df766d34338aaa68bcc3fbfb6`.
- `20261126T172654731486Z`: normal temporary gameplay passes nine checks. Forty-seven
  outdoor objects of thirteen types pass actual terrain and clearance admission
  around three transient lot probes; the native snapshot remains valid. Hidden
  Meadow's canonical save stays byte-for-byte unchanged. The picture is a
  temporary outdoor placement check in the existing world, not a refurnished save.
- `20261126T172253885102Z`: 40 normal-catalog and complete single-district planning
  checks pass, including unchanged terrain footprints and cached reconstruction.
- `20261126T171654243044Z`: the original full default plan timed out at 240 s.
  Profiling `20261126T173809036603Z` also remained in its first settlement until
  the 120 s limit. Both failed receipts remain intact. The search was repeatedly
  rebuilding furnished prefab recipes for terrain candidates and variants.
- `20261126T174209159050Z`: 42 checks pass; search-local recipe reuse matches
  freshly authored civic, city, neighbourhood and market recipes at integer and
  fractional centres, including complete prefab fingerprints and plot coordinates.
- `20261126T174332284109Z`: all 40 full-default checks pass. The cold placement
  plan completes in 69.603 s with six districts and 52 buildings; native terrain,
  entrance, road and earthworks checks remain in force. Warm reconstruction
  preserves the exact plan digest.
- `20261126T174619035076Z`: the explicitly requested playable **Homestead Valley**
  is created through normal Generate & play, seed 1703 / terrain 29 / default
  **Frontier expedition**. Native generation, verification and publication succeed;
  the game opens in 216.044 s with 684 supported outdoor objects of thirteen types.
  The driver records one stale assertion expecting the old Connected countryside
  label; its actual recipe equals the unchanged defaults. That assertion is fixed
  to Frontier expedition, and this receipt remains failed rather than rewritten.
  The new player world is preserved, separately from disposable capture retention.
- `20261126T175057755722Z` and `20261126T175355747079Z` retain successful
  fresh-game object/pose/hash assertions with one failing harness comparison:
  JSON parses numeric recipe values as floats, which native recipe admission
  correctly refuses. The capture driver now converts these receipt fields back
  to integers before canonical encoding. `20261126T175313149767Z` retains an
  intermediate capture-driver type-inference parse error, fixed with an explicit
  Vector3 annotation. The first yard camera was obstructed by a house; the
  corrected camera faces a populated yard from outside its nearest building.

Complete room/entrance traversal and sustained population frame qualification
remain open. Close them with actual routes and full-game frame traces; generation
and persistence success do not establish universal terrain or visual acceptance.

- `20261126T172839981722Z`: the existing prefab-library capture/reopen and rotated
  placement regression passes with the new objects. Ten launcher/retention tests
  pass, and admitted editor import `house_population_uid_import_20261126T173006617403Z`
  generates all four new script UIDs without engine errors.

Earlier failed checks remain retained: `20261126T170617470057Z` has a corrected
test assertion-helper parse error; `20261126T171312897503Z` rejected a valid surface
reply by comparing the publication and density revision counters. The outdoor
pass now checks each counter against its corresponding captured source state;
the final real-terrain replay passes. The full-default planning timeout is now
fixed by the search-local recipe reuse described above; full room traversal and
populated-world frame qualification remain open.

![Newly furnished cottage](../../reports/checks/20261126T172449697845Z/cottage.png)

Same cottage fabric and original furniture; new sleeping, kitchen and household
objects occupy the spare room edges. This is an inspected native fixture view.

![Outdoor placement check](../../reports/checks/20261126T172654731486Z/outdoors.png)

Actual terrain-supported boxes, storage, refuse and garden objects in a temporary
read-only session. This does not claim stable 60 FPS or a saved-world retrofit.

Implementation, reproducible commands and retention scope are in
[Object pack integration](../../docs/OBJECT_PACK_INTEGRATION.md#future-house-furnishings-and-outdoor-population).

The CPU follow-up stages character/corpse admission and prepares large saved
head hulls on a worker. Lifecycle, collision-contact and rest checks pass;
the uncontended replay `20261126T142559219408Z` passes all 36 gameplay assertions
but fails all four 60 FPS gates. One corpse-walk torso-speed failure reproduces
exactly on the committed baseline and remains open. Full evidence and the next
draw-submission work are in the linked rendering report; this is not a stable
60 FPS or visual-approval claim.

The final character-material follow-up reduces visible rig surfaces from 45 to
14 while preserving skin, morphs, contact geometry and severed-mesh baking.
Replay `20261126T165138197821Z` passes all 36 functional assertions and one of
four strict timing gates. The user requested closing this investigation with
commit/push; stable 60 FPS remains open. The linked performance report contains
the final timing table, retained diagnostics and explicit resumption criteria.

From `TerraForest`, use the admitted runner:

```text
python tools/run_godot_check.py homestead_mansion --isolated-render --require failures=0 --timeout 120
python tools/run_godot_check.py object_system_world --isolated-render --require failures=0 --timeout 240
```

The first creates a bounded native stage; the second creates a temporary ordinary
world with no player-save writes. Backtick hold → 2 / Objects → hold Alt and
select nearby names. Alt alone does not enable labels. Building presets include
Homestead Manor R2; it is deliberately not a world-generation default.

Earlier placement failures `20261126T110837607606Z`, `20261126T113151793913Z`
and `20261126T113412856973Z` remain in the original reports: furniture clearances
and the outdoor attachment envelope were corrected, not bypassed.

### Requested generated world: fresh-process evidence

`20261126T175554049707Z` passes all 19 checks in a new normal-game process. My worlds
lists Homestead Valley; the native default recipe and publication receipt match.
The saved plan contains 35 populated residential/service lots and 3,789 planned
attachments. Both inspected houses restore every authored Homestead object
position in their native collections. A generated yard prop retains its native
identity/pose; the 684-prop publication is preserved. The `.trw` SHA-256 remains
`1626bc34b2da9fbebe5666b2b3336578652e88590f69935ed512c898d43fe115`
after read-only inspection. Eleven launcher/retention unit tests pass; capture
retirement excludes the player world and keeps its creation provenance.

![Furnished cottage in the new world](../../reports/checks/20261126T175554049707Z/cottage_interior.png)

Actual published world, cottage interior; furnishings, original fabric and nearby
terrain are loaded from the saved world. This is no longer the isolated fixture.

![Large-house kitchen in the new world](../../reports/checks/20261126T175554049707Z/house_interior.png)

Actual saved large-house kitchen, with original chest and added kitchen objects.

![Generated outdoor yard](../../reports/checks/20261126T175554049707Z/outdoor_yard.png)

A nine-object local group in the generated workshop yard: boxes, tire, duffel,
planter, basket, refuse and garden objects. Camera faces inward from outside the
nearest building, correcting the earlier obstructed view. All three full-resolution
images were inspected. They establish this capture's visible population, not
complete site-quality acceptance, every-room traversal or stable 60 FPS.

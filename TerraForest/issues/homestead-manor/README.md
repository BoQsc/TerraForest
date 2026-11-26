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

## Remaining / resume here

User visual approval remains open. Before generator adoption, fit a real lot,
verify ground/road contact and traverse every room/entrance with full gameplay
collision and doors. The main-stair and courtyard checks do not cover every
possible route. Do not replace established houses or refurnish player saves.

The 1,000-extra-object frame test exceeds the 16.7 ms budget. Profile material,
mesh and shadow cost, compare the same retained route, and test longer walking
samples with full simulation before claiming dense-scene 60 FPS. No new runtime
simulation is implied for individual litter, eggs, cabinet lids or tires.

Detailed controls, pack-folder contract, evidence and timing scope:
[Object pack integration](../../docs/OBJECT_PACK_INTEGRATION.md).
Code: [mansion author](../../addons/structures/mansion/author.gd),
[pack registry](../../addons/structures/pack_registry.gd),
[inspection overlay](../../addons/player_runtime/object_inspector.gd).

## Reproduce / history

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

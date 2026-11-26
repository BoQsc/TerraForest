# Homestead household object packs

Four separate original asset packs extend the existing table/chair/shelf/chest
set. They use stable pack, item and native model identities, with committed
baked meshes, icon atlases, editable source and exact hash provenance.

| Pack | Contents | Items |
| --- | --- | --- |
| [Homestead 01 — Household Essentials](../addons/structures/packs/homestead_01/README.md) | Bed, nightstand, wardrobe, counter, cupboard, sink, stove, sofa, books, mug | 720–729 |
| [Homestead 02 — Lived-in Details](../addons/structures/packs/homestead_02/README.md) | Rug, curtains/rail, landscape picture, clock, coat rack, basket, crate, bottle, dishes, lamp | 730–739 |
| [Homestead 03 — Washroom & Utility](../addons/structures/packs/homestead_03/README.md) | Bathtub, toilet/cistern, mirror, towel rail, folded towels, soap dish, paper holder, laundry tub, washboard, broom/dustpan | 740–749 |
| [Homestead 04 — Workshop & Repairs](../addons/structures/packs/homestead_04/README.md) | Workbench, vise, wall tool board, toolbox, sawhorse, plank stack, paint tin/brush, rope, cable spool, handcart | 750–759 |

All four appear independently in the Objects pack filter and Dev Bag categories.
Normal placement, recipes, partial salvage, durability, native history, model
streaming and structure save/reload remain shared. Inventory drops use the
universal parcel fallback and existing bounded physical pool. No new per-item
save provider or ticking node is introduced. Existing player worlds are not
refurnished or rewritten by admitting the packs.

Homestead 02 adds wall placement shared by carried objects and the Objects tool.
The visible back sits 15 mm clear of the support plane, with authored support
points checked against solid wall geometry. Curtains test only their two rail
brackets so they can span a window. Floor hits, absent support, unready bounds
and occupied carried placement are rejected. The table lamp joins the existing
four-slot native resident light pool; its source index metadata includes the new
collection without shifting existing provider identities.

## Rendered review

These are rendered from the actual committed models, not concept illustrations.
User visual acceptance remains separate from engineering checks.

![Homestead 01 household essentials](../reports/checks/20261126T082623911470Z/homestead_01.png)

Homestead 01 first model pass. Earlier stale-viewport and missing-mug-surface
renders remain at their original receipt paths; the latter was corrected by
indexing custom vertices before combining them with indexed primitive meshes.

![Homestead 02 lived-in details](../reports/checks/20261126T083427198184Z/homestead_02.png)

Homestead 02 final authoring preview. The earlier landscape-backface witness
is retained at `reports/checks/20261126T083302766544Z/homestead_02.png`.

![Homestead 03 washroom and utility](../reports/checks/20261126T085621379763Z/homestead_03.png)

Homestead 03 authoring preview: open fixture geometry, cream enamel, zinc and
folded fabrics. Its mirror uses a simple finish and authored highlights without
live room reflections. Editable new geometry reuses the existing Homestead 02
0BSD offline helpers; the exact helper hash is retained in pack provenance.

![Homestead 04 workshop and repairs](../reports/checks/20261126T091005146674Z/homestead_04.png)

Homestead 04 authoring preview: open furniture frames, mechanical details,
continuous rope/cable meshes, and a spoked handcart. These are static furnishings.

## Scope and return triggers

These are furnishings. Clock hands are static, cloth does not simulate and
storage/cooking/sleeping/sitting/water-exchange interactions are not implemented.
The lamp follows existing always-on resident-light behavior rather than adding
independent switching state. Basket/crate and Homestead 01 cabinet storage need
shared cross-collection container identities before implementation. Acceptance
requires equal-local-ID isolation, nonempty-removal protection, transfer/lock
behavior and fresh-provider reload. Clock motion needs a shared world-time
contract and reload checks. Other interactions need their gameplay contracts
before adding behavior; their absence is not a completed feature.

Homestead 03 plumbing, washing, cleaning, fixture water storage and soap/paper
consumption remain unimplemented. Fixture behavior needs a shared capacity and
volume-conservation contract, native inventory transfers and fresh-provider
reload evidence. Live mirrors require a separate bounded reflection experiment,
sparse/dense timings and an explicit fallback before default admission. These
requirements are deferred to their gameplay/effect contracts, not declared done.

Homestead 04 crafting, usable hand tools, moving vise/lid parts, toolbox storage,
paint application, rope/cable attachment and cart motion remain unimplemented.
Crafting needs shared recipe/progress transactions and conservation/reload
checks. Storage needs the existing cross-collection ownership prerequisite.
Moving parts need shared state and reload tests. Cart motion needs one physics
owner, bounded residency and saved-motion/support checks. Rope/cable use needs
an attachment/length/state contract. Return to these shared gameplay contracts
before adding behavior; the pack introduces no new actor or vehicle permission.

Headless density fixtures cover 1,000 mixed placements per pack, native ownership
and byte-exact reopen. They do not establish graphical frame rate, transparent
overdraw cost, dense-house navigation quality, total RAM/VRAM or 60 FPS headroom.
Return with a representative furnished-house route and matched sparse/cluttered
captures before making a whole-game performance claim. Generated-building
furnishing is outside this milestone; the rejected district layout is unchanged.

## Verification

- Homestead 01: 98 assertions, including the mixed-density fixture and fresh
  structure owners: `reports/checks/20261126T084217973148Z/run.json`.
- Homestead 02: 139 assertions, including 1,000 mixed placements, paid placement,
  no unpaid duplicate, byte-exact reopen, pre-pack save admission, icon identity,
  native lamp configuration, and real wall support on all four sides:
  `reports/checks/20261126T083525776071Z/run.json`.
- Homestead 03: 137 assertions covering paid placement, no unpaid duplicates,
  shared damage/salvage, icons, byte-exact reopen, pre-pack save admission,
  1,000 mixed placements and real wall support on all four sides:
  `reports/checks/20261126T085712674667Z/run.json`.
- Homestead 04: 111 assertions covering paid placement, no unpaid duplicates,
  shared damage/salvage, icons, byte-exact reopen, pre-pack save admission,
  1,000 mixed placements and real tool-board wall support on all four sides:
  `reports/checks/20261126T091105311460Z/run.json`.
- Expanded Homestead 04 catalog: universal drops/recollection pass 783 checks
  (`reports/checks/20261126T091251412951Z/run.json`), physical drops pass 126
  (`reports/checks/20261126T091337525004Z/run.json`), and actual-world rendered
  G/input checks pass 35 (`reports/checks/20261126T091431643291Z/run.json`).
- Expanded Homestead 03 catalog: universal drops/recollection pass 713 checks
  (`reports/checks/20261126T085806878619Z/run.json`), physical drops pass 116
  (`reports/checks/20261126T085904647712Z/run.json`), and the actual-world rendered
  G/input route passes 35 (`reports/checks/20261126T085946399426Z/run.json`).
- Universal item-drop catalog regression:
  `reports/checks/20261126T083609261132Z/run.json`.
- Physical item-drop regression: 106 assertions:
  `reports/checks/20261126T083752027205Z/run.json`.
- Actual-world rendered G/input regression: 35 assertions, startup with both
  packs, input/menu guards, original-size/physical drop options and recollection:
  `reports/checks/20261126T084058031606Z/run.json`. The headless attempt at
  `reports/checks/20261126T083953728795Z` passed startup but failed two active-drop
  assertions; preserve that scope rather than claiming a headless input pass.
- Initial full-world startup exposed an invalid light-source metadata getter;
  the corrected integration uses the native collection's `stats().asset_id`.
  Failed evidence: `reports/checks/20261126T083823339234Z/run.json`.
- An initial numeric-ID/icon lookup failure is retained in
  `reports/checks/20261126T083329268862Z`; JSON numeric IDs are now normalized to
  integers before matching inventory keys in both packs.

The shared test runner admits 2 MiB of headless reports or 16 MiB of rendered
reports. No world copy, save slot output, full export or isolated build is
allocated. Keep at most two ordinary ready contact sheets per pack, preserving
rejected evidence and receipt-owned archival rules. Asset/source provenance and
offline credits have their own freshness checks.

`tools/maintain_homestead_captures.py` runs before and after pack checks and the
required G/input driver. It keeps two ordinary ready runs per capture family,
covering each pack's preview and the input driver's two UI images. It cold-retains
only exact image names from completed matching temporary driver/output receipts.
Pins, incomplete processes,
other files and unowned captures are excluded. Existing verified chunk archives
preserve every byte before exact-file retirement; logs and run receipts stay
ready. Three ownership/pin regressions pass. No storage limit is raised.

Godot's headless editor import generated the new script identity sidecars:
`reports/checks/homestead_uid_import_20261126T084351486949Z/run.json`.
Homestead 03 identities were generated by the later import at
`reports/checks/homestead03_uid_import_20261126T090113095694Z/run.json`.
Homestead 04 identities were generated at
`reports/checks/homestead04_uid_import_20261126T091652930378Z/run.json`.

The input capture lifecycle cold-retained the older two menu images from
`reports/checks/20261126T084058031606Z` after the later input driver exited.
`homestead.archive.json` there retains exact filenames, hashes and verified
chunk reconstruction; run receipts/logs remain ready and two recent UI runs
remain loose. The archive preserves all image bytes under the existing storage
limits.

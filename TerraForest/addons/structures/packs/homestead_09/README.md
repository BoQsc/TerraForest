# Homestead 09 — Bedroom & Personal Effects

A separate ten-object furnishing pack in warm timber, dusty blue fabric,
cream linen and brass. Stable identity: `terraforest.homestead_09`,
version `1.0.0`.

| Object | Item | Placement |
| --- | ---: | --- |
| Chest of drawers | 800 | Floor; four closed drawers and brass pulls |
| Dressing table | 801 | Floor; open knee space and small drawers |
| Padded vanity stool | 802 | Floor; turned legs, tufting and soft cushion |
| Tabletop mirror | 803 | Supported surface; oval frame, pivots and stand |
| Three panel folding screen | 804 | Floor; three fixed angled fabric/timber panels |
| Open suitcase with clothes | 805 | Floor/surface; open lid, lining, packed clothes and straps |
| Folded blanket stack | 806 | Supported surface; layered fabric, stripes and fringe |
| Mechanical alarm clock | 807 | Supported surface; twin bells, dial marks and static hands |
| Hot water bottle | 808 | Supported surface; ribbed body, neck and stopper |
| Small jewellery box | 809 | Supported surface; open lined lid, rings and necklace |

Use **Objects → Homestead 09** or **Dev Bag → Homestead 09**. Carried versions
share right-click placement, R rotation, H grid/free placement and universal
G drop/recollection. Model keys are `packs/homestead_09/<object id>/v1`.
Costs, partial salvage and durability are in `pack.json`. All placements use
existing native collections, history, paging and structure persistence. No
per-garment, panel, clock-hand or jewellery ticking node, new save provider or
permanent per-part rigid body is introduced.

## Behavior boundary and return triggers

These are furnishings. Storage, movable drawers/lids/screen panels, sitting,
equipping packed clothes, live reflections, clock/time/alarm behavior and bottle
filling/heat are not implemented. The mirror uses a simple finish with authored
highlights; the clock hands and screen angles are static. Generated houses and
player saves are not refurnished.

Storage needs cross-collection identities, transfer/lock rules and nonempty-removal
protection. Moving parts need shared saved state and collision/interaction checks.
Seating needs actor/seat ownership; wearable contents need shared equipment and
visual/durability state without duplicate decorative/inventory quantities. Live
mirrors need their own bounded reflection experiment, sparse/dense timings and
fallback before admission. Clock behavior needs shared world time, bounded alarm
audio and saved state. The bottle needs shared capacity, volume/heat conservation
and native transfers. Return to these contracts with interaction/fresh-provider
reload evidence before adding behavior; furnishing admission is not closure.

## Sources and checks

Runtime meshes, embedded materials and icons are self-contained here.
`author.gd` retains new geometry and reuses original Homestead 02/04 mesh/tube
helpers and the Homestead 07 cushion helper. Exact source hashes are retained.

```text
python tools/run_godot_check.py homestead_09_pack --require "failures=0" -- --author-pack
python tools/run_godot_check.py homestead_09_pack --isolated-render --require "HOMESTEAD09_PREVIEW failures=0" -- --preview-only
python tools/run_godot_check.py homestead_09_pack --require "failures=0"
python tools/homestead_provenance.py --check
```

Godot generates script `.uid` identities on import. The shared runner admits
2 MiB of headless logs or 16 MiB for one bounded 1920×1080 contact sheet.
Receipt-owned retention keeps two ordinary ready runs per capture family and
cold-retains older verified images, including required G/input UI captures.
Logs, pins, unrelated files and player saves remain protected. No export,
source copy or new saved world is allocated. The 1,000-placement fixture covers
native ownership/persistence, not dense-bedroom graphical or navigation acceptance.
Preview/checks are linked from [pack status](../../../../docs/HOMESTEAD_PACKS.md).
See [asset terms](ASSET_LICENSE.md).

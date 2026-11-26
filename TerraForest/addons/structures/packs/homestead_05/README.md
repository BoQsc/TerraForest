# Homestead 05 — Kitchen & Pantry

A separate ten-object furnishing pack in cream enamel, faded teal, copper,
weathered timber and warm pantry colours. Stable pack identity:
`terraforest.homestead_05`, version `1.0.0`.

| Object | Item | Placement |
| --- | ---: | --- |
| Compact refrigerator | 760 | Floor; separate closed door shapes |
| Kettle | 761 | Supported surface; curved spout and handle |
| Cooking pot and lid | 762 | Supported surface; open pot and separate propped lid |
| Frying pan | 763 | Supported surface; shallow bowl and long handle |
| Cutting board and knife | 764 | Supported surface; one preparation cluster |
| Wall utensil rail | 765 | Wall; ladle, spatula and whisk |
| Wall plate rack | 766 | Wall; open timber frame and upright plates |
| Preserve jar cluster | 767 | Supported surface; three translucent jars with contents |
| Bread bin | 768 | Supported surface; rounded closed cover |
| Grain sack | 769 | Floor/surface; shaped cloth, open collar and grain |

Use **Objects → Homestead 05** or **Dev Bag → Homestead 05**. Carried versions
share right-click placement, R rotation, H grid/free placement and universal
G drop/recollection. Wall pieces use the existing authored support-point checks.
Model keys are `packs/homestead_05/<object id>/v1`; costs, partial salvage and
durability are in `pack.json`. All placements use existing native collections,
history, paging and structure persistence. No per-jar, grain or utensil ticking
node, new save provider or permanent per-part rigid body is introduced.

## Behavior boundary and return triggers

The refrigerator, cookware, food representations and containers are static
furnishings. Cooking, cooling, powered appliances, moving doors/lids, storage,
edible jar/grain contents and knife use are not implemented. Registering the
pack grants no weapon, food-consumption or appliance permissions. Existing
generated houses and player saves are not refurnished.

Cooking needs shared recipe/progress transactions, resource conservation and
reload checks. Refrigeration needs a shared power/cooling and persistence
contract. Storage needs cross-collection container identities and nonempty
removal protection. Edible contents need explicit native item/transfer and
consumption rules, avoiding duplicate decorative and inventory quantities.
Moving parts need shared saved state and collision/interaction checks. Return
to those contracts before adding behavior; furnishing admission is not closure
of these gameplay features.

## Sources and checks

Runtime meshes, embedded materials and icons are self-contained here.
`author.gd` retains the new geometry and reuses original Homestead 02 and 04
offline helpers. Their exact source hashes are retained in provenance.

```text
python tools/run_godot_check.py homestead_05_pack --require "failures=0" -- --author-pack
python tools/run_godot_check.py homestead_05_pack --isolated-render --require "HOMESTEAD05_PREVIEW failures=0" -- --preview-only
python tools/run_godot_check.py homestead_05_pack --require "failures=0"
python tools/homestead_provenance.py --check
```

Godot generates script `.uid` identities on import. The shared runner admits
2 MiB of headless logs or 16 MiB for one bounded 1920×1080 contact sheet.
Receipt-owned retention keeps two ordinary ready runs per capture family and
cold-retains older verified images, including required G/input UI captures.
Logs, pins, unrelated files and player saves remain protected. No export,
source copy or new saved world is allocated. The 1,000-placement fixture covers
native ownership and persistence, not dense-house frame rate or transparency
cost. Preview/checks are linked from [pack status](../../../../docs/HOMESTEAD_PACKS.md).
See [asset terms](ASSET_LICENSE.md).

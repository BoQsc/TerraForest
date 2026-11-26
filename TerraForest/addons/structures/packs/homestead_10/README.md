# Homestead 10 — Dining Room & Serving

A separate ten-object furnishing pack in warm oak, cream ceramics, muted green
fabric and brass. Stable identity: `terraforest.homestead_10`, version `1.0.0`.

| Object | Item | Placement |
| --- | ---: | --- |
| Round pedestal dining table | 810 | Floor; turned column and four splayed feet |
| Upholstered dining chair | 811 | Floor; timber frame and padded seat/back |
| Glass fronted china cabinet | 812 | Floor; transparent panes, shelves and dishes |
| Two tier serving trolley | 813 | Floor; timber trays, brass frame and fixed wheels |
| Teapot and teacup set | 814 | Supported surface; tray, hollow spout, teapot and two cups |
| Ceramic serving platter | 815 | Supported surface; oval dish and coloured rim |
| Cutlery tray | 816 | Supported surface; compartments, spoon, fork and knife |
| Woven bread basket | 817 | Supported surface; open weave, loaf and rolls |
| Fruit bowl | 818 | Supported surface; ceramic bowl, apples and pear |
| Folded tablecloth and napkins | 819 | Supported surface; layered linen and three napkins |

Use **Objects → Homestead 10** or **Dev Bag → Homestead 10**. Carried versions
share right-click placement, R rotation, H grid/free placement and universal
G drop/recollection. Model keys are `packs/homestead_10/<object id>/v1`.
Costs, partial salvage and durability are in `pack.json`. All placements use
existing native collections, history, paging and structure persistence. No
per-dish, food, wheel or cutlery ticking node, new save provider or permanent
per-part rigid body is introduced. The glass uses simple alpha transparency;
there is no live reflection camera or refraction effect.

## Behavior boundary and return triggers

These are furnishings. Seating, cabinet storage, moving doors, trolley motion,
pouring/drinking, edible bread/fruit, usable cutlery and cloth simulation are
not implemented. Dishes, food and folded linen are fixed parts of their parent
object. Generated houses and player saves are not refurnished.

Sitting needs shared actor/seat ownership. Storage needs cross-collection
identities, transfer/lock rules and nonempty-removal protection. Moving parts
need shared saved state and collision/interaction checks. Trolley motion needs
one physics owner, bounded residency and saved-motion/support checks. Serving
liquids needs shared capacity/volume/heat conservation and native transfers.
Edible contents need item/consumption rules avoiding duplicate decorative and
inventory quantities. Usable cutlery needs explicit interaction permissions;
cloth simulation needs its own bounded effects/state contract. Return with
interaction and fresh-provider reload evidence before adding behavior.

## Sources and checks

Runtime meshes, embedded materials and icons are self-contained here.
`author.gd` retains new geometry and reuses original Homestead 02/04 mesh/tube
helpers and the Homestead 07 cushion helper. Exact source hashes are retained.

```text
python tools/run_godot_check.py homestead_10_pack --require "failures=0" -- --author-pack
python tools/run_godot_check.py homestead_10_pack --isolated-render --require "HOMESTEAD10_PREVIEW failures=0" -- --preview-only
python tools/run_godot_check.py homestead_10_pack --require "failures=0"
python tools/homestead_provenance.py --check
```

Godot generates script `.uid` identities on import. The shared runner admits
2 MiB of headless logs or 16 MiB for one bounded 1920×1080 contact sheet.
Receipt-owned retention keeps two ordinary ready runs per capture family and
cold-retains older verified images, including required G/input UI captures.
Logs, pins, unrelated files and player saves remain protected. No export,
source copy or new saved world is allocated. The 1,000-placement fixture covers
native ownership/persistence, not dense-room graphical or navigation acceptance.
Transparent cabinet cost needs matched sparse/dense furnished-house captures
before making a performance claim. Preview/checks are linked from
[pack status](../../../../docs/HOMESTEAD_PACKS.md). See [asset terms](ASSET_LICENSE.md).

# Homestead 08 — Entryway & Porch

A separate ten-object furnishing pack in weathered timber, sage green metal,
woven fibre and terracotta. Stable identity: `terraforest.homestead_08`,
version `1.0.0`.

| Object | Item | Placement |
| --- | ---: | --- |
| Narrow hall console | 790 | Floor; shallow drawers and open lower shelf |
| Entryway bench | 791 | Floor; timber slats, backrest and metal frame |
| Shoe rack with shoes | 792 | Floor; three slatted levels and eight shoes |
| Umbrella stand with umbrellas | 793 | Floor; hollow stand, folded fabric and hooks |
| Woven doormat | 794 | Floor; coir weave and border |
| Wall key rack | 795 | Wall; five hooks, rings and three keys |
| Wall mounted mailbox | 796 | Wall; closed lid/door, slot, label frame and keyhole |
| Pair of muddy boots | 797 | Floor; shaped feet, open collars, tread and mud |
| Terracotta planter with foliage | 798 | Floor/surface; hollow pot, soil and opaque leaves |
| Metal watering can | 799 | Floor/surface; hollow vessel, spout, rose and handles |

Use **Objects → Homestead 08** or **Dev Bag → Homestead 08**. Carried versions
share right-click placement, R rotation, H grid/free placement and universal
G drop/recollection. Both wall pieces use authored support-point checks.
Model keys are `packs/homestead_08/<object id>/v1`. Costs, partial salvage and
durability are in `pack.json`. All placements use existing native collections,
history, paging and structure persistence. No per-shoe, leaf, key or umbrella
ticking node, new save provider or permanent per-part rigid body is introduced.
Foliage is opaque static geometry, without transparent cards or wind simulation.

## Behavior boundary and return triggers

These are furnishings. Drawer/mailbox storage, mail delivery, key use, equipping
the decorative shoes/boots, umbrella opening, seating, plant growth and watering
are not implemented. Generated houses and player saves are not refurnished.

Storage needs cross-collection container identities, transfer/lock rules and
nonempty-removal protection. Mail needs shared content/delivery ownership and
persistence. Keys need explicit lock identities and interaction permissions;
decorative geometry does not grant usable inventory keys. Wearable footwear needs
shared equipment/visual/durability state. Opening umbrellas needs shared saved
state and collision checks; seating needs actor/seat ownership. Plant care and
watering need shared capacity, resource conservation, growth/time and native
transfer rules. Return to those contracts with interaction and fresh-provider
reload evidence before adding behavior. Furnishing admission does not close
these gameplay features.

## Sources and checks

Runtime meshes, embedded materials and icons are self-contained here.
`author.gd` retains the new geometry and reuses original Homestead 02 and 04
offline helpers. Their exact source hashes are retained in provenance.

```text
python tools/run_godot_check.py homestead_08_pack --require "failures=0" -- --author-pack
python tools/run_godot_check.py homestead_08_pack --isolated-render --require "HOMESTEAD08_PREVIEW failures=0" -- --preview-only
python tools/run_godot_check.py homestead_08_pack --require "failures=0"
python tools/homestead_provenance.py --check
```

Godot generates script `.uid` identities on import. The shared runner admits
2 MiB of headless logs or 16 MiB for one bounded 1920×1080 contact sheet.
Receipt-owned retention keeps two ordinary ready runs per capture family and
cold-retains older verified images, including required G/input UI captures.
Logs, pins, unrelated files and player saves remain protected. No export,
source copy or new saved world is allocated. The 1,000-placement fixture covers
native ownership/persistence, not dense-house graphical or navigation acceptance.
Preview/checks are linked from [pack status](../../../../docs/HOMESTEAD_PACKS.md).
See [asset terms](ASSET_LICENSE.md).

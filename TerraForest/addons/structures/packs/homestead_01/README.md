# Homestead 01

An original, coordinated household object pack: weathered timber, faded teal
upholstery and cabinet fronts, cream enamel, dark iron and brass hardware.
Pack identity: `terraforest.homestead_01`, version `1.0.0`.

| Object | Inventory ID | Model identity |
| --- | ---: | --- |
| Bed | 720 | `packs/homestead_01/bed/v1` |
| Nightstand | 721 | `packs/homestead_01/nightstand/v1` |
| Wardrobe | 722 | `packs/homestead_01/wardrobe/v1` |
| Kitchen counter | 723 | `packs/homestead_01/counter/v1` |
| Cupboard | 724 | `packs/homestead_01/cupboard/v1` |
| Sink | 725 | `packs/homestead_01/sink/v1` |
| Iron stove | 726 | `packs/homestead_01/stove/v1` |
| Sofa | 727 | `packs/homestead_01/sofa/v1` |
| Book cluster | 728 | `packs/homestead_01/books/v1` |
| Enamel mug | 729 | `packs/homestead_01/mug/v1` |

## In game

Open the developer **Objects** workspace and select **Homestead 01** in the pack
filter. The **Dev Bag → Homestead 01** category grants carried versions; equip
one on the gameplay belt, right-click to place, R to rotate and H for grid/free
placement. G uses the universal drop/recollection path, including persistence.
Small props can be placed on supported building/model surfaces.

Recipes and partial salvage are in `pack.json`, together with damage profiles.
Each model uses a shared native collection, compound collision and ordinary
structure saves/history/paging. The pack adds no ticking node per placement,
new save provider or permanent rigid body per decorative object. Old worlds
retain their furnishings; the pack is available for authoring without rewriting
generated buildings or player saves.

## Scope and follow-up

All ten objects are furnishings in this first release. Wardrobe, nightstand and
cupboard have authored closed fronts, but no storage interface or animated parts.
Bed sleeping, sofa sitting, stove cooking/fire, sink water exchange and readable
books are not implemented. Each requires shared gameplay behavior, saved state
and targeted verification before it can be advertised as functional.

Return to storage after adding a shared container identity/ownership mapping
across model collections; the present chest adapter owns one collection's IDs.
Closure needs independent contents for equal local IDs, protected nonempty
removal, transfer/lock behavior and fresh-provider reload. Other interactions
need their corresponding gameplay contract before extending these models.

The ten-type, 1,000-placement headless density fixture measures native admission
and persistence only. It does not establish gameplay FPS, light/shadow cost,
navigation acceptance or dense-house performance. User visual acceptance remains
separate from the rendered engineering review.

## Editable sources and verification

`author.gd` retains geometry, material palette, texture seed and collision boxes.
`pack.json` owns the roster, costs and durability. Baked meshes and the icon atlas
are committed, so gameplay does not regenerate models or start live icon viewports.

Run from the repository project directory with the existing Python and Godot:

```text
python tools/run_godot_check.py homestead_pack --require "failures=0" -- --author-pack
python tools/run_godot_check.py homestead_pack --isolated-render --require "failures=0" -- --bake-icons
python tools/run_godot_check.py homestead_pack --require "failures=0"
```

Use an editor import after adding scripts to generate Godot `.uid` identities.
The shared runner performs storage admission and records commands, hashes and
completion receipts. No source copy, export or saved world is allocated. The
rendered driver emits one bounded 1920×1080 contact sheet in its receipt directory.
The runner uses `tools/maintain_homestead_captures.py` before and after checks to
keep at most two ordinary ready contact sheets and cold-retain earlier exact
receipt-owned captures with the verified artifact lifecycle. Retain logs/receipts
and never remove unrelated capture or player-save data.

See [asset terms and provenance](ASSET_LICENSE.md).

# Homestead 04 — Workshop & Repairs

A separate ten-object furnishing pack for garages, basements and sheds:
weathered timber, dull iron, faded teal paint and rust-red accents. Stable pack
identity: `terraforest.homestead_04`, version `1.0.0`.

| Object | Item | Placement |
| --- | ---: | --- |
| Heavy workbench | 750 | Floor; open frame, lower shelf and closed drawer fronts |
| Bench vise | 751 | Supported surface; jaws, screw and handle |
| Wall tool board | 752 | Wall; four decorative hand tools |
| Metal toolbox | 753 | Supported surface; closed lid and latches |
| Sawhorse | 754 | Floor; angled supports |
| Timber plank stack | 755 | Floor/surface; grouped boards |
| Paint tin and brush | 756 | Supported surface; open tin and brush |
| Coiled rope | 757 | Floor/surface; continuous spiral and loose end |
| Cable spool | 758 | Floor/surface; flanges, winding and loose cable |
| Small handcart | 759 | Floor; open bed, spoked wheels and handles |

Use **Objects → Homestead 04** or **Dev Bag → Homestead 04**. Carried versions
share right-click placement, R rotation, H grid/free placement and universal
G dropping/recollection. The board uses existing authored wall-support checks.
Model keys are `packs/homestead_04/<object id>/v1`; recipes, partial salvage
and durability are in `pack.json`. Native collections own all placements;
there is no per-part ticking node or permanent per-piece physics body.

## Behavior boundary and return triggers

The workbench, vise, tools, toolbox, timber, paint, rope, cable and cart are
static furnishings. Crafting, usable hand tools, moving jaws/lids, storage,
paint application, rope/cable attachment and cart motion are not implemented.
Registering the pack does not grant vehicle, crafting or actor permissions.
Existing generated layouts and player saves are not refurnished.

Crafting needs a shared recipe/progress and native transaction contract, with
resource conservation and save/reload checks. Toolbox storage needs shared
cross-collection container ownership (see Homestead 01). Moving parts require
shared state and reload/interaction tests. Cart motion needs one physics owner,
bounded residency, saved motion and support/collision checks before becoming
interactive. Rope/cable use needs an attachment/length/state contract. Those
requirements are follow-up gameplay work rather than completed features.

## Sources and checks

Runtime meshes, embedded materials and icons are self-contained here.
`author.gd` retains the new geometry and reuses the repository's original
Homestead 02 offline mesh helpers; the exact helper hash is in provenance.

```text
python tools/run_godot_check.py homestead_04_pack --require "failures=0" -- --author-pack
python tools/run_godot_check.py homestead_04_pack --isolated-render --require "HOMESTEAD04_PREVIEW failures=0" -- --preview-only
python tools/run_godot_check.py homestead_04_pack --require "failures=0"
python tools/homestead_provenance.py --check
```

Godot generates script `.uid` identities during editor import. The shared runner
admits 2 MiB of headless logs or 16 MiB for a bounded 1920×1080 contact sheet.
Receipt-owned capture retention keeps two ordinary ready runs per family and
cold-retains older verified images. It also covers the required G-input UI
captures without retiring logs, pins, unrelated files or player saves.
No export, source copy or new saved world is allocated. The 1,000-placement
fixture is native ownership/persistence evidence, not a dense-house FPS claim.
Preview and checks are linked from [pack status](../../../../docs/HOMESTEAD_PACKS.md).
See [asset terms](ASSET_LICENSE.md).

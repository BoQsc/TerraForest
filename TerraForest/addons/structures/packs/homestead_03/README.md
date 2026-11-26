# Homestead 03 — Washroom & Utility

A separate ten-object furnishing pack in cream enamel, dull zinc, faded teal,
woven linen and weathered timber. Pack identity: `terraforest.homestead_03`,
version `1.0.0`.

| Object | Item | Placement |
| --- | ---: | --- |
| Enamel bathtub | 740 | Floor; open basin, rolled rim and feet |
| Toilet and cistern | 741 | Floor; open bowl and timber seat |
| Wall mirror | 742 | Wall; inexpensive silver finish |
| Towel rail | 743 | Wall; folded-over hanging towel |
| Folded towels | 744 | Supported surface; three-towel cluster |
| Soap dish | 745 | Supported surface; dish and soap together |
| Paper holder | 746 | Wall; roll and hanging sheet |
| Laundry tub | 747 | Floor/surface; hollow galvanized tub |
| Washboard | 748 | Floor/surface; authored 12-degree lean |
| Broom and dustpan | 749 | Floor; one decorative cluster |

Use **Objects → Homestead 03** or **Dev Bag → Homestead 03**. Carried objects
share right-click placement, R rotation, H grid/free placement and universal
G dropping/recollection. Wall objects use the existing authored support-point
checks. Model keys are `packs/homestead_03/<object id>/v1`; recipes, salvage and
durability are in `pack.json`. No new ticking object, save provider, permanent
per-item rigid body or native build is needed.

## Behavior boundary

These are furnishings. Plumbing, toilet use, washing, soap/paper consumption,
water storage and cleaning are not implemented. The mirror has a simple silver
material and authored highlights; it does not render live room reflections.
No existing player save or generated house is refurnished by registering the
pack. A new pack does not establish dense-house frame-rate performance.

Return to water behavior after defining shared capacity, volume conservation,
inventory transfer and fresh-provider persistence for fixtures. Return to
washing/cleaning after their gameplay contracts exist. Live mirrors need a
separate bounded reflection experiment, sparse/dense timing comparisons and
an explicit fallback before becoming a default effect. Visual acceptance
remains with the user after reviewing the rendered sheet.

## Sources and verification

The runtime meshes, embedded materials and icon atlas are self-contained here.
`author.gd` retains the new geometry and reuses the repository's original
Homestead 02 offline mesh helpers. The exact helper hash is retained in the
pack's provenance; no external asset source is introduced.

```text
python tools/run_godot_check.py homestead_03_pack --require "failures=0" -- --author-pack
python tools/run_godot_check.py homestead_03_pack --isolated-render --require "HOMESTEAD03_PREVIEW failures=0" -- --preview-only
python tools/run_godot_check.py homestead_03_pack --require "failures=0"
python tools/homestead_provenance.py --check
```

The shared runner admits 2 MiB for headless logs or 16 MiB for one bounded
1920×1080 contact sheet. Receipt-owned retention keeps two ordinary ready
previews per pack and cold-retains older verified images; logs, pins, rejected
evidence and player saves remain protected. No export, source copy or new
saved world is allocated. Godot generates resource `.uid` identities on import.
Checks and preview are linked from [pack status](../../../../docs/HOMESTEAD_PACKS.md).
See [asset terms](ASSET_LICENSE.md).

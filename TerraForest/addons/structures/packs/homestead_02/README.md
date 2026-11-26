# Homestead 02 — Lived-in Details

A separate ten-object household pack with woven linen, faded teal, weathered
timber, brass, cream ceramic and amber glass. Stable pack identity:
`terraforest.homestead_02`, version `1.0.0`.

| Object | Item | Placement |
| --- | ---: | --- |
| Woven rug | 730 | Floor |
| Curtains and rail | 731 | Wall; two rail mounting points |
| Framed landscape | 732 | Wall |
| Wall clock | 733 | Wall |
| Coat rack | 734 | Floor |
| Laundry basket | 735 | Supported surface |
| Wooden crate | 736 | Supported surface |
| Amber bottle | 737 | Supported surface |
| Plate and bowl set | 738 | Supported surface |
| Table lamp | 739 | Supported surface; resident warm light |

Model keys use `packs/homestead_02/<object id>/v1`; object IDs, costs, salvage
and damage profiles are in `pack.json`. Models, materials, icons and editable
authoring sources stay inside this directory.

Use **Objects → Homestead 02** or **Dev Bag → Homestead 02**. Carried versions
use right-click placement, R rotation, H grid/free placement and universal G
drop/recollection. Wall pieces face the aimed wall; their actual mounting
points must meet solid support. The curtain rail can span a window opening.
The Objects workspace also supports numeric transforms in development mode.

The lamp shares the existing four-light native resident pool with other house
lights, including its focus, residency and shadow budget. Its bulb is emissive;
it adds no ticking node per placement. Like the existing house lights it has
no individual on/off saved state. Glass uses an actual transparent material;
fabric is visible from both sides. The rug has a thin collision surface.

The clock face is static; cloth does not simulate. Basket/crate storage, readable
picture/book content and dish/bottle consumption are not implemented. Return to
container behavior after shared cross-collection identity ownership is available
(see Homestead 01). Closure requires equal-local-ID isolation, nonempty-removal
protection, transfers and fresh-provider reload. Running clock hands require a
shared world-time contract and reload checks before adding saved behavior.

## Authoring and checks

```text
python tools/run_godot_check.py homestead_02_pack --require "failures=0" -- --author-pack
python tools/run_godot_check.py homestead_02_pack --isolated-render --require "HOMESTEAD02_PREVIEW failures=0" -- --preview-only
python tools/run_godot_check.py homestead_02_pack --require "failures=0"
python tools/homestead_provenance.py --check
```

Godot generates `.uid` sidecars during editor import. The shared runner declares
2 MiB for headless logs or 16 MiB for the bounded contact sheet and performs
normal storage admission. Tests use the current checkout without a saved world,
export, worktree or source copy. Captures remain with their `run.json` receipt;
keep at most two ordinary ready captures per pack. The runner invokes
`tools/maintain_homestead_captures.py` before and after checks to cold-retain older
exact receipt-owned images with the verified repository artifact archive.
Retain failed logs and rejected comparisons. No archival or test work runs
inside gameplay measurements.

The density fixture verifies 1,000 mixed native placements and persistence;
it is not a graphical frame-rate or total memory qualification. Pack preview
and evidence are linked from [the pack status](../../../../docs/HOMESTEAD_PACKS.md).
See [asset terms and provenance](ASSET_LICENSE.md).

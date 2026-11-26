# Homestead 06 — Study & Communications

A separate ten-object furnishing pack in dark timber, cream metal, muted teal,
black plastic and brown leather. Stable pack identity:
`terraforest.homestead_06`, version `1.0.0`.

| Object | Item | Placement |
| --- | ---: | --- |
| Writing desk | 770 | Floor; open knee space and closed drawers |
| Desk chair | 771 | Floor; upholstered seat/back, armrests and caster base |
| Typewriter | 772 | Supported surface; keys, carriage and paper |
| Table radio | 773 | Supported surface; grille, knobs, tuner and antenna |
| Rotary telephone | 774 | Supported surface; dial, handset and coiled cord |
| Desk fan | 775 | Supported surface; wire guard and three static blades |
| Document bundle | 776 | Supported surface; layered papers, folder and twine |
| Wall calendar | 777 | Wall; original November 2026 print |
| Briefcase | 778 | Floor/surface; leather grain, handle and clasps |
| Wastepaper basket | 779 | Floor; open wire sides and crumpled paper |

Use **Objects → Homestead 06** or **Dev Bag → Homestead 06**. Carried versions
share right-click placement, R rotation, H grid/free placement and universal
G drop/recollection. The calendar uses the existing authored wall-support checks.
Model keys are `packs/homestead_06/<object id>/v1`; costs, partial salvage and
durability are in `pack.json`. All placements use existing native collections,
history, paging and structure persistence. No per-key, fan-blade or wire ticking
node, new save provider or permanent per-part rigid body is introduced.

## Behavior boundary and return triggers

These are static furnishings. Radio audio/tuning, telephone calls, fan rotation,
typing, readable documents, live calendar/time changes, sitting and container
storage are not implemented. Existing generated houses and player saves are not
refurnished. The calendar's highlighted date is authored artwork.

Radio behavior needs a shared bounded audio/power contract and saved tuning/state.
Calls need an explicit communication/interaction contract. Fan motion needs shared
appliance state, a bounded animation/effect budget and reload checks. Readable or
editable content needs shared content identities and interaction permissions;
calendar updates need shared world time and reload evidence. Sitting needs the
shared actor/seat ownership contract. Storage needs cross-collection container
identities and nonempty-removal protection. Return to these contracts before
adding behavior; each requires its own interaction and fresh-provider reload
checks. Furnishing admission does not close these gameplay features.

## Sources and checks

Runtime meshes, embedded materials/print artwork and icons are self-contained
here. `author.gd` retains the new geometry and reuses original Homestead 02 and
04 offline helpers. Their exact source hashes are retained in provenance.

```text
python tools/run_godot_check.py homestead_06_pack --require "failures=0" -- --author-pack
python tools/run_godot_check.py homestead_06_pack --isolated-render --require "HOMESTEAD06_PREVIEW failures=0" -- --preview-only
python tools/run_godot_check.py homestead_06_pack --require "failures=0"
python tools/homestead_provenance.py --check
```

Godot generates script `.uid` identities on import. The shared runner admits
2 MiB of headless logs or 16 MiB for one bounded 1920×1080 contact sheet.
Receipt-owned retention keeps two ordinary ready runs per capture family and
cold-retains older verified images, including required G/input UI captures.
Logs, pins, unrelated files and player saves remain protected. No export,
source copy or new saved world is allocated. The 1,000-placement fixture covers
native ownership and persistence, not dense-house frame rate or thin-wire cost.
Preview/checks are linked from [pack status](../../../../docs/HOMESTEAD_PACKS.md).
See [asset terms](ASSET_LICENSE.md).

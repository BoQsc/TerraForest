# Homestead 07 — Living Room & Leisure

A separate ten-object furnishing pack in warm timber, muted teal upholstery,
linen, aged stone and brass. Stable identity: `terraforest.homestead_07`,
version `1.0.0`.

| Object | Item | Placement |
| --- | ---: | --- |
| Upholstered armchair | 780 | Floor; rounded cushions, tufting and timber legs |
| Low coffee table | 781 | Floor; open legs and lower slatted shelf |
| Tall bookcase with books | 782 | Floor; open shelves and varied book spines |
| Sideboard cabinet | 783 | Floor; closed doors/drawers with brass handles |
| Record player | 784 | Supported surface; open lid, grooved record and tonearm |
| Vinyl record crate | 785 | Floor/surface; open slats and original sleeve/label art |
| Chessboard with pieces | 786 | Supported surface; 64 squares and 32 shaped pieces |
| Newspaper stack | 787 | Supported surface; layered paper and original print |
| Standing floor lamp | 788 | Floor; linen shade and brass stand |
| Fireplace surround with logs | 789 | Floor, against wall; stone arch and unlit logs |

Use **Objects → Homestead 07** or **Dev Bag → Homestead 07**. Carried versions
share right-click placement, R rotation, H grid/free placement and universal
G drop/recollection. Model keys are `packs/homestead_07/<object id>/v1`.
Costs, partial salvage and durability are in `pack.json`. All placements use
existing native collections, history, paging and structure persistence. No
per-book, chess-piece or record ticking node, new save provider or permanent
per-part rigid body is introduced. The lamp joins the existing four-slot native
resident-light pool; it does not allocate a light per placed copy.

## Behavior boundary and return triggers

These are furnishings. Seating, cabinet/record storage, music playback, movable
tonearm/lid, playable chess, readable newspapers/books and active fire/heat/smoke
are not implemented. The fireplace contains unlit decorative logs. The lamp
uses existing always-on resident lighting without independent switch state.
Generated houses and player saves are not refurnished.

Sitting needs shared actor/seat ownership. Storage needs cross-collection
container identities, transfer/lock rules and nonempty-removal protection.
Music needs shared bounded audio/playback state and content with suitable
provenance. Movable parts need shared saved state and collision/interaction
checks. Chess needs a shared board/piece transaction and interaction contract.
Reading needs explicit content identities and permissions. Fire needs shared
fuel/conservation, heat/interaction rules and bounded effects. Return to those
contracts with interaction and fresh-provider reload evidence before adding
behavior. Furnishing admission does not close these gameplay features.

## Sources and checks

Runtime meshes, embedded materials/artwork and icons are self-contained here.
`author.gd` retains new geometry and reuses original Homestead 02 and 04 offline
helpers. Their exact source hashes are retained in provenance.

```text
python tools/run_godot_check.py homestead_07_pack --require "failures=0" -- --author-pack
python tools/run_godot_check.py homestead_07_pack --isolated-render --require "HOMESTEAD07_PREVIEW failures=0" -- --preview-only
python tools/run_godot_check.py homestead_07_pack --require "failures=0"
python tools/homestead_provenance.py --check
```

Godot generates script `.uid` identities on import. The shared runner admits
2 MiB of headless logs or 16 MiB for one bounded 1920×1080 contact sheet.
Receipt-owned retention keeps two ordinary ready runs per capture family and
cold-retains older verified images, including required G/input UI captures.
Logs, pins, unrelated files and player saves remain protected. No export,
source copy or new saved world is allocated. The 1,000-placement fixture covers
native ownership/persistence, not dense-house graphical performance or lighting
acceptance. Preview/checks are linked from [pack status](../../../../docs/HOMESTEAD_PACKS.md).
See [asset terms](ASSET_LICENSE.md).

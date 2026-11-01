# Woven woodland clothing pack

Three original CC0 garments fitted to TerraForest's existing R11 player:

| Item | Slot | Plant-fibre recipe | Triangles |
| --- | --- | --- | --- |
| 301 Woven hood | Head | 2 | 1,236 |
| 302 Woven vest | Body | 4 | 4,236 |
| 303 Woven footwraps | Feet | 3 | 2,368 |

Craft them in Backpack, then drag each item to its matching Character slot.
Drag it back to the backpack to remove it. Existing item IDs, recipes and binary
save formats are preserved. These are cosmetic wearables; no armor, warmth or
movement bonus is added. The default shirt and trousers remain underneath.

The hood hides the short hair; the vest replaces the default field vest and its
carry harness; footwraps supply footwear. Empty equipment now shows the minimal
starter: plain shirt and trousers, bare feet, no outer gear. Removing garments
returns to that starter look. First person hides the hood. The two body garments use
the existing player body render layer; no animation owner or per-frame wardrobe
scan is added. The portrait requests a frame only when its outfit changes.

## Files and reuse

`301/302/303.res` are pre-baked Godot ArrayMesh resources with embedded materials
and ten named skin influences. `../clothing.gd` binds these to the existing R11
Skeleton3D using named inverse rest transforms. The resources are shared between
instances. The meshes total 7,840 triangles and nine material surfaces.

The matching GLBs are standalone **unrigged** garments in metres, Y up, facing +Z,
at their character rest positions. They contain no body, skeleton or animations;
rig them to a different character when reusing outside TerraForest. The `.res`
bone palette is documented in `manifest.json` and generated independently of the
character files. Keep the skin indices and palette together when editing it.

Editable source: `tools/author_woven_clothes.gd` (0BSD). Rebuild from the project:

```text
godot --headless --path . --script res://tools/author_woven_clothes.gd
godot --headless --path . --script res://tools/ensure_item_icons.gd
python tools/check_woven_clothes.py
```

The authoring tool regenerates all six assets and the hash manifest. The icon
freshness tool bakes actual garment silhouettes and matching ground-item models.
No authoring geometry runs during gameplay. See [ASSET_LICENSE.md](ASSET_LICENSE.md)
for the dedication and exact original/derivative scope.

## Verification boundary

The source review exercises paid crafting, legal/wrong/stale equipment drags,
both presentations, removal, binary storage restoration, first/third-person
visibility and idle portrait rendering. Front/side/back renders cover idle, walk,
run, crouch, pickaxe swing and punch samples. This is sampled animation fit, not
proof of all animation frames or arbitrary body proportions. The inherited
trousers' knee clipping in deep crouch is tracked separately with a base-outfit
comparison in `issues/woven-clothes/README.md`. The trader's woven appearance is
approved. Both packs are installed and package-verified; exact evidence is in
`issues/woven-clothes/package-evidence.json`. Broader animation and frame pacing
acceptance remain separate from these scoped checks.

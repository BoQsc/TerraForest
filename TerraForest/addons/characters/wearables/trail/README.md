# Trail clothing pack

The second original CC0 clothing set has a broad-brimmed blue hat, rust-colored
belted jerkin with an asymmetric pouch, and tall cuffed boots with short laces.

| Item | Slot | Plant fibre | Triangles |
| --- | --- | --- | --- |
| 304 Trail hat | Head | 3 | 1,440 |
| 305 Trail jerkin | Body | 6 | 3,964 |
| 306 Trail boots | Feet | 5 | 2,712 |

Craft in Backpack and drag to Character's Head, Body or Feet slot. The two packs
can be mixed by slot; dragging a full item onto an occupied matching slot swaps
the previous item back into the backpack. Clothing changes appearance only.
The trader uses the original woven set as their default role outfit; the player
can still craft and wear either set. Trader stock and save schemas are unchanged.

The trail hat retains the existing short hairstyle. First person hides headwear.
The jerkin replaces the default vest/harness, and tall boots replace base boots;
the existing shirt and trousers remain. No per-frame inventory scans or runtime
geometry generation are added. The inherited deep-crouch trouser defect remains.

## Reuse and authoring

The three `.res` files are pre-baked skinned Godot meshes with a ten-name palette
for the R11 rig, using `../clothing.gd`. The three GLBs are **unrigged** garments,
metres, Y up, facing +Z, in their fitted rest positions. No inherited body or
skeleton is included. Other character proportions require refitting and rigging.

```text
godot --headless --path . --script res://tools/author_trail_clothes.gd
godot --headless --path . --script res://tools/ensure_item_icons.gd
python tools/check_woven_clothes.py --trail
python tools/check_woven_clothes.py --trail --world
```

The original 0BSD generator inherits the primitive helpers in
`tools/author_woven_clothes.gd`. Both are editable source. `manifest.json` records
exact source and output hashes; [ASSET_LICENSE.md](ASSET_LICENSE.md) identifies
the CC0 assets and derivative scope. Sampled fit and real inventory/world evidence
are recorded in `issues/woven-clothes/README.md`; sampling is not a guarantee of
every animation frame. New trail-set visual approval remains pending.

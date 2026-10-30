# Trader and civic buildings — R1 review

Five new native block prefabs, with one trader using the retained current Human
R11 player model. Launch from TerraForest:

```text
python tools/review_modular_buildings.py --civic --persistent-review
```

Choose a building and Exterior, Rear, Inside, cutaway or Basement. Walk starts at
the approach: WASD/mouse, Shift to run, Space to jump, E for doors or the trader,
Escape returns to the review menu. Right-drag and wheel orbit the static views.
Doors also has a review-only open-all control. There is no trading from an orbit
camera: the player must be within three metres with clear sight to the NPC.

| Prefab | Plan | Basement clear area |
| --- | --- | --- |
| Trader T1 | 13 × 17 m house, covered arrival, stockroom and sales counter | None |
| Town hall T1 | 25 × 21 m, two storeys, portico and council chamber | 99 m² |
| Church C1 | 13 × 29 m nave, vestry and entrance tower | 99 m² |
| School S2 | 29 × 13 m two-storey teaching wing plus library | 81 m² |
| Warehouse W1 | 27 × 29 m, three gables, two loading bays and office | 99 m² |

Basement clear areas describe the interior rectangle before stairs/furniture.
The review ground has an opening for each basement; it is a fixture, not proof
of natural-terrain integration. Each `.tres` includes its excavation envelope.

## Trading

The one stationary, unarmed trader buys and sells eight existing commodities:
brick, wood, concrete, metal, stone, iron ore, copper ore and dry twigs. Buy/sell
prices differ; both the merchant's coins and stock are finite. The review player
starts with 300 coins, 25 stone and 20 twigs. Quantity is 1–999 per transaction.
Native `exchange_with` commits goods and payment together, rejects stale views
and prevents loss on insufficient stock, coins or inventory space. Equipment and
water are excluded from commodity exchange so wear/fill metadata cannot be lost.
Stock is never refreshed by closing the panel or switching buildings.

`--persistent-review` uses only `user://civic_trader_review_v1.tfworld`. F5 or Save
trade publishes both native inventories in one checksummed, leased, atomic archive.
Opening restores them; a corrupt archive disables saving to preserve the file.
Without this flag, the review is temporary. Existing gameplay saves are untouched.
The reusable merchant adapter provides a production persistence registration hook;
the main world does not yet place this review house or spawn its trader.

## Provenance and limits

New authoring/controller/test code is 0BSD. Original baked civic cell arrangements
and metadata are CC0-1.0; see `provenance.json`. They reference existing native
parts and furniture rather than importing external assets. The exact retained
player model and existing animations/materials keep their existing notices and
the open GAP-002 provenance qualification. No asset is relicensed by this review.

These are **review candidates**, not accepted world locations. Existing approved
houses, production recipes and saved buildings remain unchanged. See the
[visual issue and evidence](../../issues/civic-buildings/README.md) and
[shape/material expansion assessment](../../docs/BUILDING_EXPANSION_REVIEW.md).
World placement, terrain fitting, merchant activation/persistence in a generated
location and populated-world performance follow design approval. This review
does not claim an accepted generated world or an equipment/quest economy.

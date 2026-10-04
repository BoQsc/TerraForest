# Player inventory and construction

Default world launches remain the free editor. `Play Gameplay Construction.cmd`
selects a separate `gameplay_construction` save slot and passes
`--gameplay-construction`. The HUD identifies the active construction mode.

Gameplay construction charges one unit per occupied prefab cell or individual
block: material IDs 0–3 map to inventory items 101–104 (brick, wood, concrete,
metal). All shapes currently have the same one-unit cost. Prefab totals are
cached in native code when the asset is configured; fetching costs is constant
work even for large prefabs. Removal gives no refund. Occupied individual cells
must be cleared before replacement. Construction undo/redo and free material
supply spawning are disabled in this mode. Editor behavior is unchanged.

This is the construction economy connection, not a complete survival mode:
terrain tools, roads, static model placement and vehicle authoring are still
editor features without material recipes. New gameplay inventories start with
tools and 64 units of each construction material. This is the default for a
missing loadout section, not a refill: saved inventories replace it exactly,
including depleted stocks and existing editor loadouts. Further supplies must
currently be prepared in the editor; mining-to-inventory conversion is unfinished. The
mode is selected at launch, not stored in the world file or enforced by a
multiplayer authority. Opening the gameplay slot in editor mode allows editing.

`NativePlayerInventory.consume_items(costs, expected_revision)` accepts 1–32
item/count pairs and stages deductions across the fixed 32 inventory slots.
Duplicate item rows are cumulative. Failure preserves both slots and revision;
success advances revision once. `can_afford` performs the same validation
without mutation. Neither method scans world content.

`construction_inventory.gd` coordinates synchronous main-thread native edits.
It debits before placement so successful building change signals observe the
paid inventory. Native placement rejection does not alter blocks; the
coordinator then restores the previous slots with the debit revision as a
guard. Rollback advances revision rather than making stale commands valid
again. No await occurs in this transaction. Reentrant construction is rejected;
a conflicting inventory mutation during rejected placement is reported rather
than overwritten. This is not a distributed transaction protocol.

Targeted checks: `tests/player_inventory.gd` and
`tests/construction_inventory.gd` and `tests/gameplay_loadout.gd` (headless). These verify inventory correctness,
native prefab accounting and placement rollback, not rendering performance.

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

This is not a complete survival mode. Gameplay terrain tools excavate only;
free terrain filling, grading and legacy terrain cubes are editor tools.
Static model placement and vehicle authoring still lack material recipes.
New gameplay inventories start with
tools and 64 units of each construction material. This is the default for a
missing loadout section, not a refill: saved inventories replace it exactly,
including depleted stocks and existing editor loadouts. Further supplies must
currently be prepared in the editor. Mining supplies raw resources, but crafting
them into construction materials is unfinished. The
mode is selected at launch, not stored in the world file or enforced by a
multiplayer authority. Opening the gameplay slot in editor mode allows editing.

`NativePlayerInventory.consume_items(costs, expected_revision)` accepts 1–32
item/count pairs and stages deductions across the fixed 32 inventory slots.
Duplicate item rows are cumulative. Failure preserves both slots and revision;
success advances revision once. `can_afford` performs the same validation
without mutation. Neither method scans world content.

`grant_items(items, expected_revision)` and `can_receive` provide the matching
all-or-nothing grant/preflight operations. They accept 1–32 item/count pairs,
reuse existing stacks before empty slots and treat duplicate rows cumulatively.
An invalid row or insufficient capacity leaves all slots and the revision
unchanged. Successful grants advance revision once. Starter supplies use this
batch path. The caller must retain or otherwise handle an unaccepted reward;
these operations do not create overflow storage or retry deliveries themselves.

`NativeRewardInbox` provides bounded pending storage separately from the loadout.
The world registers it as `pending_rewards`; older worlds receive an empty
default. It holds at most 32 distinct item IDs and 10^12 units per item in a
fixed 400-byte format. `accept(items, receipt)` stages the entire batch and
requires a positive, strictly increasing receipt ID. The saved last receipt
rejects duplicates and older receipts after reload. A caller must serialize
one receipt stream per inbox; out-of-order delivery is not supported.

`claim(inventory, items, expected_revision)` atomically transfers a requested
portion through native `grant_items`. Capacity, catalog or revision failure
preserves the pending stock. No callback or await splits the two mutations.
Snapshot both components together using world persistence. Snapshot validation
is structural; the outer compound archive supplies integrity checking.
An inbox at its limit rejects new receipts without partial changes; callers
must handle that rejection. This API does not itself establish multiplayer authority.

The inventory's Pending materials row lists available rewards. Select an item,
enter a quantity and press Claim. Full-inventory or stale-state failures retain
the pending balance and explain how to retry. Successful claims and inventory
transfers mark the world dirty for autosave; F5 also saves the paired state.

In gameplay, `mining_rewards.gd` maps native removed samples 0/1 to stone (201),
8 to iron ore (202), and 9 to copper ore (203). One newly removed solid lattice
sample yields one raw unit; this is not exact physical volume. Other painted
materials yield nothing. Publication delivers one receipt identified by terrain
density revision. No-op/repeated cuts do not accrue resources. The terrain
admission callback rejects additive/road edits and conservatively checks inbox
headroom before excavation. This is bounded orchestration over at most four
commands and three reward types; accounting and inventory mutations are native.

Normal window close drains publication before saving. Direct synchronous
teardown with a pending gameplay edit disables new snapshot writes, retaining
the previous consistent save; unsaved progress can be lost in that fallback.
Receipt rejection likewise protects the prior save and stops further gameplay
excavation. Abrupt process termination cannot save uncommitted progress. The
free editor has no mining reward adapter or additive-edit restriction.

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

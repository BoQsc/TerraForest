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
Static models use provisional recipes: metal beam costs 4 metal, floor panel
costs 8 metal, and doorway costs 8 concrete. The object palette shows the cost.
Gameplay placement debits inventory before native insertion and refunds native
rejection. Missing recipes reject placement. Object removal has no refund;
gameplay object undo/redo and resizing are disabled, while moving and rotating
existing objects remain available. Free editor placement and transform/history
controls are unchanged. Vehicle authoring still lacks a material recipe.
New gameplay inventories start with
tools and 64 units of each construction material. This is the default for a
missing loadout section, not a refill: saved inventories replace it exactly,
including depleted stocks and existing editor loadouts. Further supplies must
currently be prepared in the editor or crafted from mined stone/ore, except
wood, which can also be harvested from reachable forest trunks with E. The
mode is selected at launch, not stored in the world file or enforced by a
multiplayer authority. Opening the gameplay slot in editor mode allows editing.

In the inventory, select brick, wood, concrete, metal, stone, iron ore or copper
ore and press **Drop one
selected supply**. On foot, this places one unit on clear supported ground in
front of the player. It rejects unavailable collision, occupied positions and
world updates without consuming the item. Tools cannot be dropped.
The editor uses the same paid inventory drop action; its separate free
supply authoring tool remains available.

Drops reuse the native bounded pickup stores and batched static renderer: no
per-item node or active rigid body is created. The synchronous coordinator
reserves a native pickup before consuming the selected inventory slot with its
revision check; rejection retires that reservation. Change signals run only
after both sides commit, marking the compound world for autosave. E recollects
one unit through the existing reach/occlusion checks. This is local gameplay,
not network authority. Targeted tests: `tests/inventory_drop.gd` and
`tests/inventory_drop_scene.gd`. `tests/inventory_drop_persistence.gd` verifies
drop and recollection through two autosaves and fresh provider/worker reloads;
shutdown writes are disabled so they cannot mask a failed autosave.

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

The Craft supplies row converts claimed resources using starter recipes:
2 stone → 1 brick, 3 stone → 1 concrete, and 2 iron ore or 2 copper ore → 1 metal.
These are provisional game rules, not physical manufacturing ratios. Select
1–1000 batches; `NativePlayerInventory.exchange_items` consumes inputs and
grants outputs as one main-thread transaction with one revision. Rejected
outputs restore all inputs and the original revision, and consumed input slots
can hold outputs. Recipes live in `crafting.gd` for bounded modding/UI use;
inventory work stays native. No crafting stations, timers or multiplayer recipe
authority are implemented yet. Successful crafting marks the world for autosave.

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

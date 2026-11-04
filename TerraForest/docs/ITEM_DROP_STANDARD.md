# Item dropping standard

Required behavior, 2026-11-04:

- **G drops one held item only during active gameplay** while aiming in the
  world. It does nothing in inventory, menus, text entry or developer tools.
  Selecting a backpack slot does not make it a G-drop target. G must never toggle
  flight. Equip an item on the gameplay belt before using G.
- Every registered inventory item is droppable, including tools, guns, ammunition,
  currency, consumables, clothing, materials, vehicles and filled buckets. There
  is no droppable whitelist, quest-item exclusion or opt-in flag.
- Register new item definitions and their stack/durability rules in
  `addons/player_runtime/item_catalog.gd`. Player inventory and pickup containers
  share that schema. A host with an extended native schema passes it to
  `material_pickups.prepare(persistence, inventory_schema)` before loading saves.
- Existing item-specific pickup batches retain their save-section identities.
  Other items use the shared `pickups_0` / `pickup_stacks_0` batch and an original
  code-built parcel mesh. Custom ground art is optional. New item definitions do
  not add save providers, render batches, ticking nodes or rigid bodies.
- Dropping and recollection transfer the complete native stack record, including
  exact quantity, wear and water volume. Labels identify the real contained item.
  E recollects the stack; an unsuccessful transfer leaves it intact.
- World readiness, supported clear reachable ground, capacity, revisions, focus,
  menus, death and on-foot checks still apply. A rejected drop retains the item.
  Holding G must not repeatedly drop through OS key repeat; typing in a text
  field and Ctrl/Alt/Meta+G must not invoke dropping.
- Dragging outside inventory panels/belt drops the whole stack; Shift-drag drops
  half. Worn clothing can first be moved into carried storage through Character.

Required regressions: `tests/universal_item_drop.gd` exercises every registered
definition and two future definitions without dedicated art, including metadata,
stack transfers, capacity rejection and fresh-provider reload. `tests/drop_key_standard.gd`
sends real G input through the actual world and gameplay belt, and checks that
inventory, menus, typing and developer tools cannot invoke it.
`tests/inventory_drop_persistence.gd -- --drop-item=601` checks universal
drops through two autosaves and three worker/provider lifetimes.

Evidence and scoped acceptance: [universal item-drop issue](../issues/item-dropping/README.md).

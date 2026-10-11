# Player menus and inventory

Use **Play Combined Gameplay.cmd** for the resource-cost gameplay world, or
**Play Combined World.cmd** for the free editor. Both keep their existing save
slots. The UI changes do not reset inventory or chest contents.

- **Escape** opens a clickable menu: resume, inventory, save/load, object and
  block selection, vegetation selection, mining, headlamp, and save-and-quit.
  Escape first closes an open inventory, chest or confirmation dialog.
- **1–9 and 0** equip the ten belt slots in gameplay. These are the first ten
  inventory slots. Development mode retains the editing number shortcuts;
  **Alt+1–9 / Alt+0** equips its belt. Belt buttons also equip tools.
- **Tab** opens inventory. Drag full stacks to move, merge or swap them.
  **Shift-drag** moves half (rounded down, minimum one). Full-stack swaps work
  across player and chest inventories; partial swaps between unlike items and
  merges that exceed a stack limit are rejected without changing either side.
- **E** opens a reachable, aimed chest. Its two grids support direct dragging
  in either direction and rearrangement within either inventory. Quantity
  transfer buttons remain available. A nonempty chest remains protected from
  removal; an empty chest releases that protection.
- Tap the **` / ~ key** to toggle development mode. Hold it for at least
  0.45 seconds and release to toggle flight, entering development if needed.
  Flight is also a button in the development section of the Escape menu.
  Development exposes roads, settlement editing, diagnostics and vehicle
  placement. Returning to gameplay turns flight off, restores resource costs
  and enables mining rewards. Mode changes wait for pending authoring work.

The menu stops player input; the world simulation continues. Development mode
is a local session choice, not multiplayer authorization. Free edits can be
saved, so use the separate editor slot when preserving gameplay progression
matters. The launcher's mode is restored on the next launch.

Inventory rules and cross-container transactions run in the native player
addon. The script controls only presentation, input and bounded orchestration.
The transaction validates both revision tokens and exact target slots before
committing, with no callbacks between the two inventory mutations. Persistence
formats and sparse container capacity remain unchanged.

Automated checks and screenshots: [UI evidence](evidence/player_ui/README.md).
This is the first integrated UI pass; human usability acceptance remains open.

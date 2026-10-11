# Actions, gameplay tools and development

Open **Play Combined Gameplay.cmd** for resource-cost gameplay, or
**Play Combined World.cmd** for free development. Existing save slots and
inventory/chest bytes are preserved.

## One Actions window

**Escape** opens Actions. The sidebar is the shared entry point:

- **Toolbelt:** click any of the ten belt slots, including empty slots.
- **Building:** equips an owned building hammer and shows shape, material,
  rotation and prefab choices. Return to world to aim and place.
- **Objects:** equips an owned assembly tool and shows every object recipe,
  selection, rotation and allowed transform controls.
- **Vegetation:** choose an owned plant/stone stack to place; development
  allows free placement. E gathers reachable ground cover without a special mode.
- **Inventory / crafting:** rearrange items, move items to quick-use slots,
  claim mined resources and craft. Its Actions button returns to the shared UI.
- **Session:** save/load, headlamp, mode switching and save-and-quit.
- **Development / Roads:** appear only in development mode.

Building, object and road panels are the existing detailed controls docked into
this window. Development Building retains prefab capture, stacking, settlement
composition, site survey/preparation, supply authoring and history. Development
Objects retains numeric transforms, scaling and history. Scroll to reach longer
panels. No M/B/H mode switching is required or active through normal input.

## Actual inventory tools

| Item | Gameplay use |
| --- | --- |
| Pickaxe | Hold left mouse to excavate terrain within 3.5 m using a fixed 0.65 m rounded cut. Cannot fill terrain or change brush shape. |
| Hatchet | Left mouse chops a tree within 2.5 m, respecting occlusion and native harvest identity/accounting. |
| Building hammer | Right mouse places the selected block/prefab and consumes materials; left mouse removes blocks. Configure shapes, materials and rotation through Building. Local block targeting is limited to 4 m. |
| Assembly tool | Right mouse places a selected object using its recipe; left mouse dismantles it. Furniture salvage and nonempty-chest protection remain. Local placement/selection is limited to 4 m; dismantling retains its 3 m limit. |
| Empty hands / material stack | Does not activate terrain, building or object editing. E still interacts. |

These are reusable starter tools with simple original held meshes and short use
animations. Durability, tool crafting/repair, polished hand animation and combat
are not implemented. Tools can be rearranged or stored in chests; world dropping
still applies only to supported material/resource items.

The former selector IDs 1-4 now represent pickaxe, hatchet, building hammer and
assembly tool. Existing inventory and chest placements keep their exact slots
and quantities, with the new item definitions. No refill or save reset occurs.
World loading starts with tools put away, so saved legacy editor-mode IDs cannot
reactivate editing. Selecting a slot or moving its item away updates equipment;
placing a tool in a chest cannot leave it usable in the player's hands.

## Input and inventory

- **1-9 / 0** select belt slots in both modes; these keys no longer change editor
  shapes or object recipes. The Toolbelt page provides the same choices by mouse.
- **E** interacts independently of the equipped placement tool: aimed chest first,
  then vehicle/harvesting/collectibles. Object selection is a visible Objects action.
- **Tab** opens inventory. Clicking selects an item or empty slot without moving
  anything; drag it to the toolbelt to hold it. Drag to move, merge or swap. **Shift-drag** moves half
  (rounded down, minimum one). Chest grids support the same exact-slot actions.
  Invalid or stale transactions preserve both inventories; nonempty chests stay
  protected from removal.
- **Tap the ` / ~ key** to switch development mode. Hold at least 0.45 seconds
  and release to toggle flight; **~+F** is also a flight chord. The chord consumes
  F and does not toggle the headlamp or toggle flight again on release. The
  Development page has a Flight button; Session has the Headlamp button. Plain F
  remains an optional headlamp shortcut.
- Development terrain brushes, radius and material choices live in Development,
  outside inventory. Returning to gameplay restores its selected belt slot, disables flight and
  restores costs/mining rewards. Mode changes wait for pending authoring work.

Menus stop player input while the world simulation continues. Development is a
local session setting, not multiplayer authorization; free edits can be saved.
Use the separate editor slot to protect gameplay progression. The launcher sets
the mode for the next session.

Inventory, terrain edits, construction and harvest accounting still use the
existing native stores. UI/held-mesh scripts do bounded presentation and input
coordination; no new per-item simulation or physics bodies were introduced.

Evidence: [unified tools](evidence/unified_tools/README.md) and the earlier
[native drag transaction checks](evidence/player_ui/README.md). Human usability
and sustained frame-time qualification remain open.

Toolbelt selection also accepts the mouse wheel (down: next, up: previous),
including empty slots and wrapping between 0 and 1. Menu and inventory scrolling
does not change equipment. Tool selection and development/flight switches preserve
held movement keys; opening actual menus still stops movement.
Regression: [input and terrain projection](evidence/input_surface_regression/README.md).

Opening inventory also opens a separate crafting panel on the left. Click a recipe
to craft one batch; cards show owned / required ingredients and disable when short
of materials. Claim pending materials before crafting. Empty slots are translucent,
the equipped slot has a mint outline and lower accent, and the selected inventory
slot has a gold outline. Container slots share the empty/selected styling.
Evidence: [inventory presentation](evidence/inventory_presentation/README.md).

Inventory leaves the world undimmed and the toolbelt accessible. Drag between the
inventory grid and belt in either direction, including swaps, merges and Shift
half-stack moves. Backpack (22 slots) and toolbelt (10 slots) occupy separate
slot ranges; each item appears in only one container. While inventory is open,
clicking a belt slot selects it for inventory
actions. [Drag regression evidence](evidence/inventory_belt_drag/README.md).

Crafting and Character buttons above the left panel switch between recipes and
character clothing. Drag woven hood, vest or footwraps to matching Head, Body or
Feet slots; drag back into carried storage to remove. Equipment saves separately.
The initial clothing has no armor bonuses or worn-model art yet.

Release a dragged backpack/belt item outside UI panels and the belt to drop it
on clear ground in front of the player. Normal drag drops the whole stack;
Shift-drag drops half. Invalid/blocked drops preserve items. Each dropped stack
is one world pickup; E recollects its contents. Pickup quantity and equipment
use native transactions and world snapshots. The old Equip/Drop buttons are gone.
[Character and drop evidence](evidence/character_drops/README.md).


## Separate development toolbelt

Tapping `~` swaps the visible gameplay belt for development actions. Each mode
remembers its selection during the session; gameplay stacks stay untouched.
Numbers and mouse wheel select the currently visible belt, including empty slots.
Development actions cannot be dragged into inventory or receive item stacks.
Switch back to gameplay to manage its belt items.

| Key | Development action |
| --- | --- |
| 1 | Sculpt sphere |
| 2 | Sculpt box |
| 3 | Voxel cube |
| 4 | Build blocks |
| 5 | Place objects |
| 6 | Vegetation |
| 7 | Roads settings via Esc |
| 8 | World tools via Esc |
| 9 / 0 | Empty |

Selecting Roads or World tools does not open a modal or interrupt movement.
Press Esc to open the selected workspace. Other settings remain accessible
through the session menu. Evidence: [development belt checks](evidence/developer_belt/README.md).

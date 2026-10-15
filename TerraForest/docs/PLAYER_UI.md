# Actions, gameplay tools and development

Open **Play Combined Gameplay.cmd** for resource-cost gameplay, or
**Play Combined World.cmd** for free development. Existing save slots and
inventory/chest contents are preserved; old records migrate on save.

## One Actions window

While aiming in the world, a prompt below the crosshair identifies nearby
doors, chests, dropped items and collectible ground cover. **E** opens/closes the aimed door,
opens the aimed chest, or collects the named plant/stone within 2.5 metres.
These aimed actions take priority over nearby vehicle entry. A full inventory
leaves the collectible in place and reports that space is needed. Menus and
unavailable world regions suppress the prompt; pressing E always checks the
current target again. Development gathering removes cover without rewards.
For loose items, the nearer aimed pickup or plant wins. Dropped tools retain
their wear when recovered. If nothing is aimed at, nearby pickup recovery
remains available; terrain, buildings and vehicles block that recovery ray.

Tools wear out on successful attacks. A broken tool leaves empty hands, which
can still attack and dig. To replace a pickaxe, gather three stones and two wood
(dry twigs also yield wood), open Tab → Crafting and choose Pickaxe. Move the new
tool to a toolbelt slot to use it. Replacement recipes also exist for the
hatchet, building hammer and assembly tool.

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
| Pickaxe | Hold left mouse to attack any supported solid target; strongest against stone. Terrain cuts use a fixed 0.65 m radius. |
| Hatchet | Hold left mouse to attack or dig; strongest against wood. |
| Building hammer | Left mouse attacks the aimed target; right mouse builds using the selected recipe. |
| Assembly tool | Left mouse attacks the aimed target; right mouse places an object using its recipe. |
| Empty hands | Left mouse punches/digs using the shared attack path, at 5 damage per hit; no tool wear. |
| Material or placeable stack | Does not attack. Right mouse places held building materials as cubes or owned ground cover. E interacts. |

Hands and all four tools share one occlusion-aware 3.5 m attack query with a 250 ms cooldown.
Targets are terrain patches, building blocks, trees, ground cover, furniture/static
models, active actors and vehicles. Partial damage persists through saves. Nonempty
containers remain protected; failed destruction cannot discard their contents.
Untouched targets require no individual health records or update loops.

Tools start with 200 durability. Accepted hits cost one point and break the tool
at zero. Misses and rejected interactions cost nothing. Wear follows native item
records through backpack/belt moves, swaps, chests, drops and save/load. Older
inventory/chest saves migrate with full-durability tools. Toolbelt colored durability bars and
inventory hover text show condition. Four replacement-tool recipes use hand-
gatherable stone and wood. Repair, damage-stage art, collapse physics and combat
balance are not implemented by this change. Existing held meshes remain simple.

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
of materials. Mining delivers materials directly into inventory. Empty slots are translucent,
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
Shift-drag drops half. G drops one currently held item during gameplay; it does not toggle flight. Invalid/blocked drops preserve items. Each dropped stack
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


## Persistent development HUD and durability evidence

In development mode a compact panel stays visible beside the world and changes
with the selected development tool. **F1** hides/shows it; **hold Alt** to release
the cursor and click its controls, then release Alt to resume aiming. Brush radius
and materials, block shape/material/rotation, object choice, vegetation species,
road endpoints/width, and world actions have contextual controls. Detailed authoring
palettes remain available through their buttons and Escape. Inventory/menu panels
hide the compact panel temporarily. These editor actions do not wear gameplay tools.

[Attack, durability and development HUD evidence](evidence/world_attack/README.md).


## Baked item icons

Carried items use shared prerendered icons in the toolbelt, backpack, chest and character slots. Stack quantities remain in the upper right. Tools show a small green/amber/red durability line; hovering with the inventory open shows their name and exact remaining durability. Developer slots clear gameplay visuals. Recipe-based furniture has matching icons in the placement picker. See [icon evidence and rebaking](evidence/item_icons/README.md).


## Gathering and dropped models

Mining grants Stone, Iron ore, Copper ore and Topsoil directly when the terrain edit publishes. Topsoil (item 211) is natural unpainted terrain within two metres of the original surface; deeper unpainted terrain remains Stone. This is a provisional soil-depth rule, not biome-specific geology. There is no Claim row. If inventory fills during excavation, a persisted internal receipt retains excess and transfers it automatically when space opens; further mining pauses until it clears. Old saved pending rewards use this same automatic delivery.

Dropped stacks use 22 baked, single-surface item meshes from the icon baker, including stone, ores and topsoil. Existing native spatial stores and MultiMesh rendering remain in charge: no per-drop nodes, live baking, animations or rigid bodies. Tools retain their wear when dropped. Simple hands appear in an empty slot and animate on the common attack path.

The developer overlay does not own Space: jumping remains available while Alt exposes the mouse, and releasing Alt clears keyboard focus and closes option popups. See [gameplay item evidence](evidence/gameplay_items/README.md).


## Water editing

In development mode (~), open Escape > Water, or choose World tools on the
development belt and click Water / lakes while holding Alt. The page lists each
lake's Ready, Baking or Failed state and its water elevation. Carve lake at aim
uses the existing terrain carving action. Remove water deletes only that water
definition and its published volume, leaving carved terrain unchanged. Save world
to retain the removal. Failed bakes show a reason and Retry bake; repair the terrain
first if the basin is open or its seed is blocked. These are static basins, not
flowing fluids. The page and mutation actions are unavailable in gameplay mode.

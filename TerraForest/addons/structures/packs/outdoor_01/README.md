# Outdoor 01 — yard storage and found objects

Ten original objects, items 820–829, in their own `terraforest.outdoor_01` pack.
The bird nest, duffel, two cardboard boxes, refuse bag, trash can and dumpster
have 4/12/16/12/8/16/32 native storage slots respectively. Tires and litter are
static props. Contents are initially empty; there is no automatic loot refill.

Drop the complete folder under `addons/structures/packs` and restart the game.
Objects and Dev Bag discover the manifest automatically. E opens a nearby
container, drag/Shift-drag transfers stacks, and E/Esc/Tab closes it. Nonempty
containers cannot be removed; contents follow the placement when moved and are
saved under the stable inventory/model identity. Do not rename installed packs
or remove packs referenced by a save.

Objects → Outdoor 01 supplies individual placement. Hold Backtick and select
Objects / inspection to reach the developer controls. Hold Alt to select
inspection/name modes or scatter a bounded outdoor patch at the aim point.
Scatter is explicit, seeded, undoable per placement and never repopulates a save
by itself. It checks support, slope, water, planned road width, objects and player
clearance. Authored scatter zones can additionally declare access exclusions.

The nest eggs and litter pieces are fixed parts of their parent object. There is
no bird simulation, tire rolling, moving lid/wheels or rubbish collection system.
Those features need their own shared runtime design and player-facing validation.
The current task's evidence and remaining checks are in
`docs/OBJECT_PACK_INTEGRATION.md`.

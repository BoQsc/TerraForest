# Wooden fence integration — 2026-10-15

Stable model key: `architecture/wooden_fence/v1`. One baked mesh, 60 triangles,
one wood material, 2 m section, 1.3 m high. Uses the existing native model batch
and bounded nearby static collision (64 m, 256 bodies, 8 builds/tick). A single
continuous box blocks movement through the rail gaps; no separate rail bodies.

The normal object catalog exposes placement through the assembly/editor UI.
Gameplay costs four wood and destruction returns two wood. Editor placement
remains free. The offline icon bake adds one tile within the existing atlas size.

Checks: building_salvage, item_icons and building_object_menu all passed using
the short Godot check runner. The fence test grants fixture materials explicitly,
then verifies the production placement debit, actual attack-ray selection,
protected rejection, repeated damage, wear, exact salvage and no duplicate reward.
The icon screenshot was inspected. Menu testing verifies button signals and
scroll reachability, not OS-level mouse automation.

The interaction fixture is a temporary world: its inherited save message does
not establish fence persistence. No dense fence population, automatic settlement
fences, export bundle refresh or new performance qualification is claimed here.

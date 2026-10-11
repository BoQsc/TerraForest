# Separate backpack and toolbelt

2026-10-11: inventory presentation 24 checks passed; reward/claim UI passed.
Backpack displays only native slots 10..31 (22 slots), numbered 1..22. The belt
alone displays slots 0..9. These are disjoint storage ranges in the existing
native atomic inventory, preserving total capacity, accounting and save bytes.
There are no hidden duplicate belt buttons in the backpack grid.

Dragging moves/swaps/splits between ranges using existing native transactions.
Equip selected from the backpack moves the stack to the first empty belt slot;
if full, it swaps with the active belt slot (or first slot when none is active).
Crafting continues to count carried supplies across both ranges. No items are
created or removed by this change; saved belt contents remain on the belt.

Tests send actual mouse drags in both directions, check distinct ranges, empty
moves, swaps, splits, merges, active tool updates and backpack-to-belt equip.
Fullscreen 1920x1080 screenshot inspected. Not a sustained performance test.

# Furniture dismantling — 2026-10-11

In gameplay construction, M selects object mode; LMB on nearby furniture dismantles
it. Shelf yields four wood, table three, chair one. These provisional values recover
part of the construction cost. E still selects furniture; shelves do not open an
inventory. Loose books and carrying a whole furniture item remain unfinished.

Gameplay object removal now requires a physics hit within three metres. Filled
containers retain their native removal guard. Other object types have no salvage
recipe and retain unrewarded deletion. Free-editor deletion remains unrewarded,
undoable and retains its existing reach.

The bounded event coordinator grants through native inventory accounting before
native geometry removal, so successful removal observers see the reward. Full or
partially available inventory capacity rejects before touching geometry. A rejected
native removal rolls back only its own inventory revision. Reentrant coordinator
calls are refused. Successful salvage clears model history: undo cannot recreate
the rewarded furniture. There is no per-object update loop or native binary change.

Eight native-backed checks pass for full/partial capacity, protected removal, exact
reward visibility at publication, deletion identity, repeat rejection, undo safety
and disabled rewards in free-editor mode. The actual main-world object tool passes
32 checks at fullscreen 1920x1080/cap60, including distance rejection, all three
furniture removals, collision retirement and the exact eight-wood combined yield.
The rendered test is temporary and does not verify salvage-specific save/reopen.
Normal existing compound persistence applies; no new archive section was added.
This is interaction correctness, not dense performance or multiplayer authority.

Reproduce: `tools/run_godot_check.py furniture_salvage --headless --require FURNITURE_SALVAGE`
and `tools/run_godot_check.py furniture_world --require FURNITURE_WORLD -- --gameplay-construction`.

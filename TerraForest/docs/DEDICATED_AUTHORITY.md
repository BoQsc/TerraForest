# Windows terrain and water authority

From the TerraForest project directory, run the installed Windows executable
with its matching game pack and a dedicated slot:

```text
TerraForest.exe --headless --main-pack dist/TerraForest.pck --script res://addons/world_runtime/dedicated_main.gd -- --authority-slot=InlandWorld
```

The operator interface reads ASCII lines from inherited standard input. It
writes JSON records prefixed with `AUTHORITY ` to standard output. The ready
record includes the current terrain revision. Slots live under
`user://authority/`. A new slot generates the seed-1703 inland world with four
lakes. Saving is explicit. A closed input pipe or `quit` releases the lease.

| Operator command | Result |
| --- | --- |
| `lakes` | Read generated lake definitions |
| `sample X Y Z` | Sample terrain density, height, water depth, total water and terrain revision |
| `excavate X Y Z R REV` | Excavate a sphere against the specified revision and return the sample after water settles |
| `save` | Publish a verified compound archive and retain the preceding version as a backup |
| `quit` | End the process |

The current format accepts inline terrain and native volumetric water. World
archives with other components or paged sidecars need those providers and
their collision inputs before this host can edit them. Keep their original
saves in the gameplay world directory. The native archive takes the same
exclusive lease used by gameplay. A failed water transaction requires a
reload of the last saved state.

The operator pipe is local and trusted. This implementation serializes work.
The response to an edit follows the water solve. Concurrent gameplay admission,
regional replication, persistent operation IDs and 30 Hz scheduling remain open.
The standalone process does not load the world scene, player, camera or HUD.

## Regression check

Run `python tools/check_dedicated_world.py --pack --godot TerraForest.exe`.
The test starts independent processes with a temporary Windows application-data
directory and removes its own files after exit. It uses the production game
scene in headless mode for the local comparison. Rendering and presentation
timing are separate qualification gates.

The fixture cuts a three-metre sphere at (240, 31, 224), crossing both a
terrain tile boundary and water-region boundaries. It compares density and
water depth at x=239 and x=241, water conservation, and an outside-terrain
probe at x=256. It tests process restart, archive contention, stale revision,
unsaved process termination, backup identity, and rejected corrupt input.

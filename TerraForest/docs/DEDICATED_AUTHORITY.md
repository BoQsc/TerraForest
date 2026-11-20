# Windows terrain and water authority

From the TerraForest project directory, run the installed Windows executable
with its matching game pack and a dedicated slot:

```text
TerraForest.exe --headless --main-pack dist/TerraForest.pck --script res://addons/world_runtime/dedicated_main.gd -- --authority-slot=InlandWorld
```

The operator interface reads ASCII lines from inherited standard input. It
writes JSON records prefixed with `AUTHORITY ` to standard output. The ready
record includes the current terrain revision and `last_request_id`. Slots live under
`user://authority/`. A new slot generates the seed-1703 inland world with four
lakes. Saving is explicit. A closed input pipe or `quit` releases the lease.

| Operator command | Result |
| --- | --- |
| `lakes` | Read generated lake definitions |
| `sample X Y Z` | Sample terrain density, height, water depth, total water and terrain revision |
| `excavate X Y Z R REV` | Excavate a sphere against the specified revision and return the sample after water settles |
| `v1 ID excavate X Y Z R REV` | Commit an ordered operator request and return its ID, resulting revision and changed flag |
| `save` | Publish a verified compound archive and retain the preceding version as a backup |
| `quit` | End the process |

One trusted operator owns the ordered stream for a slot. Start at
`last_request_id + 1` and wait for the reply before issuing another request.
Retry the most recently committed ID with identical arguments to recover
its original acknowledgement. Reusing it with a different brush, skipping
an ID or submitting an older ID returns an error. Rejected requests leave
the next ID available. A successful explicit save publishes the latest
36-byte receipt alongside the matching terrain and water. After an unsaved
process exit, resume from the ID reported by the reopened slot. Existing
two-section authority archives start at ID zero.

The current format accepts inline terrain, native volumetric water and
the optional operator receipt. World
archives with other components or paged sidecars need those providers and
their collision inputs before this host can edit them. Keep their original
saves in the gameplay world directory. The native archive takes the same
exclusive lease used by gameplay. A failed water transaction requires a
reload of the last saved state.

The operator pipe is local and trusted. This implementation serializes work.
The response to an edit follows the water solve. Concurrent gameplay admission,
regional replication, authenticated peer request streams and 30 Hz scheduling remain open.
The standalone process does not load the world scene, player, camera or HUD.

## Regression check

Run `python tools/check_dedicated_world.py --pack --godot TerraForest.exe`.
The test starts independent processes with a temporary Windows application-data
directory and removes its own files after exit. It uses the production game
scene in headless mode for the local comparison. Rendering and presentation
timing are separate qualification gates.

Each run retains a compact `reports/checks/<run-id>/dedicated_world.json`
with executable and native hashes, workload, probe values before and after the
edit, reloaded values, operator round trip and process memory. The large test
worlds remain disposable.

The fixture cuts a three-metre sphere at (240, 31, 224), crossing both a
terrain tile boundary and water-region boundaries. It compares density and
water depth at x=239 and x=241, water conservation, and an outside-terrain
probe at x=256. It tests process restart, archive contention, stale revision,
unsaved process termination, backup identity, and rejected corrupt input.
The Windows gate also holds the canonical archive open across a save to force
final replacement to fail. It verifies the original bytes, removal of pending
output, and a successful edit/save after restart. Local and dedicated global
terrain revisions must agree and survive reload. The retry check repeats a
saved request after restart and again after an intervening legacy excavation.
Both replies must reproduce the original revision. After a newer versioned
request succeeds, the older ID must be rejected.

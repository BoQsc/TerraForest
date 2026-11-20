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
| `v1 sample X Y Z [X Y Z ...]` | Read one to eight world positions in order, returning one terrain revision and one total water quantity for the set |
| `v1 water-surface X Y Z END_X END_Y END_Z` | Cast a bucket-length segment against the resident water surface. A hit returns world position, normal and owning cell as numeric triples, alongside the terrain revision. |
| `v1 inventory` | Read the trusted local operator's 32 gameplay slots, including bucket contents and durability. The native inventory revision is scoped to the current process. |
| `v1 ID scoop X Y Z END_X END_Y END_Z SLOT REV DIGEST` | Collect water into the selected bucket. Pass the terrain revision and the loadout digest from the inventory query. |
| `v1 ID pour X Y Z END_X END_Y END_Z SLOT REV DIGEST` | Place water using the same five-metre segment and inventory preconditions. |
| `excavate X Y Z R REV` | Excavate a sphere against the specified revision and return the sample after water settles |
| `v1 ID excavate X Y Z R REV` | Commit an ordered operator request and return its ID, resulting revision and changed flag |
| `v1 ID deposit X Y Z R MATERIAL REV` | Add solid terrain, reconcile displaced water and commit under the same request stream. Material IDs 1 through 3 are accepted. |
| `edit-profile` | Read elapsed microseconds for the last executed brush, terrain patch sampling, water snapshot, equilibrium and commit. Patch and solve counts distinguish repeated work. Returns an empty profile before the first brush. |
| `save` | Publish a verified compound archive and retain the preceding version as a backup |
| `quit` | End the process |

One trusted operator owns the ordered stream for a slot. Start at
`last_request_id + 1` and wait for the reply before issuing another request.
A retry of any of the last 32 committed IDs with identical arguments
returns its original acknowledgement. Different arguments or skipped IDs
are rejected. An expired ID returns the high-water mark so the caller can
resynchronize. A successful explicit save publishes receipts with terrain,
water and inventory. Brush records take 36 bytes and bucket records take 80.
The combined history uses at most 2,560 bytes of receipt payload. A
legacy single receipt seeds the window. Two-section archives start at ID
zero. After an unsaved exit resume at the high-water mark in the reopened slot.

Bucket commands use the SHA-256 digest of the native loadout snapshot, which
survives restart. The response reports the actual transferred millilitres.
A pending occupancy request consumes no command ID. The caller can retry it.
The bucket commit signal fires after inventory, water and receipt agree.

The current format accepts inline terrain, native volumetric water, the
gameplay `player_loadout` and the optional operator receipt. On opening a
world without a loadout the host creates the standard construction-gameplay
starter belt. An existing loadout, including an empty one, replaces that
default. Saves publish the loadout and finite water in one archive. World
archives with other components or paged sidecars need those providers and
their collision inputs before this host can edit them. Keep their original
saves in the gameplay world directory. The native archive takes the same
exclusive lease used by gameplay. A failed water transaction requires a
reload of the last saved state.

The operator pipe is local and trusted. This implementation serializes work.
The batched read accepts finite coordinates within the 2000 × 256 × 2000 m
world bounds. Invalid input rejects the whole read. Each entry in `samples`
has `height`, `density` and `depth`. The enclosing response has `revision`
and `water_ml`. Reads leave the excavation request stream untouched.
The surface query uses the same native intersection as a player aiming a
bucket. Both endpoints must be finite and inside the world. A nonzero ray
up to five metres long can return a successful miss. New dedicated brushes
must have radius 0.5 through 8 metres. A retained receipt from an older
build still replays its original acknowledgement.
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
The original acknowledgement also survives a newer versioned request. The gate
fills the window, saves, restarts, and checks both retained endpoints, expired
IDs, conflicting arguments, and unchanged terrain and water.

The fixture also deposits material 2 into the water-filled cut. It checks
water quantity and contact on both sides of the boundary after deposition
and restart. Operation and material are part of the saved request identity.
The edit profile reports receiver searches and cell visits for displaced water.

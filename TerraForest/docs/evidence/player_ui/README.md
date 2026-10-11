# Player UI integration evidence — 2026-10-11

Scope: Escape menu, development mode, ten-slot belt and player/chest dragging.
Godot 4.7.2 Steam; native player debug and release builds use the existing Zig
and prebuilt godot-cpp toolchain. No godot-cpp source rebuild was needed.

`player_ui.log` records actual GUI mouse press/move/release drags in the main
world: chest withdrawal, exact-slot deposit, chest rearrangement, Shift split,
and an inventory swap into belt slot ten. It also checks Escape ownership,
tap/hold tilde, flight-button behavior, restored gameplay accounting, blocked
gameplay flight shortcut, the zero key and clean shutdown. Screenshots show
the gameplay menu, development menu, inventory and chest at fullscreen 1080p.

`container_drag_release.log` has 13 native transaction checks against the
release DLL; the debug run has the same 13 passing checks. Existing container,
inventory transfer and mining-reward regressions pass. `storage_build.log`
and `storage_reopen.log` exercise save, separate-process reopen, same-process
reload and deletion protection with the new grids. Test saves use isolated
slots, not the player's existing world.

Retained failures: the initial hold fixture used a simulation-time timer to
test a wall-clock input duration. It failed, and was corrected to wait for
input delivery and a measured wall-clock hold; final input checks pass. An
earlier storage script parse error (untyped dynamic selection result) was
fixed before the retained final runs. The first isolated release check timed
out because its script omitted explicit extension loading; adding the same
load call used by other native tests resolved it. These were not hidden by
relaxing transaction or input assertions.

These short functional checks are **not a sustained 60 FPS qualification**.
The screenshots include startup/streaming and test synchronization work, with
low instantaneous FPS visible. The asserted 60 FPS cap and 1920x1080 fullscreen
configuration do not establish frame-time performance or laptop thermals.
Human UI acceptance remains pending.

Reproduce from the repository root:

```powershell
python TerraForest/tools/run_godot_check.py player_ui --timeout 60 --require 'PLAYER_UI failures=0' -- --gameplay-construction
python TerraForest/tools/check_storage_world.py
python TerraForest/tools/test_native_release.py --addon player_runtime --test container_drag --godot '<Godot executable>'
```

Run manifests retain commands and revision provenance; `source_hashes.json`
identifies the tested source and installed binaries. Build reports retain
their original pre-line-ending-cleanup source fingerprint.

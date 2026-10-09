# Connected world save/reopen checkpoint

2026-10-09. A fresh graphical process now verifies the combined saved world after
the actual construction editor creates, surveys, prepares and places a connected
settlement. This closes the fresh-process persistence gap recorded in
[connected settlements](CONNECTED_SETTLEMENTS.md), not all M2 coverage.

The persistent fixture uses generator 4, seed 1703, four cottages (1,872 block
cells), two streets with two end connections, one small static model prop, and four
generated lakes in the same world. Forest vegetation remains enabled. The prop is
test-authored through the model API; this is not a furnishing or inventory UI test.
The lakes are distributed in the world, not all beside this settlement.

The first process runs the real construction controls and normal save/shutdown
lifecycle. The second opens the same slot without generator overrides. All 14
reopen checks pass: byte-exact block/model/lake/road state and edited native terrain,
generator/seed retention, all lake definitions rebaking with occupied water,
asphalt at each road's endpoints/midpoint, and normal shutdown. Direct terrain
queries occur only after the owning worker has joined. An initial fixture error
failed to retain that native reference across shutdown; its log is preserved.

Both processes use 1920x1080 fullscreen at full render scale with a 60 FPS cap.
The reopened screenshot was inspected. These are correctness/presentation checks,
not a human playtest, sustained performance or thermal evidence. The earlier
2.002-second graphical outlier remains open; a faster later sample does not erase it.
[Logs, snapshots, manifest, screenshot and build identity](evidence/connected_world/).

## Human checkpoint on this computer

Run [Play Connected Settlement.cmd](../Play%20Connected%20Settlement.cmd). It opens
the verified local save and preserves subsequent edits. It does not regenerate the
world or replace another save. Python and the configured/Steam Godot executable are
required, as with the existing launcher. `--godot PATH` overrides the executable;
`--dry-run` prints the resolved command without launching.

The saved camera/player location is above the settlement. Use flight controls to
approach, inspect roads and buildings, place/edit blocks and objects, then save with
F5. The settlement origin is approximately X=807, Y=47, Z=1310. This checkpoint
does not certify usable furnished interiors, driving routes or detailed city scale.

The save itself lives in local Godot user data and is not in Git. On a new computer,
reproduce creation using `tests/settlement_survey_editor.gd` with user arguments
`--connected-settlement-fixture --save-connected-world --world-generator=4
--world-seed=1703 --world-slot=YOUR_NEW_UNIQUE_SLOT`, then run
`tests/connected_world_reopen.gd -- --world-slot=THE_SAME_SLOT`. Use a new slot for
creation: the fixture expects an empty world. Both graphical commands need
1920x1080 fullscreen and a 60 FPS cap. Expected snapshots are written locally to
`reports/connected_world`; do not run two copies concurrently. To play a reproduced
slot, use `python tools/run.py --slot THE_SAME_SLOT`.

M2 continues with vegetation variety, richer building/interior content and a
representative combined performance checkpoint. Mining continuity, dense streaming,
multiplayer and endurance remain tracked separately. No runtime or save-format
change was required to pass this persistence check.

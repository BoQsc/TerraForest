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

## Furnished checkpoint

Run [Play Furnished Settlement.cmd](../Play%20Furnished%20Settlement.cmd) for the separate furnished copy, with ground cover enabled. It starts on foot inside the first cottage. All four cottages contain a table, chair and shelf; the original checkpoint remains unchanged. Use M for the object tool, E to select, and F5 to save. The furniture is static: sitting and container storage are not implemented.

The local slot and source-copy provenance are in [the furnished manifest](evidence/furnished_world/manifest.json). As with the original checkpoint, user saves are not distributed in Git. Creation and fresh-process reload checks verify exact furniture and other addon snapshots plus central aisle capsule clearance. These checks do not establish general navigation, travel or mixed-workload performance.

The furnished launcher now selects a repaired copy (`walk_probe_1791581867452784300`); the previous furnished slot remains intact. Its four entrances include missing lower stairs and support blocks. Actual on-foot approach-to-interior tests pass for all four cottages, including after save/reopen with exact block restoration. Evidence, original failures and source manifest: `docs/evidence/settlement_walk`. The regenerated cottage prefab also includes the lower stairs for new construction. This is entrance coverage for this layout, not arbitrary slope navigation or a frame-time qualification.


## Generated furnished checkpoint

Run [Play Generated Furnished Settlement.cmd](../Play%20Generated%20Furnished%20Settlement.cmd) for the separate save produced by the actual settlement editor with furniture carried by the prefab. It starts on foot inside the first cottage, with ground cover, fullscreen1080p and cap60. Earlier saves and launchers remain available. Select **Furnished cottage** in the construction palette for a single building or as a settlement source. Editor placement is free; gameplay costs include block materials plus 17 wood per cottage for furniture. Combined placement has no grouped undo and clears prior block undo history; individual editing remains available.

The four cottages have 1896 blocks and 12 interior objects. Exact terrain/addon restoration and object-count checks pass in a fresh process. Evidence and reproduction arguments: `docs/evidence/generated_furnished/manifest.json`. Creation records p95 20.754 ms and maximum 52.725 ms; the interior relocation screenshot HUD reads 22 FPS. These are retained limitations, not a sustained 60 FPS claim. Current-layout walking/travel, grouped undo and representative furnished scale remain open. User saves are local and not distributed in Git.

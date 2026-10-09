# Human checkpoint — 2026-10-09

Double-click **Play Human Checkpoint.cmd** in the TerraForest project folder.
This starts the full world at 1920×1080 fullscreen, VSync enabled, a 60 FPS cap
and 100% render scale. The cap is a target, not a performance guarantee.

The dedicated saved-world slot is `human_checkpoint_20261009`. Existing worlds
are untouched. Launching this shortcut again continues this test world. The
current Windows save location is:
`%APPDATA%/Godot/app_userdata/TerraForest/worlds/human_checkpoint_20261009.trw`.
Keep its associated region/model sidecar directories with it when backing it up.

## First route: about five minutes

1. Walk and turn for a minute. Use WASD, mouse, Shift to sprint and Space to jump.
   Notice uneven movement, tearing, collision catches or uncomfortable controls.
2. Hold LMB to mine nearby. Then press G to fly, travel for roughly 20 seconds,
   release movement and mine somewhere new. Compare response at the two locations.
   Look for visible changes, pauses, recovery cycles and trees disappearing too far
   from the actual edit. Press G again when you want to return to walking.
3. Press B for block building. Use 1 cube, 2 slab, 3 stairs, 4 slope, 5 post or
   6 sphere. RMB places, LMB removes, R rotates, T changes material. Build a small
   floor and stairs; test walking on them. Ctrl+Z / Ctrl+Y undo and redo.
4. Press Tab to inspect inventory; close it with Tab. Alt+1 through Alt+6 select
   toolbelt slots. This checkpoint uses the **free editor**, with no material costs.
5. Press F5 and wait for the save confirmation. Press F9 to reload. Check your
   mining and construction edits. Relaunching the same shortcut should also retain
   the saved test world.

Optional afterward: M enters object placement; V places the vehicle while on foot,
E enters/exits a stopped vehicle, and L carves a lake where you aim at nearby
terrain. These need not delay
feedback on the core route. Escape releases/captures the mouse. F3 toggles diagnostics.

## What is active

Default terrain generation (generator 1, seed 1703), forest/vegetation, block and
static-object building, free-editor toolbelt/inventory, water/lake controls and
vehicle integration. Native block paging uses the existing world path. No laptop
power mode, GPU assignment or graphics-driver setting is changed.

**Not active:** experimental regional/snapshot terrain flags, automatic model
transfer scheduling or model metadata startup. The recent model-streaming code has
native tests but is not connected to automatic focus-driven gameplay. This route
therefore does not qualify those changes. Dense-model transfer latency/timing,
far-travel mining consistency, tearing during motion and sustained laptop heat
remain open observations, not resolved claims. There is no need for a long soak.

## Feedback and records

Stop at the first meaningful problem if you prefer. Tell us what you were doing,
where it happened (F3 or a screenshot helps), and whether it recovered or persisted.
A short recording is particularly useful for mining rhythm, movement and tearing.
You do not need to complete a formal checklist before reporting a bad experience.

Each launch records its Git revision, modified-file list, native DLL hashes,
arguments and logs under `reports/playtests/<UTC timestamp>/`. The launcher prints
the exact folder. The game reports its actual presentation and save path when ready.
This is a checkpoint in the working project, not a standalone exported release;
the Git tag preserves its source revision. Later local changes are recorded in the
launch manifest instead of silently being called the same tested binary.

The short automatic check opened the real scene, verified 1920×1080 fullscreen,
100% scale, VSync and an actual 60 FPS cap, captured an image, and closed normally.
Its isolated startup-check slot saved successfully on shutdown. It did not perform
this human route or establish steady 60 FPS, long-run thermals or correct scanout.
[Evidence](evidence/human_checkpoint_20261009/).

## Launcher correction

Git is optional when launching from Explorer/CMD. The original launcher failed
before Godot started if Git existed only in the development environment's PATH.
The corrected launcher records unavailable revision metadata explicitly and still
records native DLL hashes. The actual CMD was tested with all Codex PATH entries
removed: startup passed, no engine errors were logged, and CMD returned exit 0.
Failure exit codes are preserved across the CMD pause. Evidence is under
`evidence/human_checkpoint_20261009/launcher_fix/`.

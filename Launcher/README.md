# TerraForest Godot launcher

This small, separate Godot project prepares the source checkout and opens the
game. Its window and process orchestration are GDScript. On Windows it uses
Python 3 and Git to check native code and the pinned toolchain to rebuild changed
extensions. Keeping bootstrap
scripts outside the game allows preparation even when the game's import cache
or global script-class cache needs rebuilding.

Launch an editor-capable Godot 4.7 engine with `--path Launcher`. Add
`-- --continue-last` to continue the most recently played world, or
`-- --prepare-only` to import and validate without opening gameplay. The
`TerraForest` source folder must be beside `Launcher`. The checked-in Windows
compatibility `TerraForest/Worlds.cmd` merely forwards to this Godot project.
Desktop shortcuts point directly to the engine and this project.

The launcher paints its controls before starting preparation and caps its UI at
60 FPS. Native checks, imports, log validation, preview preparation and executable/library hashes
run on joined workers. Close minimizes immediately during preparation, then exits
after the current worker releases its files; it starts no subsequent stage or game.
The checkout lease remains held until that exit. Game handoff also minimizes the
launcher; an unexpected game exit restores its error window.

The launcher shows progress, checks the Windows source DLLs, runs the engine's
headless editor import pass, refreshes item previews and starts the world-browser scene. The editor UI
never opens. Import/process failures remain visible with Retry and Open logs.
A loopback listener prevents two launchers for the same checkout from preparing
or launching concurrently. The launcher retains that lease while its game runs.

Each launch uses the local checkout, including uncommitted GDScript and assets.
Windows rebuilds stale debug DLLs before opening the game. It reuses matching
local builds or committed DLLs whose native inputs match the checkout. If a build
fails, the launcher stays open with Retry and the native build log.

Logs use fixed names in `TerraForest/reports`: `worlds_native.log`, `worlds_import.log`,
`worlds_icons.log`, `worlds_game.log`, and `worlds_launch.json` (engine and current
water/generation-script fingerprints). Godot's bounded rotation preserves recent
logs; no new export or world is created by preparation. The optional one-time
Windows shortcut installer is `TerraForest/tools/install_launcher_shortcuts.py`.
It uses Windows COM directly, backs up the original links once under
`reports/launcher_generation/shortcuts`, and verifies both saved link targets.
Use `--last-world-only` to retarget only the **TerraForest Last World** desktop link.

Original launcher code: 0BSD. No third-party code or assets were imported.

## Reusing completed source preparation

On Windows, the launcher first compares a bounded local preparation record with
current file sizes and high-resolution timestamps, the engine identity and the
small Godot import indexes. It enumerates source and imported files without
reading every asset. An unchanged checkout opens the browser directly; native
checks, import, preview preparation and identity hashing run when the record is
absent, stale or explicitly bypassed with `-- --force-prepare`.

New/deleted files, changed scripts, DLLs, assets, import outputs or engine identity
invalidate reuse. A source edit during the preparation pipeline prevents publishing
a ready record. The existing checkout lease, worker cancellation, error UI and
full native/import/bake checks remain in force. This is a local metadata cache,
not a content-integrity certificate: use `--force-prepare` after tools intentionally
restore both file sizes and timestamps. Linux/macOS keep the original preparation
path. Python was already required for Windows native preparation.

The cache uses two fixed JSON files under `TerraForest/reports/source_preparation`,
each capped at 4 MiB, with one atomic replacement file. It creates no world or
export. A prepared record persists across process exits and Windows restarts.
Full-source measurements and the pending post-reboot qualification are in the
[browser issue](../TerraForest/issues/browser-responsiveness/README.md#complete-source-launch--2026-11-26).

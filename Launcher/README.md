# TerraForest Godot launcher

This small, separate Godot project prepares the source checkout and opens the
game. Its window and process orchestration are GDScript; no PowerShell, Python,
command interpreter, or GDExtension is required at launch. Keeping bootstrap
scripts outside the game allows preparation even when the game's import cache
or global script-class cache needs rebuilding.

Launch an editor-capable Godot 4.7 engine with `--path Launcher`. Add
`-- --continue-last` to continue the most recently played world, or
`-- --prepare-only` to import and validate without opening gameplay. The
`TerraForest` source folder must be beside `Launcher`. The checked-in Windows
compatibility `TerraForest/Worlds.cmd` merely forwards to this Godot project.
Desktop shortcuts point directly to the engine and this project.

The launcher shows progress, runs the engine's headless editor import pass, then
refreshes item previews and starts the normal world-browser scene. The editor UI
never opens. Import/process failures remain visible with Retry and Open logs.
A loopback listener prevents two launchers for the same checkout from preparing
or launching concurrently. The launcher retains that lease while its game runs.

Source scripts and imported assets refresh on every fresh launch. Native C++
changes still require the repository's native build step; importing cannot compile
DLLs. This is a source-development launcher, not an updater or hot-reloader for
an already running game. Packaged releases should continue to launch their
exported executable and pre-imported pack. Cross-platform Godot APIs are used;
Windows is currently the verified platform.

Logs use fixed names in `TerraForest/reports`: `worlds_import.log`,
`worlds_icons.log`, `worlds_game.log`, and `worlds_launch.json` (engine and current
water/generation-script fingerprints). Godot's bounded rotation preserves recent
logs; no new export or world is created by preparation. The optional one-time
Windows shortcut installer is `TerraForest/tools/install_launcher_shortcuts.py`.
It uses Windows COM directly, backs up the original links once under
`reports/launcher_generation/shortcuts`, and verifies both saved link targets.
Python is installation tooling only, never part of the launching path.

Original launcher code: 0BSD. No third-party code or assets were imported.

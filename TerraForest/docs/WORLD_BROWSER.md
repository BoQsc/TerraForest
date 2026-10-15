# World browser

`Worlds.cmd` and the Godot project main scene open `demo/worlds.tscn`.
Existing checkpoint launchers continue to open their world directly.

The browser lists canonical saves and filters their names. New worlds choose a
name, seed and existing generator preset. Creation rejects existing canonical,
backup, temporary, region or model data and preparation locks. Opening a world
does not supply generator/seed overrides. The gameplay-cost checkbox applies to
either action. Saving in the world remains explicit through Actions or F5.

The browser launches the actual world in a new Godot process at 1920x1080
fullscreen capped at 60 FPS, then exits. It owns no terrain workers. World
runtime, generation, storage and water implementations are unchanged.

Validation: `tests/world_browser.gd`, graphical report
`reports/checks/20261015T210521848520Z`, all 14 assertions passed. Includes name
validation, preservation of existing sentinel bytes, orphan-data rejection,
launch arguments, filtering, invalid-create feedback and control bounds. The
1920x1080 screenshot `reports/world_browser/browser.png` was visually inspected.
The first run failed because the fixture assigned filter text without emitting
the user typing signal; the corrected fixture exercises the connected signal.

This check does not certify the OS process handoff, fresh-world save/reopen,
exported executables, simultaneous creators, loading time or sustained frame
rate. Existing world-generation and persistence evidence still applies only to
its recorded builds. Whole-world baking, thumbnails and a return-to-browser
action remain future work.

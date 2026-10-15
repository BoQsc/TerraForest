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

**Esc > Session > World browser** asks to save and return (or discard a temporary
review world). It freezes menu/game actions during the save, requires a successful
manual-save response, then shuts down terrain workers and replaces the current
scene with the browser. Save failure leaves the current session open and restores
its controls. Loading and unsafe seated restore positions reject departure.
The browser restores normal window closing after the world's custom close handler.

Departure validation: `world_browser_route.gd` now invokes the actual menu method
on a persistent world, checks that the browser replaces and frees it, and verifies
the changed inventory in another process. Report `20261015T211507281741Z` passes;
child logs are in `evidence/world_browser_departure/`. Stubbed save-failure,
loading and vehicle guards pass (`20261015T211451571999Z`). Browser UI and inherited
window-close policy pass (`20261015T211554755762Z`). Failure injection is a signal
stub, not real disk exhaustion. The route calls the menu method, not mouse input.

Validation: `tests/world_browser.gd`, graphical report
`reports/checks/20261015T210521848520Z`, all 14 assertions passed. Includes name
validation, preservation of existing sentinel bytes, orphan-data rejection,
launch arguments, filtering, invalid-create feedback and control bounds. The
1920x1080 screenshot `reports/world_browser/browser.png` was visually inspected.
The first run failed because the fixture assigned filter text without emitting
the user typing signal; the corrected fixture exercises the connected signal.

Follow-up `tests/world_browser_route.gd` passes production launch-policy arguments
through `OS.create_process` to two sequential graphical Godot processes. It
substitutes an observing SceneTree that instantiates the actual world scene.
Generator 1 / seed 7129 creates a persistent unique slot; seven starter wood
items are consumed and the ordinary compound save completes. Fresh reopen has
no generation overrides and restores the chosen generator/seed and exact changed
inventory. Both processes pass the 1920x1080 fullscreen/full-scale check. Child
logs contain no errors or warnings. Evidence: `evidence/world_browser_route/`,
report `reports/checks/20261015T211018720152Z`. The earlier unmodified-inventory
run passed but was strengthened because defaults alone are weak restore evidence.
The reopened world screenshot was inspected.

This is not an actual mouse click through the browser, nor qualification of
exported executables, simultaneous creators, all presets/seeds, loading time or
sustained frame rate. Whole-world baking and thumbnails remain future work.
Other world-generation and persistence evidence
still applies only to its recorded builds.

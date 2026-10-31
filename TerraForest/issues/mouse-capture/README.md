# Mouse capture on world entry and focus return

- Status: Fixed for reproduced cases; player review pending.
- Updated: 2026-10-31. Supersedes the October 28 click-to-play behavior below.
- User clarification: Alt+Tab away/back must resume play without a click. The
  loading symptom was uncertain; source inspection confirmed that path was also
  still click-only. Esc and other real interfaces must retain their cursor.

## Changes and verification

The October 28 controller revoked the capture request on focus loss and did not
renew it on focus return. Its loading completion also required a click. The old
Alt-tool recovery could not pass the new request gate. A baseline run reproduced
17 failures in 31 focus/input assertions.

`world.gd` now applies one UI-aware rule on world readiness and main-window focus
return. It authorizes play before requesting capture, preserves visible menus,
and retries native capture for at most four frames while rechecking ownership.
Retries use one-shot bound callbacks that disconnect when the scene is freed.
The Alt tool HUD delegates recovery to the same rule. No watchdog, pointer-position
test, foreground activation or inference from mouse mode at focus-out is used.
Loading, shutdown and hidden SubViewports cannot capture the gameplay cursor.
Menu closure after returning focus resumes an authorized gameplay session.

Source verification:

- Focus/input integration: **36 checks pass**, including no-click world readiness,
  OS release before focus-out, both focus event orders, immediate WASD/mouse look,
  stale Alt/dropdown cleanup, four modal interfaces, a menu opening during deferred
  focus return, and loading while unfocused.
- Actual Windows Alt+Tab: **42 checks pass**, including two OS round trips with
  observed foreground process changes. Gameplay recaptures without a click; an
  open Esc menu retains visible mode for more than half a second after return.
- Hidden-world ownership and teardown: **16 headless checks pass**, including zero
  global mouse changes/captures from background loading and UI cleanup, plus
  disposal of a primary world with a pending capture retry and no stale callback.
- `escape_ui_priority` passes its current interface/confirmation/wheel/storage
  matrix. These checks use isolated temporary worlds, not player saves.
- The rebuilt and locally installed PCK repeats all **42 focus assertions** and
  both real Windows round trips, with zero runtime diagnostics. Exported startup
  passes with 14 external native libraries. No player-save files were selected.

Code: [world policy](../../demo/world.gd), [focus hook](../../demo/controller.gd),
[tool recovery](../../addons/player_runtime/developer_hud.gd),
[regression test](../../tests/focus_return.gd),
[Windows driver](../../tools/check_focus_desktop.py).
Evidence and exact run IDs: [qualification](qualification.json).

A first package attempt never acquired foreground and performed zero OS switches;
its cursor assertions therefore failed. That run also exposed a real teardown
error from an awaited retry after the scene was freed. The callback lifetime was
corrected and the desktop fixture now requests initial focus before loading;
it fails early if that prerequisite is unavailable. The failed record is retained.
The first teardown-specific fixture attempted to reparent a live world and hit
unrelated duplicate-disconnect errors; it was replaced by a fresh primary-world
fixture. That rejected test record is retained too.

## Reproduce / remaining review

```powershell
python tools/check_focus_desktop.py
python tools/check_focus_desktop.py --pack
python tools/run_godot_check.py loading_mouse_ownership --headless --timeout 150 --require 'failures=0' -- --gameplay-construction --no-zombies
python tools/run_godot_check.py escape_ui_priority --timeout 150 --require 'COMBINED_RESOURCE_ROUTE failures=0' -- --gameplay-construction --no-zombies
```

After requesting initial fixture focus before loading, the desktop check sends
only Alt+Tab, after confirming the expected test process
owns the foreground, and observes focus returning without a click or forced
activation. Leave the test window foreground while it runs. A source/PCK check
does not establish every Steam overlay, multi-monitor or user-save combination.
Player review of the usual Last World launch remains open: load without clicking,
Alt+Tab twice, move/look immediately, then repeat with Esc open. Reopen this issue
if any of those cases require a click or take the cursor from a menu.

## Evidence provenance / images

No screenshot can establish mouse-capture ownership. The evidence is engine
assertions and Windows foreground PID/handle observations. New implementation and
test code is original 0BSD work, AI-assisted with Codex from the user's report and
existing repository code; no external code or assets were imported. Local logs
and run manifests retain failures as well as passing results.

## October 28 history — superseded

- Status: Corrected / scoped checks; desktop playtest review pending.
- Updated: 2026-10-28.
- Cause: finishing loading requested captured mode without player input; focus loss
  left that mode active. Captured mode inherently centres the system pointer.
- Gameplay now captures only after a focused, unhandled left click in the world.
  Loading and focus loss revoke capture; returning focus does not reclaim it.
  The first click is consumed, not an attack. Closing a gameplay menu still resumes
  an already authorized session. Background viewports cannot change global modes.
- No mouse warps, extra windows, launcher policy files or helper processes added.
- `tests/loading_mouse_ownership.gd`: 13 passing headless checks;
  `reports/checks/20261028T070529313843Z/`. The earlier headless run retained four
  assumptions about captured mode/native windows unsupported by that display driver.
- No screenshot establishes desktop input ownership. Still review actual launch,
  loading, Alt-Tab and click-to-resume on the player's desktop.
- Installed package repeats all 13 assertions with zero diagnostics:
  `reports/checks/20261028T082918413737Z_queued_pack/loading_mouse_ownership/`.
  Actual production generation and read-only game reopen also leave capture
  unauthorized: `reports/checks/20261028T081755681198Z/`.

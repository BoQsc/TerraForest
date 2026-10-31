# Issue: mouse capture / focus on entering a world and after Alt+Tab

Status: **unfixed**. Written as a handoff so someone else can pick it up without repeating the dead ends.

## What the user reported (their words)

> "the main problem is that we enter world and mouse is not focused on game to play. and if we do alt
> tab it is not force focused back too."

> "I just launched the last world and it wanted me to click to focus and play"

Two symptoms, same root:

1. **Entering a world** (from the world list, or the `TerraForest Last World` desktop/Steam shortcut) the
   game sits in "Click the world to play" state. Until the left mouse button is pressed, mouse-look,
   WASD-by-capture, and every interaction feels dead.
2. **After Alt+Tab away and back** the game window is in the foreground again, but the pointer is not
   re-captured, so another click is needed before play resumes.

Requirement from the user: **no click** in either case, and **the Esc session menu must keep its cursor**.

## Environment

- Windows (10/11), Godot 4.7.2 stable (steam build), Vulkan / Forward+.
- Project: `TerraForest/` (run via `TerraForest.exe --path <project>`).
- Window mode: fullscreen, `project.godot` → `display/window/size/mode=3` (borderless fullscreen).
- Reproduced with world slot `Copper_Creek` (any slot).

## Where the behaviour lives (search these symbols; line numbers drift)

`demo/controller.gd` (the input/player controller inside the world scene):

- `_notification(what)` → `NOTIFICATION_WM_WINDOW_FOCUS_OUT`:
  `app_focused = false`, `mouse_capture_requested = false`, `Mouse.set_mode(self, Input.MOUSE_MODE_VISIBLE)`.
- `_notification(what)` → `NOTIFICATION_WM_WINDOW_FOCUS_IN`:
  restores vsync and `app_focused = true` — **and nothing else**. No re-capture.
- `_capture_mouse_click(event)` (~line 520): the **only** path that sets `mouse_capture_requested = true`
  and requests `Input.MOUSE_MODE_CAPTURED`. It runs on a left mouse button press.
- `_mouse_capture_allowed()` (~line 518): requires `mouse_capture_requested and app_focused and not
  loading_active and not shutdown_requested`.
- `_movement_input_available()` and most gameplay gates test
  `Input.mouse_mode == Input.MOUSE_MODE_CAPTURED` (see also `demo/world.gd`: headlamp F, interact E,
  tools, placement, vehicle interaction). That is why "not captured" feels like "game not focused".
- World-ready path: sets `loading_active = false`, then shows `_message("Click the world to play · nearby
  terrain is ready")`. This message **is** the "you must click" prompt.

`addons/world_runtime/mouse_ownership.gd` — `Mouse.set_mode(owner, mode)`:

- refuses `MOUSE_MODE_CAPTURED` when `not owner.get_window().has_focus()`;
- refuses it when the owner has `_mouse_capture_allowed()` and that returns false.

So capture can only be granted when the request flag is already set and the window already reports focus.

`demo/world.gd` (the scene root) owns the UI state that decides whether the cursor is legitimately free:
`session_menu.visible_ui()`, `player_hud.inventory_open`, `storage.opened`, `loading_active`.
`addons/player_runtime/session_menu.gd` (`set_open`) is what shows the cursor for the Esc menu.

## Measured facts (do not re-derive these)

Instrumented run: `TerraForest.exe --path <project> res://demo/world.tscn -- --world-slot=<slot>
--ground-cover --actors --vehicle-fleet --max-fps=60 --focus-diagnostics`
(the `--focus-diagnostics` prints in `controller.gd` are gated and silent without the flag).

1. **Capture at world start works when requested**: log shows `CAPTURE mode=2` (2 =
   `MOUSE_MODE_CAPTURED`) right after the world becomes playable.
2. **The cursor is already released when the focus-out notification arrives**:
   `FOCUS_OUT play=... mode=0` even though the pointer was captured a frame earlier.
   → "was it captured?" **cannot** be read from `Input.mouse_mode` inside
   `NOTIFICATION_WM_WINDOW_FOCUS_OUT`. Windows/Godot deactivate and release before the notification.
   Any resume logic built on that value silently never fires. This was the actual reason three earlier
   attempts changed nothing.
3. **A real Alt+Tab round trip works once the decision does not depend on that value**: with an
   intent flag, the log shows `FOCUS_OUT play=true mode=0` → `FOCUS_IN play=true mode=0` →
   `CAPTURE mode=2`, i.e. the pointer comes back with no click.
4. **The game window does receive foreground** on the second Alt+Tab (verified with
   `GetForegroundWindow`: `is_game=True`). This is not a Windows activation problem.

## What was tried and why it failed (avoid repeating)

- **Resume on focus-in using `Input.mouse_mode` read at focus-out** → always `0`, so nothing resumed.
- **Gating the resume on "pointer inside the window"** (`Viewport.get_mouse_position()` vs
   `get_visible_rect()`) → right after a focus change that position is unreliable and reported *outside*,
  so the resume was skipped (measured `inside=false` while the cursor was over the game).
- **A periodic "keep captured" watchdog in `controller.gd`** (every 30 physics frames) → it did restore
  capture, but it also stole the cursor back from the **Esc session menu** every half second, breaking
  the menu mouse. Reverted for that reason.

## Recommended fix (not yet implemented)

Put **one** rule in `demo/world.gd`, which owns the authoritative UI state, instead of detectors in
`controller.gd`:

> While the window is focused and no UI owns the cursor (`session_menu.visible_ui()`,
> `player_hud.inventory_open`, `storage.opened`, not `loading_active`), the pointer is captured.
> Apply it (a) when the world becomes playable, and (b) on `NOTIFICATION_WM_WINDOW_FOCUS_IN`.

Implementation notes:

- Do **not** poll on a timer — that is what broke the Esc menu.
- Do **not** infer the previous capture state from `Input.mouse_mode` at focus-out; either re-evaluate the
  UI state on focus-in, or keep an `intent` flag updated every frame while `app_focused` is true.
- `Mouse.set_mode` refuses capture unless `_mouse_capture_allowed()` already allows it, so set
  `mouse_capture_requested = true` **before** requesting capture, and retry a few frames if the window has
  not reported focus yet.
- Keep the Esc menu working: when `session_menu` is open the rule must decline to capture.

## How to verify

1. Launch a world with `-- --focus-diagnostics` and **do not touch the mouse**; expected log:
   `CAPTURE mode=2` shortly after the world is playable.
2. Alt+Tab away, Alt+Tab back; expected log: `FOCUS_IN ...` followed by `CAPTURE mode=2`.
3. Press Esc (session menu opens with a visible cursor) and confirm the cursor stays usable — no
   `CAPTURE` lines while the menu is open.
4. Manual confirmation: move the mouse and press WASD immediately after re-entering — no click.

## Repository state at time of writing

- Working tree has **one modified file only**: `demo/controller.gd`, containing the abandoned patchwork
  described above (an `_enter_play_capture` / `_ensure_play_capture` / `_ui_owns_cursor` attempt plus the
  gated `--focus-diagnostics` prints). Restore it to the committed state before starting, or lift only the
  diagnostic prints if they are useful.
- `demo/world.gd`, `project.godot`, and everything else are unmodified.

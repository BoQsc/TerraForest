# Player workflow improvements — 2026-10-26

## Implemented

- M map is non-modal for walking, crouching and jumping. Held keys survive opening;
  releases still stop movement. Pointer interaction remains map-only: tools cannot
  attack/place through the map. Living encounters no longer pause because the map
  is open. Existing developer Ctrl-click travel retains its loading/readiness gate.
- ESC has a Graphics page with one fullscreen/windowed toggle. The preference is
  saved outside worlds and reused by startup/F11. Save and quit calls the normal
  close/save/drain path directly; only the redundant confirmation is removed.
- Holding backtick opens a circular player-actions menu. Move outward and release
  to toggle flight, or press 1/F; Esc/right click cancels. Gameplay inventory/belt
  stays unchanged. A short tap retains the existing development-belt switch.
- Ctrl crouch changes the native capsule from 1.8 m to 1.1 m at the same feet,
  lowers the eye to 1 m and limits speed to 2.6 m/s. Standing checks the original
  capsule against ordinary collision; an obstructed head keeps crouching. No
  collision bypass, teleport escape or player-radius shrink is used.
- Eight slide iterations, a 4 mm recovery margin and zero minimum wall-slide
  angle remove the reproduced shallow-angle movement lock. An unchanged old
  setup travels zero metres along the wall; the new setup travels 1.63 m during
  the same two-second input. Sharp convex-apex escape, low passages, metre-high
  walls and ceiling-blocked stairs have explicit physical tests.
- The source GLB's named crouch clips were standing placeholders, despite their
  names. The reproducible offline crouch bake lowers hips 0.7 m, solves bent legs
  against unchanged ankles, and moves independent weapon bones with the hands.
  Two cached animation clips preserve the source hand holds. Animation playback
  stays native; no per-frame script IK or new model is introduced. This is a basic
  crouch pose, not a newly authored crouch-walk/attack animation set.
- Carried vegetation gets a translucent actual-species ghost using the renderer's
  existing meshes. Valid, rejected and updating spots remain visible in mint,
  coral and amber. The normal on-click probe still authorizes placement.
- Block preview refreshes immediately after meaningful camera motion rather than
  waiting out a stale 100 ms timer. Its exact-grid outline stays visible when soil
  covers its fill. Placement rules, reach, paid mutations and the lattice do not
  change; this does not solve the separate generation/grid-fit issue.
- Hold-RMB places successive paid terrain samples as native transactions finish.
  Only one native terrain edit can be in flight; no arbitrary repeat cooldown or
  unbounded edit backlog is added. Release/focus/menu/equipment changes stop repeat
  input. Explicit queued clicks retain their existing live-context validation.
  Updating terrain keeps its compact marker amber instead of hiding it.
- Corpse storage is eight slots; wooden chests are sixteen. Capacity is native,
  not just hidden UI. Old occupied overflow slots remain visible/retrievable and
  shrink only after emptied. Existing fixed-size binary snapshots remain accepted;
  no player inventory or old saved contents are truncated.

## Window-mode diagnostic

This installed Godot 4.7.2 Windows build unexpectedly reports exclusive fullscreen
after requesting normal windowed mode, even through an isolated direct
DisplayServer call. Direct mode calls, Window.mode, resizing and a project-setting
trial are retained failures, not accepted windowed results. The policy first
requests ordinary decorated windowed mode; if the engine still reports fullscreen,
it uses decorated maximized windowed mode. It does not substitute borderless
fullscreen. Three repeated transitions verify the same native window handle and
one game window. Tests persist preferences only in an owned temporary config.

## Verification and scope

Focused source checks cover actual input/UI, 54 terrain-placement assertions,
native movement/capacity and preserved legacy overflow, sharp contacts, cottage
stairs, developer map travel, corpse contact, and actual loot/save/fresh-process
reload. Debug and release native builds succeed; release container store, drag
and cross-inventory suites pass 23/23, 13/13 and 29/29.

The source moving-preview fixture matches its live target in all 45 frames;
mean update cost is approximately 0.16–0.20 ms on this i5-12450H/RTX 4050 Laptop
system. Two held terrain stamps start in approximately 0.53–0.58 seconds while
the aim travels across actual forest ground. These are local warmed measurements,
not all-hardware frame-time/terrain-publication guarantees. No world-generation
quality threshold is changed. User saves and graphics preferences are untouched
by the test fixtures.

Final packaged manifests/logs and inspected captures are retained alongside this
file. Engineering passes do not approve animation aesthetics or establish that
every possible sharp/concave collision can never trap a player. Return with an
exact saved stuck case for a new physical reproducer; retain collision and stair
safety. Broader crouch-walk/attack presentation and sustained edit-heavy/lower-end
performance need separate acceptance, not a claim that this pass closes them.

### Retained results

- Packaged workflow: 22/22, including real map movement, crouch/eye/visible hip
  lowering, graphics toggles, direct quit dispatch, radial choice/cancellation,
  vegetation ghost, all 45 moving preview frames, and continuous paid terrain.
- Packaged terrain preview/placement: 54/54, including single clicks, two queued
  clicks, stacking topsoil, blocking props and exact material debits. The old
  click-only fixture needed explicit mouse releases after adding hold behavior;
  its earlier failure is retained, not counted as a successful hold test.
- Packaged corpse contact with the new actual player settings: fifteen phases,
  all fourteen joints retained, all fifteen bodies asleep at the end; peak anchor
  error 5.914 mm. Actual loot/save/reopen: 18/18 and 9/9.
- New stance/capacity/movement fixtures also pass against the release DLL in a
  separate owned project (`*_release.json`), not only the editor/debug library.
- Final window-policy follow-up avoids toggling a saved maximized window through
  fullscreen again at startup. Reapplication now produces no resize. The final
  workflow/window checks have their own `final_*` package manifests; preceding
  terrain/corpse/lifecycle package records retain their original pack hashes.
  Their native DLL hashes are unchanged. Export/startup passes, and the installed
  native libraries match source byte-for-byte (`package_hashes.json`).

Earlier failed script/fixture runs and the rejected direct window-mode experiment
are retained separately. A clip-name-only crouch check initially passed despite
the standing visual placeholder; visual inspection rejected it. The final test
requires more than 60 cm actual hip lowering, with the baked asset inspected.

## Reproduce

```powershell
python tools/run_godot_check.py player_workflow --timeout 150 --require "PLAYER_WORKFLOW checks=22 failures=0" -- --gameplay-construction --ground-cover --no-zombies
python tools/run_godot_check.py player_stance --headless --timeout 45 --require "PLAYER_STANCE failures=0"
python tools/run_godot_check.py container_capacity --headless --timeout 30 --require "CONTAINER_CAPACITY failures=0"
python tools/run_godot_check.py window_modes --timeout 30 --require "WINDOW_MODES failures=0"
python tools/check_gathering_lifecycle.py --pack
```

`tools/bake_player_crouch.gd` rebuilds the two cached crouch clips from the existing
GLB. Its logged ankle error is below 0.000001 m. Native fixtures run headless;
input/captured-pointer/world tests require a graphical viewport.

# Loading cursor ownership — 2026-10-25

The repeated cursor recenters were real, but were not evidence of new game
processes. Offscreen photograph worlds used the same controller and UI helpers
as the playable world. Their loading-complete, map-close and menu-close paths
wrote the process-global `Input.mouse_mode`. The visible generation screen then
forced visible mode every frame. Repeated photograph destinations therefore
captured/released the real desktop cursor inside the existing game process.

## Fix and ownership contract

- `mouse_ownership.gd` only accepts requests from nodes belonging to the root
  viewport. A hidden SubViewport cannot capture **or release** the visible
  scene's cursor, even without relying on the global offscreen-session flag.
- Controller, selector, map, inventory, storage, session/developer UI and vehicle
  radial menu use this shared boundary. New player-flow UI must use it too,
  rather than writing global mouse mode directly.
- Unchanged mouse modes are not reapplied. Loading/shutdown controllers cannot
  acquire gameplay capture through a menu cleanup operation.
- The generation screen requests visible mode once, instead of fighting other
  writers every frame. Background jobs no longer save/restore mouse mode they
  never owned. Their session-argument, frame-cap and title cleanup is retained.
- Two integer counters expose actual applied mode changes/captures to regression
  checks. There is no cursor polling, render loop or native simulation change.
- Intentional user actions still work: entering gameplay captures the mouse;
  real menus release it; the user-requested vehicle radial can still center it.

## Verification

| Check | Result | Evidence |
| --- | --- | --- |
| Hidden-world reproduction before fix | 7 failures out of 9 checks | `before/` |
| Hidden loading/map/menu/inventory ownership; repeated foreground request | 11 checks, zero failures | `source/` |
| Same regression using production resources from the rebuilt PCK | 11 checks, zero failures | `pack/` |
| Alt-Tab, tool popup, inventory/session/map ownership | 29 checks, zero failures | `focus/` |
| Cancel generation, default connected world, north/road/market photographs, play, save and selector | 15 checks, zero failures; exactly one capture at playable handoff | `generation/` |
| New/load/return, three-photo refresh, cancellation and another world | 24 checks, zero failures; photograph capture count and mode-change count both zero | `session/` |
| Exported startup | Passed with 14 native libraries | `pack/pack_smoke.log` |

The integrated generation/session tests verify a stable native window handle,
same-process job IDs and no external-renderer generation phase. Independent
250 ms OS process samples observed at most one Godot process at once during the
test sequence (`process_samples.json`). Separate test invocations naturally have
different process IDs; they are not nested renderer processes inside one game.
Sampling is supplementary evidence, not a guarantee about unobserved intervals.

The normal `Worlds.cmd` launcher still performs one sequential headless icon check
before opening the game. That is not a set of background Godot renderers during
generation. The explicit external/headless CLI compatibility path remains separate
from the normal same-window player flow.

Existing user saves are unchanged. Integrated checks create isolated test slots;
read-only photograph refresh and cancellation preserve the saved root digest.
No roof geometry, image quality, generation layout or streaming budgets change.

## Retained test issues

- `focus_wrong_mode/` ran the gameplay tool-dropdown fixture in development mode,
  whose selected actor tool has no dropdown. The other focus checks passed.
  Rerunning with the actual `--gameplay-construction` mode passes all 29 checks.
- `stationary_cursor_assumption/` and `stationary_cursor_diagnostics/` required
  the physical cursor to remain still throughout photograph refresh. The user
  confirmed they were moving the mouse. The diagnostic run recorded **zero
  captures**, so those position-only failures are not game recaptures.
- The corrected integrated test permits normal user motion and asserts zero
  game-driven mode changes/captures. It retains window/desktop positions as
  observations, not a requirement to immobilize the user. The focused synchronous
  offscreen-UI check separately verifies that those operations do not move the
  cursor. Earlier failed runs are not counted as passes.

## Reproduce

```text
python tools/run_godot_check.py loading_mouse_ownership --timeout 140 --require "LOADING_MOUSE_OWNERSHIP checks=11 failures=0" -- --no-zombies
python tools/run_godot_check.py focus_return --timeout 120 --require "FOCUS_RETURN checks=" -- --no-zombies --gameplay-construction
python tools/run_godot_check.py window_generation_flow --timeout 600 --require "WINDOW_GENERATION_FLOW checks="
python tools/run_godot_check.py window_session_flow --timeout 480 --require "WINDOW_SESSION_FLOW checks="
```

The exact standalone packed-test command, source/native hashes and completion
results are retained in the per-run manifests. This closes the loading cursor
ownership defect, not the separate world-quality/performance backlog.

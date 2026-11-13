# Saved-world browser flashes during Last World startup

- Status: Fixed for reproduced presentation path / desktop review pending.
- Updated: 2026-11-04. Source: `demo/worlds.gd`, `addons/world_runtime/world_session.gd`.
- User report: TerraForest Last World briefly shows saved worlds before loading.

The Steam shortcut opens `worlds.tscn` with `--continue-last`. Previously that
scene built and drew the browser, scanned the save catalog on a worker, then
deferred continuation until a later frame. The world-loading cover was created
only after selection. The flash came from this presentation ordering; catalog
resolution is still needed to determine the last played save.

Last World now creates the shared opaque loading cover before browser setup and
catalog work. Its first phase says “Finding last played world…”. The same cover
continues into game-resource loading, including the catalog time in elapsed time.
Auto-continue skips selected-world thumbnails/details. Empty/vanished saves or
load failure reveal the browser with feedback. The process startup request is
consumed once, so returning from gameplay cannot immediately reopen the world.
Shortcut registration, save selection order and saved-world contents are unchanged.

## Evidence

![First rendered Last World loading frame](images/loading-first-frame.png)

Source fixture, Forward+ 1920×1080, first rendered frame after ready. The opaque
cover hides browser controls while the catalog resolves. Developer-details
visibility reflects existing local preferences, not a presentation change here.

![No-save fallback](images/no-save-fallback.png)

Same rendered fixture with an empty isolated catalog: the browser is deliberately
revealed with “No saved world to continue.” Both images were inspected.
[Image sources/hashes](images/manifest.json), [verification](evidence.json).

The focused rendered fixture passes 11 checks in source and the actual exported
executable: synchronous cover, real initial phase, same-cover dispatch, newest
save selection, no thumbnail work, one-time request, empty/vanished/error fallback
and uncaptured pointer. Routing is intercepted before initialization of unique
dummy test saves; user worlds are not opened or changed. Export smoke and house-
light gates pass. The installed desktop link was read and still uses Steam.

Existing browser suites retain unrelated failures: nine generator/default-policy
assertions and two preview assertions. Both sets reproduce with the pre-change
browser script; they are not reported as passing here. Their logs are linked in
the evidence record. Refresh those policy/preview contracts in their own scope
before claiming the whole browser suite passes. The first focused harness also
used an isolated catalog without matching canonical fixtures; corrected before
passing runs, with its failed log retained.

## Remaining / resume here

Confirm the real desktop/Steam launch visually on the user's system. If any
browser frame remains visible, capture the first frames and launch arguments;
verify the loaded source/PCK and cover lifetime. This does not claim faster
catalog scanning or whole-world load completion/performance acceptance.

Run `python tools/check_continue_last.py`, or add `--executable` after export.
Code/tests are original Codex-assisted 0BSD work; no new media was imported.
Diagnostic screenshots preserve the existing game's asset terms. The existing
unused Kaino source folder was temporarily excluded during export as in preceding
builds; original recordings remain intact and the marker was removed afterward.

## Launcher freshness and interrupted generation — 2026-11-13

Status: investigating; read-only desktop/Steam/log inspection, no runtime fix.
The desktop Last World link resolves through Steam to the root `TerraForest.exe`
with `--path <source project> res://demo/worlds.tscn -- --continue-last`.
It bypasses `Worlds.cmd` / `tools/start_worlds.ps1` and does not explicitly select
`dist/TerraForest.pck`. No adjacent root PCK was present. The root executable is
dated November 7; its date alone does not establish stale project content.
The existing source launcher refreshes item icons but has no editor import pass.

Recent user logs contain the current `OFFLINE_GENERATED_LAKES` output (12 lakes,
27,351,242,997 ml) and successful prepared cartography. Latest generation report
`user://generation_reports/7765abb05a2ea92ae02a5651aa440448/creating_progress.json`
stops at building/interior placement, 7 of 50. The preceding
`user://logs/godot2026-11-13T19.27.57.log` ends with a native Dictionary `_unref`
null-parameter error. These observations do not establish crash causality or
prove import staleness; opening the editor is not a demonstrated generation fix.

Next: reproduce the ordinary seed-1703 generator-29 creation path through the
actual shortcut, capture its exit status and the building-placement failure.
Keep user saves intact. Separately unify launcher entry points with a headless
editor resource-import preflight, propagated Continue flag, explicit source or
installed-pack mode, and bounded logs plus executable/content identity. Native
changes still require builds and process restart; imports cannot rebuild DLLs.
Closure requires fresh-resource launch and successful ordinary world generation,
not only saved-world reload or an isolated presentation test. No new screenshots
were taken for this read-only investigation.


## Native launcher and generation repair plan (2026-11-13)

1. Implement a separate Godot/GDScript bootstrap project with import preparation,
   Continue Last, a visible error/retry UI and one launch lease per checkout.
2. Retain native water mesh jobs until cancelled workers are joined.
3. Repair coastal rounding, independent body heads and bounded multi-body work;
   fit dense mesh batches and indexed query surfaces within existing allowances.
4. Wait for stable water before quest baselines, saving and map certification.
   Verify normal Generate & play and fresh Continue programmatically.
5. Install/verify desktop links, update the installed distribution, retain failures
   and regression evidence, and commit the completed repair.

The baseline ordinary seed-1703 UI run crashed at building 26/50 with Windows
heap corruption. Native worker Callables did not retain the RefCounted mesh job;
terrain invalidation could release it during execution. Dispatcher ownership now
lasts through join, including cancellation and shutdown (24 lifecycle regressions).
The first repaired run saved 52 buildings but stalled at 99%; it was not accepted.
Subsequent real runs exposed rounding surplus, shared heads between disconnected
bodies, aggregate transaction limits, and dense snapshot/query-cache exhaustion.
All failed runs remain under `reports/launcher_generation`, including
`failed_create_map_identity` and `failed_continue_dummy_texture`.

The final ordinary Frontier expedition, seed 1703, uses actual world-browser
controls and Generate & play handling, not an isolated generation scene. It
publishes 52 buildings and 8,183 edits, reaches playable state and shuts down
with a verified save. The generation barrier also prevents changing water state
from invalidating the map's saved-state certification. Indexed query geometry
retains the same triangles and uses 43,475,880 bytes of the existing 64 MiB cap;
no cache or transaction budget was raised. Final water has no pending regions,
settlement, dirty meshes or water preparation errors.

Verification and installation status is recorded below. Scope: this repairs
source launching and this normal creation/continuation path. It is not new visual
approval, an FPS qualification, or proof that every seed fits existing limits.
Single connected bodies exceeding the bounded transaction still fail visibly.
Cross-platform APIs are used, but only Windows has been exercised. Native C++
edits still need the native build step; imports cannot compile a DLL.

Both desktop shortcuts now target the separate `Launcher` Godot project directly;
Steam library entries are unchanged. Preparation refreshes source imports with
no editor window. Original links and verified targets are retained under
`reports/launcher_generation/shortcuts`. The PowerShell runtime launcher was
removed. Python is used only for development checks and one-time link installation.

### Verification receipts

- Runtime repair commit: `d587ec54` (debug and release libraries rebuilt).
- Normal UI creation: `reports/launcher_generation/create/run.json`, PASS,
  96.85 seconds; `WORLD_GENERATED failures=0`, then playable and verified shutdown.
- Fresh normal Continue: `reports/launcher_generation/continue/run.json`, PASS,
  28.21 seconds; zero diagnostic errors and the expected owned world restored.
- Native launcher: `reports/launcher_generation/launcher_contract.log`, 8 checks;
  `launcher_prepare_final.log`, real import/icons preparation exit 0, current
  script fingerprints and Continue flag in `reports/worlds_launch.json`.
- Water equilibrium: `reports/checks/20261113T180948280343Z`, 39 checks, zero failures.
- Worker lifecycle/meshing: `reports/checks/20261113T181907215111Z`, zero failures,
  including 24 real coordinator invalidation/shutdown cycles.
- Storage tooling: four unit checks pass; new Python tools compile.
- Compact runtime quantities and hashes: `reports/launcher_generation/verification.json`.

The receipt-owned Fixed and Final worlds are retained as diagnostic fixtures and
excluded from the player browser/Continue catalog. Repeated checks restore that
marker even on failure; the Continue driver refuses to launch a non-fixture world.
No player world was used for generation or modified by these tests. After the
user requested no nonprogrammatic interruption, checks used headless Godot control
signals and owned subprocesses only, with no desktop focus or input manipulation.

All five repair-plan steps are complete for this reproduced path. Installed pack
export and startup pass (`reports/launcher_generation/export_final.log`), including
all nine required source/release building contracts
(`reports/building_standards/20261113T183338020445Z/run.json`). Installed debug and
release water libraries match the current source-build hashes. The read-only
normal Continue report resolves to the original player slot
`StartupBench_FPS_20261109T215117560533`; it was not loaded or modified
(`reports/launcher_generation/player_continue_target.log`).

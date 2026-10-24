# One persistent game window

2026-10-24. Godot 4.7.2, Windows x86-64, Forward+, RTX 4050 Laptop GPU.

## Change

The normal player path now keeps the same process, root Window and Windows
native window handle through selector → generation/loading → gameplay → selector.
`WorldSession` is a persistent autoload, ready before the initial selector starts.
It switches scenes in place, with a loading cover spanning the transition. It
does not close the selector's operating-system window and start another game.
Confirmations and other Godot dialogs are embedded inside the root window.
Applying fullscreen no longer reapplies an already active fullscreen mode.

Generation and read-only photograph capture now use shared Node tasks. One
temporary SubViewport owns their isolated 3D world, renders at 1920×1080 with
the root's MSAA/screen-space AA/TAA settings and full render scale, and is freed
before another world opens. No child renderer process or native Window is created
by the player-facing path. Planning, terrain, native baking, map caching, storage
verification and publication retain their existing worker/native owners.

The old command-line scripts are thin adapters around those same tasks. The
explicit headless CLI generation coordinator retains its isolated child-stage
runner for diagnostic compatibility. That branch is not enabled by the browser.
Developer legacy recipes/review runners remain available; they do not set the
acceptance standard for generated world quality.

Session options replace immutable OS arguments for each world. Slot, seed,
generator, gameplay mode, readonly state, systems and generation timer reach the
existing world/backend setup. Nested jobs save and restore their parent context
only after their world and workers are destroyed. Returning to the selector clears
the override. Saved generator/seed still take precedence over create-screen
settings. Read-only photographs use the existing snapshot policy.

Cancellation is cooperative and joins workers before releasing a destination
lease or restoring session settings. Unpublished staging remains available for
diagnosis/recovery. A cancellation that races completed publication still reports
the retained published world, matching the existing policy. Native snapshot
validation and publication semantics are unchanged.

The visible generation screen retains progress, elapsed/estimated time and
developer details. Photograph refresh exposes its own cancellation label,
destination/loading stages and live world counters in the same window, with an
existing picture as background when available. Offscreen world input/window-close
notifications cannot take ownership of the foreground session. Failed startup
can return to the selector while protecting previous saved data.

## Verification

| Check | Result | Retained run |
| --- | --- | --- |
| Source session lifecycle | 21 assertions; create/play/save/return/reopen, independent modes, readonly pictures/cancel, different-world switch, one native window | `20261024T085740944159Z_session_verbose` |
| Source generation lifecycle | 12 assertions; real production bake cancellation, lease release, generation/play/return and identical native window handle | `20261024T084355590259Z` |
| Exported session lifecycle | 21 assertions; game resources/tasks resolve from PCK/dist; matching offscreen resolution/AA; no cleanup warnings | `20261024T090929516965Z_window_session_flow_pack` |
| Exported generation lifecycle | 12 assertions; full generation, publication, play, save/return, cancellation and unchanged process/window handle | `20261024T091052053333Z_window_generation_flow_pack` |
| Browser policy | Name/seed/save protection, legacy options and UI routing | `20261024T090455444052Z` |
| Generation failure policy | 7 assertions; pre-cancel, lease contention and orphan preservation | `20261024T090455443352Z` |
| Headless CLI cancellation | 6 assertions; child termination, unpublished partial state and lease release | `20261024T085454577338Z` |
| Check launcher | 5 Python tests, including old/new ObjectDB warning formats | `python tools/test_run_godot_check.py` |

The production generation fixture uses seed 1703, generator 19 and a standalone
settlement. It exercises native grading, generated water, twelve buildings,
photographs, map certificates, verification and publication. The phase manifest
records `mode=same_window` and the original process ID. The frame observer checks
the native window handle and native window count throughout the run. Session
checks hash the canonical save before/after photograph capture and cancellation.
The generated scene and the returned selector/loading captures were inspected.
This accepts the window/session transition behavior, not the existing district's
world quality or aggregate runtime performance.

The final PCK starts from its normal main scene with fourteen external native
libraries; `export.log` / `pack_smoke.log` retain the startup result. Package test
manifests include PCK, engine and external-assertion hashes. Native library code
was not changed by this work. Screenshots are evidence of layout/window flow,
not an FPS benchmark; readbacks and cold world setup affect these samples.

## Failures and corrections retained

- `083654…`: test-local inferred WeakRef triggered warnings-as-errors; explicit
  typing fixed the fixture.
- `083717…` / `083852…`: fixture attempted generator 2, which is not an allowed
  browser preset. It now creates a supported generator-4 world after photography.
- `084024…`, `084541…`, `084855…`: functional assertions passed but verbose exit
  exposed zero-reference native helper leaks. These are **not clean acceptance
  runs**, despite the old runner's `passed` field. The helper graph had been
  initialized on a resource-loading thread. Loading that graph on its owning
  thread removed the warnings; source `085740…` and final package runs exit clean.
  The launcher now recognizes Godot's newer counted ObjectDB warning format too.
- `084551…`: browser regression was run without its required developer-preset
  flag. The ordinary UI intentionally has one production preset; the correct
  `--developer-worlds` run passes.
- Initial export startup caught adding the session host to a root still setting
  up its children. Registering it as an autoload fixes normal application startup;
  subsequent exported-main-scene smoke checks pass.
- `090124…_window_session_flow_pack`: an export was mistakenly started while the
  old test still had the dist DLLs/PCK open. The copy was rejected and replacing
  the in-use PCK invalidated later resource remaps in that disposable test. The
  owned test was stopped, then export and package checks ran sequentially. Final
  package checks use one immutable PCK and pass. No such export occurs in-game.

`runs/` retains manifests and ordinary console logs, including failures. Very
large verbose shader logs are represented by bounded diagnostic excerpts; full
originals remain in `reports/checks/` locally. The leak-probe snippets are
diagnostics, not additional acceptance claims.

Test-created save artifacts were moved out of the normal world library into
`user://window_session_checks_20261024/` after acceptance. `fixture_archive.json`
records each original/archive path for recovery. The move used only exact random
fixture identities found in this task's evidence. Move all artifacts for a fixture
back to their recorded original paths to reopen that retained test world.

## Reproduction and limits

Run `python tools/run_godot_check.py window_session_flow --timeout 300
--require 'failures=0'` and the same launcher for `window_generation_flow` with
`--timeout 600`. The tests use uniquely named saved worlds and do not turn a
temporary launcher flag into readonly gameplay. Run graphical checks sequentially.
The browser policy check needs `-- --developer-worlds` for its legacy-preset case.

Export with `tools/export_pack.py --godot <installed engine path>`, wait for it to
finish, then run `python docs/evidence/single_window_session/check_pack.py` and,
after it finishes, the same wrapper with `--generation`. The external assertions
use PCK resources and preserve provenance under `reports/checks/`.

Cold script/native-helper initialization still briefly occupies the main thread;
native long-running work retains its workers. This change does not claim a new
loading-time baseline, interruption of an in-progress native atomic operation,
multihour switching endurance or all legacy developer recipes/hardware coverage.
Existing world-quality, navigation, combined-cost and endurance requirements stay
open in `WORLD_FOUNDATION_STATUS.md`; this implementation closes the requested
single-window player flow.

# Automated checks with separate caches

Use `tools/run_godot_check.py` for in-project Godot checks that use the terrain
backend's command-line cache override. From TerraForest:

```powershell
python tools/run_godot_check.py check_cache_isolation --headless --timeout 20 --require "PASS CACHE_ISOLATION fresh owned directory"
python tools/run_godot_check.py cache_eviction_world --timeout 90 --require "PASS cache completes without write failures or quota overrun"
```

The second command runs the actual graphical world; it is not needed to test the
launcher. Graphical checks use fullscreen 1920x1080 and a 60 FPS cap. Headless
checks provide no graphical performance evidence. Supply additional test options
after `--`, and use `--dry-run` to inspect the command without launching Godot.

Each invocation assigns `user://<test>_<uuid>` as its derived cache, a unique
world-slot argument, and `--temporary`. Conflicting cache, slot and temporary
arguments are rejected. `cache_eviction_world.gd` independently rejects an
existing directory before scene creation and verifies the actual backend path.

This is **not a sandbox or universal save isolation**: a script can ignore those
arguments, use hardcoded paths, or explicitly save. Review each test's ownership
and save policy before running it. The launcher does not change existing tests,
human launchers or default runtime cache policy. It does not restore the normal
cache evicted during the earlier test incident or requalify a warm baseline.

`reports/checks/<UTC>/run.json` records the exact command, Git revision and dirty
files, engine/test/DLL SHA-256 hashes, timeout, process exit and result. Console
and engine logs are retained. Success requires exit zero, requested completion
text in the console, and no recognized error/failure/leak messages in either log.
Assertions and numerical gates remain the test's responsibility. Timeout kills
and waits for the direct engine process; tests spawning child processes must
manage their own children. Interrupt recovery and full process-tree supervision
are not implemented.

Caches and evidence are retained, not automatically deleted. This makes repeated
checks cold by default and can consume disk space; do not treat their timing as a
warm-cache comparison. Use dedicated documented fixtures for cold/warm tests.

Validation: four Python tests cover conflicting overrides, unique roots,
successful completion, missing completion, nonzero exit, console/engine errors,
timeout and launch failure. One short real headless Godot check confirmed native
ownership and complete accounting at the actual fresh cache path. Evidence is in
`docs/evidence/check_launcher`; no full world, GPU or sustained-load claim.

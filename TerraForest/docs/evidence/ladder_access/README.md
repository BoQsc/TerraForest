# Ladder access — 2026-10-11

Place object 7 (Wooden ladder) using M and the object palette. Rotate with R;
place on a supported floor with RMB. Face its front, walk toward it with W,
descend with S, release to hold position, or press Space to jump off. Gameplay
cost is six wood; the world editor remains free. The front is the local +Z side.
The 3.6 m ladder serves approximately 3 m landings. Keep ceiling clearance.

This is one shared baked 168-triangle mesh and a thin solid collision proxy;
rung gaps are intentionally not collision gaps. Native physics-ray lookup uses
the existing collider-to-placement mapping. At most two short rays per player
tick; no ladder placement scan, per-ladder script, dynamic body or Area3D.
Collision streaming uses 64 m radius, 128 bodies maximum, eight builds per tick.
No new save schema: the stable asset key is `architecture/wooden_ladder/v1`.
Removal releases support immediately; reloaded collision proxies restore access.

## Evidence

- `debug/`: 19 focused traversal checks, all passing. The later fixture change
  only adds its JSON summary file for the release wrapper.
- `ladder_traversal_release.*`: the same 19 checks against release player and
  structures DLLs in a clean temporary project. Reuses the existing imported
  wood texture resource; does not rebuild or reimport assets.
- `world/`: 12 create checks and nine fresh-process reopen checks, all passing.
  Normal object tool charges six wood and refuses a second unaffordable ladder.
  Actual world controller climbs onto an editable block landing, saves normally,
  and repeats the climb after normal world loading. Fixture grants six wood;
  gathering is covered separately by the preceding gather/build integration.
- `build.png`, `reopen.png`: visually inspected fullscreen 1920×1080 captures.
  The green cube is an editor selection marker, not ladder geometry.
- `movement/`, `stairs/`: existing movement/swimming and tower stair regressions.
- Build manifests record the pinned prebuilt SDK, Zig and DLL hashes.

The initial world fixture mistakenly used a recipe exchange with empty costs
instead of the grant API, and treated the fixed 32-slot inventory as a sparse
array. It failed before ladder placement; retained in `fixture_failure/`. The
fixture now uses grant and checks each slot count. No inventory runtime change.

The first clean release setup attempted a headless editor import. It completed
texture import but exited nonzero after editor layout loading without a diagnostic;
the cause is unresolved. The wrapper now copies the existing imported texture
and runs the physics test directly, which succeeds. This verifies release runtime,
not a fresh editor import. The failed temporary project was automatically removed.

## Limits

Only upright unit-scale ladders climb; arbitrary editor scaling/tilting remains
ordinary prop geometry. The native controller checks transforms before attaching.
No arbitrary-height ladder chains, side/rear mounting, character climbing animation
or network authority is claimed. Test fixtures disable automatic player physics
and drive the normal controller deterministically; human playability is pending.
The isolated floating floors test access, not building structural support.
Frame caps/screenshots do not qualify sustained 60 FPS or older-laptop thermals.

Reproduce using `tools/check_ladder_world.py`, or the headless
`tools/run_godot_check.py ladder_traversal --headless --require LADDER_TRAVERSAL`.
The release wrapper accepts `--addon player_runtime --test ladder_traversal`.

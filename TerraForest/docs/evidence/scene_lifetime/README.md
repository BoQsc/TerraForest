# Vehicle preload lifetime regression

`trace.log`: full main-scene startup/shutdown, without mining or crafting,
reproduces one leaked RefCounted. Script property tracing did not identify it.
`trace_consumed.log`: same diagnostic, explicitly retrieving the outstanding
vehicle resource request before shutdown, removes the warning.

`fixed.log`: committed `tests/scene_lifetime.gd` runs real startup, verifies the
unused preload is outstanding, drains terrain and verifies tree exit consumes
the request. Four checks pass; verbose shutdown has no leaked-object warning.
`vehicle.log`: existing vehicle placement/entry/exit/persistence test, 19 checks
pass; no leaked-object warning.
`gameplay.log`: existing full gameplay test, nine checks pass at fullscreen
1920x1080 with a 60 FPS cap. No leaked-object warning. Vulkan loader errors name
missing Epic overlay JSON files; these are separate from the fixed lifetime bug.
Updated screenshot: `../gameplay_scene/inventory.png`.

The adapter now pairs each accepted threaded request with a get on use or exit.
If a resource is still loading at early exit, shutdown waits for that load.
These are bounded functional checks, not sustained performance or memory tests.

# Regional water integration evidence — 2026-10-11

The actual-world test passes **34 assertions in 28.21 seconds**, at fullscreen 1920×1080 with the 60 FPS cap. It loads the normal world, creates its lake, proves sleeping water does no cell work, drives real bucket clicks, digs a separate real terrain hole, pours and recovers one litre, mines an outlet, verifies exact water conservation, saves through the ordinary world archive, reopens the disk world and removes water with the developer brush.

`gameplay.json`, `gameplay.log` and `gameplay_run.json` contain assertions, measurements and source/binary provenance. The two PNGs were inspected. They show filled shallow water in the forest; the 0.5 m shoreline remains visibly stepped and is not final art.

Measured on **NVIDIA GeForce RTX 4050 Laptop GPU**, with no simultaneous game:

| Observation | Result |
| --- | --- |
| Gameplay water total conserved through bucket/mining/save/reopen | 514,832,000 ml |
| Cached moving-world regions restored | 58 |
| Warm terrain density samples / cached region rebuilds | 0 / 0 |
| Maximum native flow slice before save | 1.187 ms |
| Maximum native regional mesh-array build before save | 0.375 ms |
| Whole-frame median / p95 / maximum during sampled gameplay | 16.664 / 17.709 / 49.620 ms |
| Whole-viewport GPU median / p95 / maximum | 5.048 / 6.116 / 7.138 ms |
| Cold water preparation after creation | 3.030 s |
| Outlet excavation request to wet downstream probe | 3.225 s (includes terrain publication and flow travel) |
| Saved complete-world reopening in this fixture | 6.583 s |

These are short-run observations, not controlled improvements over older hardware. The frame maximum means this is **not** a hitch-free 60 FPS qualification. Native flow timings exclude terrain-worker work, script coordination, save capture and GPU uploads. The GPU times cover the whole viewport, not water alone. Current cold preparation and total world loading are not instant.

## Independent application restart

`preparation_run.json` and the `preparation_cold.log` / `preparation_warm.log` pair verify the preparation workflow in two independent processes. Cold headless preparation and verified saving completed in 24.80 s. A fresh graphical process loaded the prepared world and completed its check/shutdown in 10.04 s. It restored **48 cached regions**, with **zero sampled nodes, zero cached-region rebuilds, zero active cells and zero flow-cell steps**, and published the saved surfaces before gameplay admission. Process wall time includes engine startup and shutdown.

Both debug and release extensions were built against the pinned Zig/prebuilt godot-cpp SDK without compiling godot-cpp. The clean-project release `water_network` regression also passed all 277 legacy native assertions; that suite protects retained reference code and is not presented as proof of the new regional model.

## Retained failures and corrections

The `failures` directory keeps failed actual-world runs. They exposed and/or clarified:

- Headless Godot does not provide captured mouse mode for the actual mouse-input acceptance path. The acceptance runner is graphical.
- Sub-millimetre relaxation and insufficient mesh publication kept unnecessary work active. A 1 mm head tolerance and a shared capped regional publication budget address the reproduced churn. Flowing water is verified by published outlet geometry, not by requiring all fluid motion to stop.
- Queued dry cells carried an awake bit into a save and failed the decoder. Capture now writes awake state only for cells owning water.
- Sampling of newly reached or unfinished flow regions was initially conflated with rebuilding a valid saved cache. Native telemetry distinguishes those cases. The final gameplay run and independent prepared restart both happen to need zero samples on reopen.
- A terrain ray endpoint could fall inside a conservative solid shoreline cell. Pouring now selects nearby open space along the unobstructed segment without debiting a bucket before preparation succeeds.
- A one-litre puddle requires an analytic surface crossing and locally connected multi-cell scoop. The test aims at its actual settled surface. Mouse capture can synchronously reset the test camera to the player's pitch; the fixture now establishes its precise aim after capture. No gameplay input gate was bypassed.

The original fixed-basin edit guard is gone. Remaining scope limits—structure occupancy, shoreline refinement, wet-region paging, large-body pressure/flow behavior, scale and endurance—are listed in `../../WATER_GAMEPLAY.md` and the project plan. This evidence closes the tested gameplay/cache loop, not the full original world-engine scope.

Final generation review: the two-assertion connectivity regression passes. Adjacent cells with disjoint air intervals cannot fill across solid terrain; a genuine shared opening fills both with exact capacity. The full 34-assertion world check and independent preparation/restart pair were repeated after this correction.

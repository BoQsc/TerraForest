# Mining review capture overhead — 2026-10-18

Fixed-cap 1920×1080 checks on resource_mine_42_20261018, read-only, sequential
processes. Stationary lake profiling did not reproduce the earlier runtime problem:
frame p95 16.77 ms, max 16.81 ms, GPU around 6 ms. The existing lake check now accepts
profile 13 and queries the actual loaded generator rather than hardcoding 12.

Optional per-frame mining profiling then found a 572.73 ms interval between iron
and copper viewpoints; ordinary strikes and settlement frames stayed near 16.7 ms.
The test saves an image between those viewpoints. A targeted capture/no-capture
comparison measured the first readback/PNG save at 565.56 ms and the second at
234.69 ms. The capture run's non-startup maximum was 586.43 ms; removing captures
gave max 21.32 ms, p95 16.78 ms. Both gameplay correctness checks passed.

Raw frame rows and summary are retained. Phase labels are sampled at process_frame
and can reflect the next operation: the capture pause appears under travel_9. The
explicit capture timers identify that synchronous cost. Engine process/physics
monitors also update less often than these per-frame intervals; do not attribute a
single interval solely from those monitor values. The second capture occurs before
shutdown and is recorded by its timer, not a subsequent gameplay frame sample.

Profiling now omits image capture by default. --ore-profile records frame/stage/GPU
data; ordinary visual runs still capture. --ore-capture-with-profile deliberately
reenables captures for this diagnosis, and --ore-no-capture always suppresses them.
The retained comparison ran before this default change, with --ore-profile in both
runs and --ore-no-capture only in the second.

This explains the measured large pause in the staged mining review and can depress
the following screenshot's rolling HUD FPS. It does NOT resolve earlier lake
spikes, exclude other gameplay hitches or qualify sustained 60 FPS. No production
renderer, mesh budget or world simulation behavior was changed by this diagnosis.

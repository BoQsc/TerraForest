# Mixed-world actor cost — 2026-10-15

Original mixed preparation staging source
`combined_stage_7801173ed84740ee91a1b06e51a3298b` was cloned exclusively; source
canonical hash remains unchanged. Eight furnished buildings, connected roads,
forest and ground cover use the normal world. Godot 4.7.2, Vulkan Forward+,
RTX 4050 Laptop GPU, 1920×1080 fullscreen, 60 FPS cap.

The existing actor_population_cost fixture waits for 60 idle frames then measures
120 observations each at 0,16,64 nearby records. Native activation remains capped
at 16 physical actors. The fixture manually ticks the normal actor adapter while
player physics is disabled. It is not a live multiplayer or 64-active-body test.

| Phase | Actor p95/max ms | Collision p95 ms | Frame p95/max ms | GPU p95 ms |
|---|---|---|---|---|
| Empty | .068 / .176 | 0 | 16.959 / 24.374 | 5.924 |
| Moving 16 | 1.177 / 3.082 | .758 | 17.201 / 18.706 | 5.950 |
| Nearby 64 | 1.306 / 1.697 | .831 | 17.082 / 19.576 | 5.961 |

Result FAIL: actor p95 exceeds 1 ms in both populated phases; moving16 maximum
also exceeds 2 ms. Fixed body count and zero collision-readiness holds pass. The
existing 18.5 ms frame-p95 fixture gate passes, but is looser than a strict
16.67 ms deadline. Nearby64 visited 30 distinct actors through 30 activation
entries; it did not simulate every stored actor. No sustained or thermal claim.
Startup also logged a 157.73 ms terrain receive hitch outside the sample window.

Decision: retain the current active limit. Do not increase it based on the 60 FPS
HUD or the storage count. Further active-population work must address measured
collision/movement cost and activation turnover with fixed comparable content;
do not rerun this short sample to average away its failure. Water remains deferred.

The reusable runner accepts a source slot, preserves the source and retains raw
measurements on failed gates. Subsequent runs also record host/test/native hashes;
this initial run predates that extra metadata and records Git state and GPU/engine
console identity. Script syntax verification passed. No runtime behavior changed.

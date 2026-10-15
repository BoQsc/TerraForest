# Actor benchmark physics cadence correction

The previous fixture awaited a physics frame, manually updated actors with
1/60 second, then awaited rendering. It could skip intervening physics ticks
when rendering ran slower than physics, and used the wrong delta at other
physics rates. Do not treat previous measurements as complete per-frame actor
cost under those conditions.

The fixture now uses a Node physics callback and the engine-supplied delta.
Every actor update between rendered frames is retained and summed into that
frame's actor budget. Individual tick timings, tick counts and configured
physics frequency are recorded. Normal player/world physics remains disabled
to prevent double integration; this is still a controlled actor fixture, not
a complete gameplay benchmark. Runtime movement code and capacity are unchanged.

Run 20261015T184638835190Z completed with five failing budget gates. The empty
control already rendered at approximately 15 FPS, so these results cannot
establish a performance regression or improvement against the earlier 60 FPS
run. The controller's background cap is 15 FPS, a plausible cause; window focus
was not recorded, so the cause is unconfirmed. All three
phases recorded exactly four physics callbacks per rendered frame, each with
delta 1/60, at configured 60 Hz: 480 updates per 120-frame phase. The old
fixture would have submitted only 120 updates in this condition.

| Phase | Actor/frame p95 / max ms | Frame p95 ms |
|---|---|---|
| Empty | .157 / .223 | 68.239 |
| Moving16 | 6.074 / 8.914 | 70.410 |
| Nearby64 | 5.294 / 7.311 | 70.124 |

Both populated phases fail the unchanged actor budget; all frame gates fail.
Body cap 16 and zero readiness holds pass. Nearby64 visited 56 actors over
73 activation entries. These longer simulated durations must not be compared
as equal travel workloads with the earlier fixture. No claim of 64 active
actors, thermal sustainability or long-run readiness is made.

The source was cloned from the original mixed-neighborhood staging save;
the source hash stayed unchanged. Water was untouched. An earlier attempt
20261015T184543466102Z exited normally before the completion marker, producing
no usable measurement; its report remains under reports/mixed_actor_cost.

Next: establish comparable foreground rendering conditions before assessing
movement optimizations. Preserve these failures; do not increase actor capacity.

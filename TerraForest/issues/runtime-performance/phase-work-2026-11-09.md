# Separating frame CPU work and waits

Status: diagnostic improvement; stalls and stable 60 FPS remain open.
Implementation: `105acaaa`. [Exact receipts](phase-work-2026-11-09.json) include
both controls, raw hardware telemetry, failed/unavailable attribution scope and
the current package. Continues the [native water batch](navigation-water-batch-2026-11-09.md).

## Rolling capture

The opt-in recorder now pairs its before-process, process, after-process and draw
wall intervals with main-thread cycles and quantized CPU time. It separately sums
measured SceneTree physics callbacks, including catch-up ticks. These physics
intervals overlap the other intervals; engine work outside those callbacks is
not included. Samples off the main thread, failed counters and reversed readings
are omitted, never reported as zero CPU work. Probe time is included in the
reported recorder overhead. This changes diagnostics only, not graphics,
simulation, navigation budgets or gameplay permissions.

Focused recorder checks and all three analyzer tests pass. The final packaged
capture has **2,091 complete phase rows with zero cycle-sum mismatches** and
2,079 rows containing physics work across 2,178 ticks. The earlier diagnostic run
predates the explicit main-thread guard and is retained separately. Its arrival
image is unreviewed; both final on/off arrival images were inspected.

## What the finer measurements establish

The final capture contains 1,510 unique triggered gameplay frames: p99 **23.077
ms**, maximum **34.590 ms**, mean root GPU time **15.367 ms**. These are trouble
windows, not an unbiased whole-session distribution. Three samples distinguish
different kinds of cost:

| Frame | Observation | Main-thread cycles in that interval |
| --- | --- | ---: |
| 2140 | 34.590 ms frame, including 29.210 ms draw | 20.979 million draw cycles |
| 2404 | 32.327 ms frame, including 8.632 ms save capture and 17.356 ms draw | 26.627 million process / 42.253 million draw cycles |
| 2405 | 28.904 ms frame, including 12.229 ms measured physics | 30.472 million physics cycles |

The first long draw interval contains relatively little thread work compared with
the other intervals; the physics outlier contains substantial CPU work. Raw cycles
are not milliseconds, and GPU timers can lag. These observations do **not** name
a mutex, wait owner or individual physics subsystem. The existing stage timers
cover only part of that physics interval, so zombie body animation/posture/hit
shapes and other callbacks need direct attribution before choosing a rewrite.
The previous Windows scheduler-capture attempt failed with `0xc5585011`; no
scheduler trace has been acquired and no system policy was changed.

## Recorder-off and hardware control

Two serial packaged runs use fresh owned copies of the same retained default
world, identical quality, and root GPU timing enabled in both. The observation
driver now retains continuous GPU/render-CPU/draw-count samples even when the
rolling recorder is off. Both runs save and shut down successfully without strict
diagnostics or sampled resource-budget failures. The inspected first-person
arrival captures retain the doorway, furnishings, held pickaxe and UI.

| Continuous phase | Recorder on: frame p99 / GPU mean | Recorder off: frame p99 / GPU mean |
| --- | ---: | ---: |
| Arrival idle | 25.100 / 16.046 ms | 24.358 / 15.410 ms |
| Turning | 19.871 / 14.789 ms | 19.946 / 14.634 ms |
| Settled idle | 19.997 / 14.585 ms | 20.473 / 15.012 ms |

The recorder-off run still reaches **32.034 ms** in settled idle and **29.651 ms**
during the save phase. The on run retains an extra three-second manual-capture
wait in settled idle; sample lengths differ. These serial, variable hardware
conditions do not isolate exact recorder overhead. Its own measured callback and
probe elapsed time averages 277 us, p99 432 us, maximum 965 us, excluding some
callback/stage overhead and potentially including descheduling.

One-second device-wide NVIDIA samples cover both controls. A separate sample
**during recorder-off gameplay at 15:58:47 UTC** reports **software power cap and
software thermal slowdown active**, P3, 1,200 MHz graphics / 7,001 MHz memory,
17.40 W and 97% GPU utilization. Windows reports AC power and battery saver off.
This is a confirmed driver-reported limiting condition, not proof that all
previous stalls share that cause. Earlier ~7.9 ms GPU runs have no simultaneous
clock/limit telemetry, so the near-doubling cannot be attributed precisely.
Polling is external and device-wide; it includes other host workloads and can
perturb measurement. No clock, power, fan or quality setting was changed.

The high GPU cost and frame tails persist without the rolling recorder. Future
rendering comparisons must retain device clocks/limiting conditions and separate
CPU-heavy callbacks from draw/presentation waits. Hardware limits do not excuse
remaining code costs or establish sufficient headroom on slower machines.

## Installed checkpoint and remaining work

PCK: **556,866,492 bytes**, SHA-256
`2640664aea5524cadf13beda980202e4520531e7609b51c347be23dedfb9c402`.
All 14 source/dist native DLLs match and retain the prior lifetime repair. The
export and final on/off saves/shutdown pass; this is not leak-endurance acceptance.

Next requirements: directly attribute the unmeasured physics work; reduce save
capture and rendering/submission costs; obtain scheduler/wait-owner evidence when
the profiling prerequisite is available. Cold regional pursuit still needs fewer
sampled candidates/prepared connectivity with physical and dynamic-edit validation.
Existing cut-cell and interaction-fixture failures, dense destruction/crowd scale,
long-session stability and stable 60 FPS with headroom remain unresolved.

Raw reviewed captures (paths/hashes/captions are retained in the receipts):

- `reports/performance_changes/20261109T155712534546Z_phase_guard_on/arrival.png`:
  recorder-on normal first-person arrival; no scoped visual reduction observed.
- `reports/performance_changes/20261109T155818654983Z_phase_guard_off/arrival.png`:
  recorder-off control of the same house and equipment; no scoped visual reduction.

New diagnostic code is original 0BSD work. Existing Windows/NVIDIA utilities were
used externally; no third-party material was imported. This is engineering review,
not user approval of world quality.

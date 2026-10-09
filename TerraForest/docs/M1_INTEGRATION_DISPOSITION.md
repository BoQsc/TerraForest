# M1 disposition and transition to world-content coverage

2026-10-09. M1's integration decision is closed: keep model paging available through
`--model-region-paging`, retain the current default/human launcher, and advance to
M2 world-content coverage. This is a scheduling and supported-path decision, not
completion of loading, mining, large-world performance or the original project.

## Populated main-world check

`tests/model_world_route.gd` creates an isolated persistent world with 768 placements
across the existing beam and doorway assets at three separated locations. Each
location has 128 placements per asset. It saves through the normal terrain worker,
reloads metadata, visits near/far/return destinations, edits a streamed placement,
saves and reloads again. No scheduler calls or artificial drain loops bypass the
normal main-world coordinator.

The strengthened run passes 27 checks. A physics ray must resolve the expected
stable placement ID. After settling, each asset has only the destination's 128
records resident; the other 256 remain unavailable with saved backing. Screenshots
show the actual rendered fixture. It is repeated elevated geometry over terrain,
not authored houses, a forested city or representative interior detail.

| Phase | Model arrival ms | Frame p95 ms | Frame p99 ms | Frame maximum ms |
| --- | ---: | ---: | ---: | ---: |
| Near | 51.595 | 17.719 | 18.212 | 18.507 |
| Far | 301.518 | 16.874 | 17.228 | 21.099 |
| Far after edit/reload | 306.635 | 18.310 | 19.184 | 20.001 |
| Return | 301.207 | 16.979 | 17.393 | 17.739 |

Gates were specified before running: arrival <=1,000 ms, frame p95 <=18.5 ms,
p99 <=25 ms, maximum <=50 ms. Arrival measures the first target model collision
and render-residency condition; it is not whole-terrain arrival. Timed intervals
include arrival plus two seconds, and exclude screenshot capture. Initial creation,
save and reload waits are outside those frame samples. Teleport destinations stress
arrival; they do not model continuous high-speed vehicle movement.

Configuration: Godot 4.7.2, Forward+, RTX 4050 Laptop GPU, 1920x1080 fullscreen,
100% scale and 60 FPS cap. Short frame-tail gates are not sustained 60 FPS or
thermal qualification. Debug extension build was loaded by this editor engine.
The initial, weaker collision-readiness run is retained separately; the final
test uses real physics hits and explicit resident-count checks.

Reproduce with `python tools/check_model_world_route.py`. It uses a unique save
slot and retains timestamped reports, screenshots, command and source hashes.
[Recorded evidence](evidence/m1_disposition/).

## Mining failure remains open

The existing `held_mining_flight.gd` check ran against the current default terrain
path, without `--region-terrain`, in a separate temporary world. Two three-second
held-input bursts after scripted relocation produced 18 and 24 visible changed
draws. Capture-to-draw p95 was 113.304 and 114.457 ms; frame p99 was 17.396 and
17.551 ms, with no frame above 50 ms. However, the maximum visible-change gaps
were **328.442 and 280.697 ms**, failing the unchanged 150 ms continuity gate.

This establishes a remaining interaction failure despite acceptable short frame
timing. It does not establish its cause, long-session scaling, or a fix. The short
fixture is not a new far-distance/endurance qualification. Logs, raw frame data,
failed checks and build identity are retained. This known gap follows the user's
earlier decision to resume planned world work rather than indefinitely optimize
mining; new regressions that prevent ordinary play still take priority.

## What returns, and when

- Model paging stays opt-in. Reassess default activation with M2 detailed buildings
  and vegetation and M4 mixed travel, including actual arrival/collision and frame
  costs. The prior 200,000-record transfer timing failure is still open.
- Re-run the mining continuity route at the combined M4 checkpoint, or sooner if
  loading/interaction changes touch that path or a human checkpoint finds a blocker.
- M2 now targets a reproducible saved-world workflow with generated geology/lake,
  connected roads, a usable building/interior, vegetation variety and settlement
  generation. A hand-authored example does not close settlement-generation coverage.
- Preserve multiplayer-facing identity, command and persistence boundaries during
  this work; actual networking remains later. No license or dependency change.

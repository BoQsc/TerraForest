> Follow-up: ../actor_crowd_timing/README.md corrects frame measurement and
> reopens continuous-physics arrival qualification (14/16). The evidence below
> remains historical, including screenshot overhead in its worst interval.

# Sixteen-actor crossing and arrival policy, 2026-10-15

The two-actor check was expanded to the normal active cap of 16: eight lanes
spaced 0.8 m apart, with opposing 12 m routes on the original furnished settlement
street. No position correction or direct velocity injection is used by the test.
All runs use copied saves; canonical source hashes remain unchanged.

The first run exposed arrived actors drifting under avoidance and four incomplete
arrivals. Preventing movement when a route requests rest improved arrival to
14/16, but moving agents still expected stopped agents to share avoidance work.
The native actor now assigns stopped/unready agents priority 1.0 and moving agents
0.5. Stopped bodies retain zero horizontal motion, and neighbours take avoidance
responsibility. Priority changes occur only on movement-state transitions. No
save-format change or extra body allocation.

| Run | Arrived | Minimum separation | Frame p95/max ms | Adapter p95/max ms |
| --- | --- | --- | --- | --- |
| Before | 12/16 | 0.786 m | 17.975 / 760.073 | 1.082 / 1.564 |
| Hold only | 14/16 | 0.708 m | 17.696 / 602.844 | 1.076 / 1.998 |
| Hold plus priority | 16/16 | 0.786 m | 37.346 / 632.554 | 1.205 / 2.672 |

**The final run still fails overall.** Correctness improved, but frame p95 exceeds
18.5 ms and adapter p95/max exceed 1/2 ms. These unchanged gates were declared
before the initial run. Do not infer performance regression causality from this
sequence: it lacks an interleaved controlled baseline. Final GPU p95/max were
6.121/7.189 ms; adapter timing excludes deferred engine avoidance work. Frame
timing includes the full world and the test's separation probes; saves and
hundreds-of-milliseconds stalls occurred and remain in the data.

The 720-update test waits for physics and render completion, manually invoking
the same actor adapter with 1/60 s steps. It therefore represents 12 seconds of
actor simulation, not necessarily 12 seconds of wall time. The first 60 cost
rows are excluded as warm-up; both moving and arrived actors remain measured.
This is not an endurance, thermal, older-device or large-population qualification.

`stationary.log` separately proves zero horizontal drift while another actor
passes, separation and arrival. `release_crossing.log` verifies opposing crossing
with the rebuilt release binary. Three runs' logs, manifests and compressed raw
motion/cost rows are retained here. `crossing.png` is the actual 1080p settlement
view; the source save remains unchanged.

Reproduce with `python tools/run_actor_street_crossing.py --crowd`. Exit status
stays nonzero when either correctness or cost gates fail. Next cost investigation
must distinguish actor adapter sub-costs, deferred engine avoidance and unrelated
world-frame stalls before changing the simulation or claiming headroom. Narrow
opposing doorways, large crowds and moving targets remain separate coverage gaps.
Water was not changed.

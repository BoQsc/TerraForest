# Separate route startup from contact movement

Run 20261015T185812961694Z, same immutable mixed-neighborhood source cloned
exclusively. Source hash unchanged. Runtime code, terrain collision, readiness,
physics cap and graphics remain unchanged. This is a benchmark correction,
not a movement or performance fix.

The preceding comparison started its two-second travel clock before route
planning. Sixteen 12 m routes each validate 24 half-metre segments through a
shared planner capped at twelve work units per physics tick. Waiting until a
route is validated is intentional. The previous 3.3–3.6 m travel result did not
separate this startup time from actual locomotion.

Comparison phases now retain all startup tick timings, require all sixteen
routes to become usable within one simulated second, capture each actor's
actual movement origin, then measure two seconds of contact movement. The
normal 0/16/64 population test remains unchanged and includes startup cost.
Earlier failed end-to-end results remain in actor_contact_comparison; this
does not retroactively pass the old two-second-from-order expectation.

| Phase | Startup seconds | Subsequent travel m | Actor p95/max ms | Motion p95 ms |
|---|---|---|---|---|
| Terrain A | .550 | 4.724–5.002 | 1.178/1.527 | .859 |
| Box | .533 | 4.751–5.002 | .724/1.438 | .331 |
| Terrain B | .550 | 4.764–5.044 | 1.898/2.438 | 1.360 |

Startup and >4 m grounded movement checks pass in every phase. All sixteen
physical actors remain active with no collision-readiness holds. Both terrain
phases still FAIL the existing actor cost gate; the box phase passes. The
terrain B frame maximum is 42.497 ms despite its passing frame-p95 gate.
No sustained 60 FPS, larger population or laptop thermal claim follows.

Conclusion: the distance shortfall is accounted for by route startup in this
case. Do not change movement speed or bypass validation to make that old
measurement pass. Terrain contact remains the demonstrated optimization target;
any collision change must retain editable terrain, stairs, obstacles and loading
safety. Water remains deferred.

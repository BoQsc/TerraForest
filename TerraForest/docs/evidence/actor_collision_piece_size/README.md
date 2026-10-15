# Actor contact: collision piece size decision

2026-10-15. Compare the existing supported 256 and default 1024 triangle recipe
sizes in exclusive clones of the same immutable mixed-neighborhood source.
Two short sequential 1920x1080 fullscreen runs, fixed active/background cap 60,
actual physics callbacks, with route startup separated from contact movement.
No runtime code or collision surface geometry changed. The fixture configures
the existing backend option before its worker starts and verifies the resident
maximum piece size. Source hashes remain unchanged.

| Setting | Resident shapes | Triangles | Engine static bytes | Terrain A/B actor p95 ms |
|---|---|---|---|---|
| 256 | 814 | 190774 | 317674493 | 1.096 / 1.569 |
| 1024 | 252 | 190774 | 315455997 | 1.501 / 1.292 |

Both runs FAIL both terrain actor cost gates. Startup, >4 m grounded movement,
fixed 16-body cap and zero readiness holds pass. Box controls pass actor gates.
Frame p95 passes the existing 18.5 ms gate, but terrain B maxima are 60.95 ms
and 55.49 ms respectively. These are not sustained 60 FPS passes. Engine static
memory is not total process memory or VRAM. Sequential order, system scheduling
and cache state remain uncontrolled; no statistically established speedup.

Decision: retain production 1024. Smaller pieces change the two terrain phases
in opposite directions and require over three times as many resident shapes.
This does not justify a global default change or a new collision implementation.
The previous geometry census found no exact ordered duplicate triangles in its
four route candidate pieces; that narrower observation does not prove absence
of all overlap elsewhere. Two-sided collision remains intact.

The benchmark accepts --collision-piece-triangles 256|512|1024 for future
reproduction. Do not continue tuning automatically: the current actor cost
limit is recorded, active capacity stays 16, and any later collision redesign
must justify its terrain-edit, cave, stair and loading correctness costs.

Next coverage deliverable: an integrated underground exploration and material
gathering checkpoint using existing generation, normal inventory rewards and
save/reload. This moves toward original scope while the actor budget remains
explicitly unresolved. Water stays deferred.

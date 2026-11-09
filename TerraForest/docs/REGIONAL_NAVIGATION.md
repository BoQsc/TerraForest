# Regional surface navigation

Selected walking journeys verified, 2026-10-23. This extends
`NAVIGATION_STANDARD.md`; broader coverage and performance remain explicit gates.

`NativeActorNavigator` now owns a shared, derived surface graph for its external
characters. Nearby level targets retain `ActorRoute`; targets farther than 12 m,
different storeys, or local searches encountering an obstacle use the regional
graph as soon as their first graph expansion begins. Direct corridors stay local. Both tiers
use the identical native support, capsule sweep, step and hazard evaluator. Standing zombies explicitly use their controller's 45-degree floor capability
(normal Y >=0.7072); legacy walkers and crawlers retain >=0.85. A physical 32-degree
ascent/contact and rejected 46-degree ascent qualify the standing profile boundary.
There is one physical body/motor owner. No generator recipe or saved world schema changes.

Before expanding the graph, a regional query now validates a complete straight
corridor in half-metre quanta with the same native evaluator. It publishes no
partial path; obstruction switches to graph search and missing coverage remains
unavailable. The 96 m X/Z domain bounds the corridor to 273 positions. This
avoids graph work for open slopes/distant line-of-travel targets. Standing
external routes use the physical 0.24 m body radius with conservative 1.8 m height;
legacy settlement routes remain 0.35 m and crawlers 0.75 m. Their dry-footprint
checks and all work/node/deadline caps are unchanged.

The graph is sampled from live collision, not inferred from building names or
road artwork. Vertices retain supported height as well as X/Z and profile.
Coincident horizontal positions on separate floors or inside/beyond a cave roof
are distinct vertices. Discovered walking edges connect spatial tiles and height
bands. These are geometric portals, not semantic room/floor identifiers. Stairs
and cave ramps must pass the actual walking contract; ladders, unsupported drops
and jumping remain separate capabilities and are not silently authorized.

Open space uses up to 2 m links. Each work quantum validates only one supported
half-metre segment; a height change or obstruction shortens/refines the link.
An exact-position root connector can extend 1.061 m to an aligned neighbouring
cell (at most 108 hazard samples); all use bounded support and capsule checks.
Goal connectors are validated incrementally too. Best-first search scores cost
plus 1.25 times (horizontal distance + height weight times height difference).
The height weight is 16 for an upstairs goal and 2 otherwise, so finding a cave
entrance can first climb a ridge without flooding every lower outdoor surface.
Height guidance prioritizes discovering the recipient's connected storey rather than flooding an
outdoor plane underneath it. This heuristic is not admissible and does not promise
an optimal/shortest path. It still requires a complete supported path to the real
destination. A failed query has no direct-chase or projected-horizon fallback.

The shared graph retains at most 32,768 vertices. Each query retains at most
16,384 search nodes, within +/-96 m horizontally and +/-64 m vertically of its
start. Water footprint checks call the native water owner directly, preserving
the same
feet+10 cm dry-ground policy without repeated script forwarding. Optional custom
admission remains an additional gate. The service shares twelve local or up to
48 regional work quanta and a
cooperative 750 us deadline per tick. More regional quanta use otherwise idle
time inside the same deadline; they do not authorize unlimited collision work.
Planning may reuse positive readiness for containing4m-aligned boxes, at most128
entries during one synchronous pass. Callbacks must report the whole input volume
and remain pure. A larger-box miss falls back to the exact query. The cache is
discarded between passes; actual motion guards always ask live providers.
Local geometry/water publications invalidate intersecting graph certificates
and query envelopes. Each certificate includes the actual support-ray, hazard
footprint and capsule/sweep bounds, including failed candidates and partly built
links. An 8 m spatial index finds possible sources; a conservative maximum
dependency extent covers tall sampled geometry. Incoming edges to retired
vertices reset before bounded free slots can be reused. Generation checks reject
stale query references. Unaffected complete paths and cached edges remain usable.
The support-ray cache still changes generation on every publication.

Callers must publish the union of old and new affected geometry in world space.
Empty, malformed or unbounded notifications remain global barriers. Recipient,
water-provider and conditional-door policy changes also remain global. Native
block edits now preserve their changed-cell bounds through the world and trader
hosts; model/tree notifications without reliable bounds still reset globally.
Live collision readiness and movement guards remain mandatory. Query envelopes
are conservative unions, so some unaffected queries may still restart.

Graph storage remains capped at 32,768 slots. Certificates increase each native
vertex from 176 to 384 bytes in the pinned build: at capacity, 12 MiB of vertex
storage, plus bounded indices/free slots and the existing 3 MiB ray cache. Broad
edits can scan every live vertex synchronously; this is measured work, not a hard
deadline. `invalidation_stats()` exposes live/allocated/free slots, scanned and
retired vertices, reset edges/queries, duration and cumulative event counters.
Opt-in query profiling includes these in the existing rolling physics trace.
Final path reconstruction, query reset, physics calls and script callbacks can
overrun the deadline; it is not a hard frame-time guarantee.

Up to eight interest points retain encounter bodies and missing frontier columns.
The host admits interests within 96 m of the player, refreshing at most four times
per second. Terrain adds them alongside existing player/travel/interaction requests
without changing player focus. Block and model collision receive small additional
interests; their existing body, shape, publication and memory limits remain.
Primary player model proxies have priority. Existing saved block/model paging
already covers 384 m; this feature does not widen that archive residency domain.
Capacity pressure must remain unavailable, not falsely empty geometry.

Only resident, closed, unprotected wooden doors (at most 64) become conditional
planning portals. Planning queries may omit their specific RIDs; movement guards
retain those RIDs and stop at the intact door. Perception follows the routed
approach on the current storey, creates a validated attack target and uses the
existing authored-contact/durability/removal policy. The conditional plan never
authorizes walking through the leaf. Other walls, floors, protected objects and
unbreakable doors remain solid. Encounter suspension releases interests; unready
living bodies retain identity while waiting for publication.

A moving-goal refresh can continue to the next already-validated waypoint from
its previous complete path, within 2.5 m. The replacement plans from that fixed
join, so the body cannot outrun its new start or be sent back to the old one.
New partial paths remain unpublished. At the join it waits for the full query.
Relevant geometry or global profile/exclusion/water invalidation clears continuation; unavailable or
failed routes stop it, and every retained step still checks live motion safety.
Physical blockage releases the retained point after one second. Keeping a query
alive through a brief hit reaction avoids rebuilding it after the animation.
This reduces refresh interruptions; it does not improve the cold tower frontier
or establish a bound on complex first-route latency.

Regional moving targets keep their committed search while it plans, then refresh
after four metres of progress or on the final approach. A storey change can
retarget earlier. This avoids restarting a large search every pursuit tick.
The 2026-11-05 pursuit rework also preserves unfinished local queries and shares
obstacle sampling early: a twelve-second ten-body moving-goal fixture improves
from 0/10 moving to 10/10. Normal-perception moving-player checks pass in furnished
rooms and the actual owned mine; source/executable receipts are in
[the zombie issue](../issues/zombie-aggression/README.md). Longer continuous
moving-target endurance remains an explicit acceptance gate.

Selected evidence is complete in [regional navigation evidence](evidence/regional_navigation/README.md):
actual saved tower and cave round trips, closed-door clearance/destruction, edited
and unavailable topology, native debug/release fixtures and inspected images.
The standing motor uses the actual capsule radius, swept30cm steps, verified
front/foot-centre treads and floor snapping. Gravity cannot undo a verified riser
advance; no jump, unsupported traversal or wall/ceiling bypass is authorized.

Cold queries still take roughly10-17s in the selected outbound cases. Faster cold
planning, full96m pressure/travel, broader owned-mine layouts and seeds/buildings,
continuous moving-target endurance and heterogeneous crowds remain unqualified.
Automatic ladder/jump links and tight crawler passages need separate capability
and interaction checks. Door removal still needs fresh-process compound persistence.
These cases do not qualify the whole2km world, large populations, sustained frame
time, historical district/cave art or arbitrary third-party buildings.

2026-10-29 regression check: the current `regional_navigation` synthetic tower
fails its upper-floor and separate-storey assertions on both baseline `87afcdfe`
and the readiness-index update. The historical journeys above are not current
qualification of this fixture. Return to its present tower geometry/support and
route trace; require the full fixture and actual street-to-floor journey to pass.
[Comparison receipts](../issues/runtime-performance/README.md).

2026-11-05 recheck: the same tower assertions still fail (18 checks / 2 failures)
with both the pre-pursuit-change native library at `510c3a15` and the current one.
The ninety-second query remains planning below the first floor. This remains an
open support/frontier investigation; the short mine/room pursuit passes do not
qualify it. Comparison reports are retained in the zombie issue evidence.

2026-11-09 support correction: the actual furnished tower fixture now passes
18/18. The former midpoint-first support check combined two legal 25 cm risers
into a forbidden 50 cm rise at aligned half-metre waypoints. Sampling every
individual tread in travel order fixes that topology error. Dense 2.5 cm support,
30 cm steps, slope/capsule/hazard/readiness checks and scheduling caps remain.
The new `navigation_treads` fixture reproduces three failures before the fix and
passes all 12 checks after it, including rejection of a genuine 50 cm riser.
The cold tower query still needs 1,068 physics ticks (17.8 seconds) and 314
expansions in the first corrected debug run. Live capsule-clearance failures now
also use bounded rejected-waypoint memory; actual conditional door RIDs preserve
their authorized approaches. The renewed saved-tower journey passes 13/13 with
door destruction, both flights, attack contact and return, and preserves all
200 source files. Cold outbound/return queries still take 35.2/45.0 seconds in
the full host. Faster first routes remain an acceptance gate.
Current receipts are linked from [the performance follow-up](../issues/runtime-performance/foundation-2026-11-09.md).

2026-11-09 query-cost follow-up: exact downward-ray reuse now shares a fixed
65,536-entry / 3 MiB numeric cache per navigator. Keys include the full ray origin
and endpoint height, with no position quantization. Entries belong to the graph
revision and the navigator's shared mask/exclusion policy; all existing graph
invalidations also invalidate support reuse. Coverage, every dense support
sample, hazard admission, floor-normal limits and capsule tests remain in place.
Motion guards bypass this cache. The eight fixture route arrays match exactly;
50.36% of requested fixture rays use cached answers. Full-host latency remains
mixed and unqualified: see [query evidence and limits](../issues/runtime-performance/navigation-query-cache-2026-11-09.md).

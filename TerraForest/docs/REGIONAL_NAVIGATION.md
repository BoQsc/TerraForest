# Regional surface navigation

Selected walking journeys verified, 2026-10-23. This extends
`NAVIGATION_STANDARD.md`; broader coverage and performance remain explicit gates.

`NativeActorNavigator` now owns a shared, derived surface graph for its external
characters. Nearby level targets retain `ActorRoute`; targets farther than 12 m,
different storeys, or exhausted local searches use the regional graph. Both tiers
use the identical native support, capsule sweep, step and hazard evaluator. Standing zombies explicitly use their controller's 45-degree floor capability
(normal Y >=0.7072); legacy walkers and crawlers retain >=0.85. A physical 32-degree
ascent/contact and rejected 46-degree ascent qualify the standing profile boundary.
There is one physical body/motor owner. No generator recipe or saved world schema changes.

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
Geometry,
water, exclusion and authorized-door changes invalidate the cache and queries.
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

Regional moving targets keep their committed search while it plans, then refresh
after four metres of progress or on the final approach. A storey change can
retarget earlier. This avoids restarting a large search every pursuit tick.
Continuous moving-target endurance remains an explicit acceptance gate.

Selected evidence is complete in [regional navigation evidence](evidence/regional_navigation/README.md):
actual saved tower and cave round trips, closed-door clearance/destruction, edited
and unavailable topology, native debug/release fixtures and inspected images.
The standing motor uses the actual capsule radius, swept30cm steps, verified
front/foot-centre treads and floor snapping. Gravity cannot undo a verified riser
advance; no jump, unsupported traversal or wall/ceiling bypass is authorized.

Cold queries still take roughly10-17s in the selected outbound cases. Faster cold
planning, full96m pressure/travel, current owned-mine and broader seeds/buildings,
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

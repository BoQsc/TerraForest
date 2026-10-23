# Entity navigation and world interaction standard

Version 1, 2026-10-23. Applies to settlement actors, zombies and future mobile
entities. This defines required behavior and distinguishes current local coverage
from unfinished world-scale navigation. Character art and a passing empty-floor
chase are insufficient navigation acceptance.

## Ownership

Use the native `ActorRoute` core in `addons/world_runtime/native/actor_route.*` for
local supported walking routes. Existing settlement actors execute it through
`NativeEntityActivation`; external character bodies use `NativeActorNavigator`.
Do not create hidden walking proxies or let a second store integrate the same
character. The character controller owns its one body, animation and attack state.
Steering consumes validated waypoints; animation cannot authorize world mutation.

Route planning, crowd avoidance, physical movement and interaction are separate
contracts. Local separation is not pathfinding. Godot avoidance does not supply a
terrain route. A failed or unavailable route cannot silently fall back to direct
pursuit, teleport, noclip or movement through unready collision.

## Profiles and geometry

| Profile | Physical body | Conservative route envelope | Step capability |
| --- | --- | --- | --- |
| Settlement walker | centred upright capsule, radius 0.35 m, height 1.8 m | same | 0.30 m |
| Standing zombie | feet-origin capsule, radius 0.24 m, height 1.74 m | upright capsule, radius 0.35 m, height 1.8 m | 0.30 m using native grounded movement |
| Crawling zombie | horizontal 1.2 m capsule behind mouth | upright capsule, radius 0.75 m, height 1.8 m | no positive step |

The crawling envelope covers turning its long proxy, but is deliberately
conservative in height. Slopes, low tunnels and crawling under furniture are **not yet
qualified**. Anatomical changes must select a matching profile and invalidate the
old route. Capabilities cannot be inferred from an animation clip existing.

Routes use a 0.5 m grid, intermediate tread support, swept capsule clearance,
floor-normal Y >=0.85, and no more than the profile's step height. Readiness bounds
must cover the full query envelope, including larger crawling clearance. Stairs
require bounded up/forward/landing collision checks, not a position snap through a
riser. Do not authorize unsupported drops or gaps as walkable edges.

Hazard admission samples the centre, edge midpoints and corners of a conservative
square footprint, with 5 cm padding (at least a 0.4 m half-width), along the edge
at intervals no greater than 0.1 m. Each graph candidate has at most 81 admission
calls. This is bounded sampling, not continuous hazard geometry; tiny hazards
between samples are not qualified. Admission callbacks and
movement guards contribute to measured runtime cost separately from work counts.

Query static obstacle mask values 1, 2 and 4 (terrain/blocks, static model
structures and vehicles). Player bodies also use mask value 2; exclude the
specific chase recipient RID from route sampling, never the whole layer. Dynamic
settlement bodies use mask 8; zombie bodies use `1 << 16`, fitted damage regions
`1 << 17` and ragdolls `1 << 18`. Both moving bodies must recognize the other actor family. Door swing
occupancy must recognize both families and ragdolls. Hit regions are not movement
support or traversal geometry.

## Runtime limits and failure states

Each route retains at most 2,048 nodes and searches within +/-16 m of its origin.
Each activation/navigator pool shares 12 candidate work units per tick under a
cooperative 750 microsecond planning deadline. With both current pools active,
the host has at most 24 planning work units; the deadlines can overrun during a
physics query, callback, reset or reconstruction. These are not a total frame or
large-population performance guarantee. Motion guards and bounded perception are
accounted separately from planning; do not hide their cost in the work count.

Zombie navigation retains at most six routes and evaluates at most 30 ordered
neighbour pairs per tick. Moving targets use bounded goal updates rather than
restarting A* every frame. Far targets may use verified 12 m local horizons, but
this is local progress, **not a regional route or proof of reachability**.

Expose `planning`, `following`, `arrived`, `blocked`, `unavailable` and
`search_limit` plus work/node counts. `blocked` describes the sampled local graph.
Unknown collision is `unavailable` and must stop motion while preserving the
living actor through temporary publication changes. Retry unavailable coverage
and invalidate routes after relevant terrain, structures, doors, harvesting, water
or vehicle-obstacle changes. Dormant or suspended actors perform no search/motion.
Bodies beyond the encounter retirement distance may retire normally.

## Interaction policy

Settlement actors and zombies share geometry, not permissions. A closed door is
an obstruction until an authorized interaction changes it. The user's zombie
policy is **attack breakable doors when blocked**; zombies do not open doors.
The current breakable whitelist is the existing wooden-door asset.

An interaction has an identified model placement, a valid approach, an action and
a result. Attack windup and contact timing remain authored. At the contact marker,
recheck live identity, reach, facing, anatomy, visible surface and intervening solid
geometry. Reapplying behavior cannot reset windup. Retargeting cancels the old
committed attack; a deleted/changed target cannot damage a replacement placement.

Door damage uses existing native world durability. Destruction removes the native
model placement, forgets hinge/durability state, invalidates routes and marks the
compound world dirty. NPC damage grants no player salvage and consumes no player
tools. Protected placements reject damage/removal. No generic permission to mine
terrain, open storage, operate vehicles or destroy every blocked object is implied.

## Acceptance and unfinished coverage

Every mobile family must prove actual movement around a solid obstacle, stair
arrival, failed and unknown route behavior, edits/door invalidation, moving goals,
crowding, activation/suspension and capability changes. Tests must run the real
host update loop, and rendered evidence must be inspected. Interaction acceptance
includes complete action-to-world-mutation behavior and saved-state correctness.
Native debug and release builds and existing actor-route regressions remain gates.

Still required before claiming proper whole-world navigation: a regional/portal
graph linking streets, entrances, floors and caves; streaming requests for future
routes; robust moving-target/endurance checks; shared heterogeneous avoidance;
automatic permitted ladder/jump links; tight crawler clearance; door-destruction
fresh-process save/reopen; populated settlement/cave journeys and measured total
CPU/frame cost. Building layouts must also satisfy `WORLD_BUILDING_STANDARD.md`.
Neither repeated local horizons nor these documented rules close those gates.

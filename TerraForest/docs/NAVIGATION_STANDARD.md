# Entity navigation and world interaction standard

Version 2, 2026-10-23. Applies to settlement actors, zombies and future mobile
entities. This defines required behavior and distinguishes current local coverage
from unfinished world-scale navigation. Character art and a passing empty-floor
chase are insufficient navigation acceptance.

## Ownership

Player-dropped pickups use a separate fixed 64-proxy `NativePickupPhysics` pool,
with the engine as their sole integrator. Upright linear rigid proxies use layer
`1 << 21`, mask `1 | 2 | 4 | (1 << 21)` and an explicit player-RID exception.
They mirror canonical pickup positions/velocities for batching, targeting and
compound saves; do not also call the entity store's kinematic `step`. Menu,
loading and unavailable swept collision coverage suspend them as registered
static bodies. Sleeping proxies can retire when the pool is full, leaving saved
ordinary pickups. This grants no actor navigation or interaction permissions.
The default-on original-size preference uses per-batch authored dimensions.
Rendering, physics, swept readiness and picking share its bottom-preserving
offset; canonical saved coordinates remain the compact reference anchor.
Resizing a live proxy replaces its native shape and wakes contact validation,
while the engine remains its sole integrator.

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
| Standing zombie | feet-origin capsule, radius 0.24 m, height 1.74 m | upright capsule, radius 0.24 m, height 1.8 m | 0.30 m using native grounded movement |
| Crawling zombie | horizontal 1.2 m capsule behind mouth | upright capsule, radius 0.75 m, height 1.8 m | no positive step |

The crawling envelope covers turning its long proxy, but is deliberately
conservative in height. The standing slope profile has an explicit physical test; crawler slopes, low
tunnels and crawling under furniture remain **unqualified**. Anatomical changes must select a matching profile and invalidate the
old route. Capabilities cannot be inferred from an animation clip existing.

Routes use a 0.5 m grid, intermediate tread support, swept capsule clearance,
the profile's floor-normal limit and step height. Legacy settlement walkers and
crawlers retain normal Y >=0.85. Standing zombies use normal Y >=0.7072, matching
their physical 45-degree floor setting with a small conservative tolerance. Readiness bounds
must cover the full query envelope, including larger crawling clearance. Stairs
require bounded up/forward/landing collision checks, not a position snap through a
riser. Do not authorize unsupported drops or gaps as walkable edges.

Interior support probes are now at most 2.5 cm apart, including exact-position
root connectors. This prevents narrow steep terrain facets from being admitted
only because their endpoints and midpoint are walkable. Step/slope limits and
the cooperative planning deadline are unchanged. One candidate uses at most 75
physics queries including worst-case stair clearance; ordinary short frame-motion
guards retain their two support probes. This remains bounded sampling, not a
continuous proof for arbitrary sub-centimetre geometry.

When live movement still finds a steep facet on a regional waypoint, that query
remembers at most 16 rejected waypoint neighbourhoods (10 cm radius, height-aware)
and searches again. It does not repeat the same cached failing connector or move
through it. Root rejection must try the other eight neighbours. Relevant world
invalidation discards these derived failures; exhaustion stays explicitly blocked.

Hazard admission samples the centre, edge midpoints and corners of a conservative
square footprint, with 5 cm padding (at least a 0.4 m half-width), along the edge
at intervals no greater than 0.1 m. Ordinary half-metre/diagonal candidates have at most 81 admission
calls; an exact-position root connector to a neighbouring aligned cell is at most
1.061 m and 108 admission calls. Open-space links consist of separate bounded
half-metre quanta. This is bounded sampling, not continuous hazard geometry; tiny hazards
between samples are not qualified. Admission callbacks and
movement guards contribute to measured runtime cost separately from work counts.

Query static obstacle mask values 1, 2 and 4 (terrain/blocks, static model
structures and vehicles). Player bodies also use mask value 2; exclude the
specific chase recipient RID from route sampling, never the whole layer. Dynamic
settlement bodies use mask 8; zombie bodies use `1 << 16`, fitted damage regions
`1 << 17` and ragdolls `1 << 18`. Both moving bodies must recognize the other actor family. Door swing
occupancy must recognize both families and ragdolls. Hit regions are not movement
support or traversal geometry.

Player-operated doors ignore the operating player's own swing occupancy so E
works while touching or blocking the leaf. Other actors, zombies, ragdolls and
vehicles still block a swing; this does not authorize NPCs to open doors or
disable the door's physical collision. Inside-leaf interaction picking retains
the normal three-metre range and intervening solid occlusion.

Player collision includes ragdolls even when living encounters are disabled.
Articulated limbs are not moving platforms. Native step assistance rejects active
ragdolls but permits verified-resting corpses, with a corpse-only 0.55 m lift.
Ordinary stairs retain 0.30 m; larger rises require corpse landing collision too.
Head, forward and landing sweeps remain mandatory, including up to four contacts
per obstacle/landing sweep. Collision remains enabled. Corpse rest preserves
anatomical joints and normal solver integration, not per-limb forced velocities
or gravity suppression. Real impacts and lost support restore active dynamics.
Menu/readiness suspension freezes bodies explicitly without removing their
physics-space registration or rebuilding joint frames.

Player standing/crouching capsules share a 0.34 m radius and fixed feet origin;
height changes from 1.8 m to 1.1 m. Native standing-clearance queries use the full
standing capsule, normal collision mask and only the player's own RID exclusion.
Blocked standing retains crouch; crouched movement is 2.6 m/s without sprint or
jump. Recovery margin is 4 mm, with eight slide iterations and no shallow-angle
wall sliding dead zone. The 30 cm swept stair limit and steep-wall refusal remain.
Do not add automatic noclip, teleport nudges or collision disabling to escape
geometry. The map permits movement while keeping map mouse interaction separate
from attacks/placement; ESC, inventory and action-wheel focus still block input.

## Runtime limits and failure states

Each local route retains at most 2,048 nodes and searches within +/-16 m of its origin.
The external-body service adds a derived regional surface graph and complete
height-aware queries. Its cache/query/domain/portal/residency contract and pending
acceptance are declared in [REGIONAL_NAVIGATION.md](REGIONAL_NAVIGATION.md).
The existing activation pool shares 12 candidate work units per tick. The external
navigator uses 12 for local searches and at most 48 half-metre quanta when a
regional search is planning, under the same cooperative 750 microsecond planning
deadline. With both current pools active, the host has at most 60 planning quanta;
the deadlines can overrun during a
physics query, callback, reset or reconstruction. These are not a total frame or
large-population performance guarantee. Motion guards and bounded perception are
accounted separately from planning; do not hide their cost in the work count.

Zombie navigation retains at most six routes and evaluates at most 30 ordered
neighbour pairs per tick. Moving targets use bounded goal updates rather than
restarting searches every frame. Finish a planning query before consuming queued
moving-goal updates. Local followers refresh near the old goal (3 m), after a
storey change (>2.5 m), or after a >4 m diversion with >1 m body progress; regional
followers retain their existing 4 m progress/end policy. Goal changes still pass
the 0.4-second throttle. Direct corridors remain local; the first local graph
expansion promotes an obstacle query to the existing shared regional cache,
avoiding repeated per-actor geometry sampling. Far targets and different storeys
also use complete regional searches; projected 12 m pursuit horizons are removed. A bounded regional
query still does not establish reachability beyond its declared resident domain.

Expose `planning`, `following`, `arrived`, `blocked`, `unavailable` and
`search_limit` plus work/node counts. `blocked` describes the sampled local graph.
Unknown collision is `unavailable` and must stop motion while preserving the
living actor through temporary publication changes. Retry unavailable coverage
and invalidate routes after relevant terrain, structures, doors, harvesting, water
or vehicle-obstacle changes. Dormant or suspended actors perform no search/motion.
Bodies beyond the 96 m zombie residency distance may retire, but must first
preserve the resident identity, position and anatomical state in the native world
population. Retirement is not death or a new encounter opportunity. Nearby
residents must be admitted before loading releases player input; no elapsed-play
spawn/refill loop is permitted. Dormant residents do not simulate navigation.

Zombie engagement is independent of route success. A stalled/blocked encounter
can abandon that destination for a short tactical reposition on its current
storey, with a separate full native route and all usual guards. This explicit
action has a two-second duration and three-second recovery cooldown; it never
moves on a failed/partial route or establishes whole-world connectivity. Missing
coverage around the actor still suspends it. Failed search endpoints preserve
engagement and retry under a bounded clock rather than clearing target memory.

## Interaction policy

Settlement actors and zombies share geometry, not permissions. A closed door is
an obstruction until an authorized interaction changes it. The user's zombie
policy is **attack breakable doors when blocked**; zombies do not open doors.
The built-in breakable whitelist remains the existing wooden-door asset. Door
content packs must explicitly set `behavior.zombie_breakable`; the same bounded
door targeting/damage path then uses that definition's collision and health.
The shipped second-door example sets this permission false. Merely importing a
GLB or registering a model grants no attack or opening permission.

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

Regional graph and frontier residency changes remain under actual-world
verification; implementation alone does not close the acceptance gate.
Still required before claiming proper whole-world navigation: representative
street/entrance/floor/cave journeys; robust moving-target/endurance checks; shared heterogeneous avoidance;
automatic permitted ladder/jump links; tight crawler clearance; door-destruction
fresh-process save/reopen; populated settlement/cave journeys and measured total
CPU/frame cost. Building layouts must also satisfy `WORLD_BUILDING_STANDARD.md`.
Neither repeated local horizons nor these documented rules close those gates.

### Coal-mine station capacity — 2026-11-01 prototype

The user requested ten zombies together at the deeper coal-mine station. The
existing native awareness/navigation services reserve at most 16 resident slots;
ordinary world admission stays at six. The population adapter selects 16 only
when its bounded nearby snapshot contains a coal-mine authored key (bit 42).
This covers ten station residents (bit 43), three side encounters and up to three
other nearby residents. No per-frame scan of all world records is added. Native
route search budgets and single-body movement ownership are unchanged.

Actual station sleeping/waking and thirteen-body fixture admission pass. This
does not establish dense pursuit/crowding performance. A frozen awake resident
blocked the driver's straight return; the existing station side lane was walked
successfully. The original installed package completes the fresh-world journey
(59 checks); the updated package passes physical doorway re-entry (59) and actual
inside-save reopening (46), with all nine surviving station bodies. Restored
standing clearance now uses the zombie's actual .24 m / 1.74 m movement capsule;
saved feet and the original .18 m support reach stay exact. Conservative ambient
admission is unchanged. Foreground awake-station combat/crowding and frame pacing
remain unqualified in [the coal-mine issue](../issues/coal-mine/README.md), which
retains earlier failed restoration checks and package-specific evidence. The
six-body statements above remain the ordinary population baseline, not the new
station-specific maximum.

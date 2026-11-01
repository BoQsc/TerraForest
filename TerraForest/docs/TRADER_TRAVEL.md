# Paid trader road travel

Requested 2026-11-01. **Full service implemented in source. The generated-world
paid trip, safe drop-off and distant return completed; coordinated packaging
and user review are separate.**

The player asks the resident trader for a ride, chooses another connected town or
city, and pays a quoted coin fare. Both enter the trader's car. The trader drives
along the actual roads while the player is a passenger. At the destination the
car stops, the player gets out, and the trader drives home and resumes trading.
This is continuous world travel, with no teleporting or movement through unloaded
collision.

## Player flow and transaction

1. Add **Travel** beside the trader's existing shop and upcoming quest services.
   List settlement/district destinations from the saved generated region, with
   road distance, fare, and unavailable reasons. Mines, footbridges, building
   entrances and secret POIs are not town destinations.
2. Bind quotes to the generated-region revision and exact outward/return routes.
   Initial proposed fare: 10 coins plus 2 per started 100 m of driven road. This
   is an implementation default, not a player-approved economy balance.
3. Validate a supported, unobstructed roadside pickup and both routes before
   accepting. The player walks to the car; the trader uses
   `NativeActorNavigator`/`ActorRoute`. The trader explicitly has permission to
   open resident hinged doors inside the original shop's prefab bounds, within
   3 m, using ordinary animated native door swings. Other doors, occupied swings
   and missing floor/collision remain obstructions. Planning may propose an
   authorized door; the motion guard still waits for its physical leaf to clear.
4. Charge once, atomically, only when both occupants can board and departure can
   begin. No charge for a stale quote, missing route, full merchant purse, failed
   boarding or insufficient funds. Cancellation before departure is free.
5. Player movement/vehicle controls cannot compete with the chauffeur. Keep camera
   look, pause, safe saving and readable destination/progress feedback. Retain one
   native chassis integration owner and the ordinary collision/readiness guard.
6. Arrival requires a stopped car and a loaded, supported, unoccupied pedestrian
   exit. Wait for the player to leave. A forward return around a connected block
   is valid; an instant pose flip or unvalidated U-turn is not.
7. Continue the return with independent bounded collision/model residency. Show
   the trader as away without recreating a shopkeeper at home. Resume trade only
   after the same trader physically returns.

Early disembarkation, failed-trip refunds and recovery must be resolved with the
transaction/state implementation before enabling payment. A route failure must
not leave an unrecoverable service after charging the player.

## Implementation

`NativeRoadJourney` builds a bounded graph from published road segments, splits
same-grade junctions, excludes paths narrower than 5 m and grades above 25%, and
uses actual route length for quotes. A departure heading can select a forward
return around a block. Disconnected/unavailable networks fail explicitly.
Node-based heading pruning is conservative; it does not prove every geometrically
possible vehicle route will be found.

The generated countryside uses 5 m approach roads and half-cell frontage
endpoints. Same-height endpoints within 0.75 m may join the overlapping road
surfaces; the vertical tolerance remains 0.15 m, so overpasses do not connect.
The captured production plan has a 1,507 m outward route to settlement 2 and
a 1,691 m forward return. The actual native chassis completed both routes in
the copied seed-1703 world, then the same trader walked back to the counter.

Limits: 8,192 source roads, 131,072 spatial-bin references, 1,048,576 candidate
pair visits, 262,144 unique comparisons and 32,768 graph nodes/query visits.
Configuration/quoting are request-time native work. The control follower inspects
at most 32 adjacent path segments per physics tick, limits speed to 8 m/s,
requests service braking and exposes following, arrived, blocked and unavailable.
It emits controls and never writes a car pose.

The optional `autonomous_controls` callback is unset on ordinary player cars. Player
driving keeps its existing path. With an assigned controller, keyboard driving
cannot control the car and reset/underworld teleport recovery is suppressed.
`NativeDrivingPolicy` remains the chassis integrator.

Road metadata is not a promise that the road is intact. The caller must supply
live readiness/clearance, invalidate changed routes and validate the entire
chassis footprint, including bends. The centre-line deviation guard alone does
**not** establish full vehicle clearance. Flat physical fixtures do not establish
production-world acceptance.

`trader_ride.gd` owns one reserved fleet identity and the idle, boarding, outbound,
arrived, returning, home-walk and stopping phases. A standing 0.34 m × 1.8 m
CharacterBody uses the existing native standing route profile and stair motor
(0.30 m steps, 45-degree floor limit). The rider becomes a passenger through the
normal vehicle seat/camera adapter. Both seat views reuse the existing human and
garment assets with an original procedural seated pose, fitted within the cabin,
with two-bone arm placement and simple original seat/steering-wheel fittings.
The hidden pedestrian capsules cannot duplicate the vehicle's collision.

The departure guard runs before payment. `NativePlayerInventory.transfer_items_to`
atomically moves commodity counts across bounded split stacks and updates both
revisions once; payment has no fabricated item output. A failed recipient grant
rolls back both inventories. Early exit first requests a stop; a second E after
stopping and finding a safe exit cancels the fare. Refunds that cannot fit remain
owed and retry without duplication. The car then finishes its forward itinerary
and returns; obstruction never authorizes a pose flip or collision bypass.

`NativeTraderRideState` validates a versioned binary section, including reserved
identity, payment/refund, passenger flag, driver pose, destination and both
routes. It is captured in the same compound save as fleet and inventories.
Each route is bounded to 8,192 points; quoted outward plus return routes share
that bound so cancellation can retain the remaining itinerary. Older worlds with
no section start idle. Restored paid passengers reboard without another fee.

The service publishes at most three snapped interests through the existing
eight-interest host. Terrain adds remote detail without replacing player focus;
model and block archive schedulers share their existing request, scan, byte and
body limits. Blocks page within 64 m of interests and retain within 96 m; remote
block meshes/collision use 38 m. Model paging uses 64/96 m admission/retirement.
Tree and boulder proxies receive the same interests. Unreconciled global owners,
unknown collision, chassis sweeps, unsupported wheel approaches or a chassis
footprint outside the published road stop controls. The service probes at 10 Hz;
the existing vehicle streaming guard also runs around each physics update.

## Integrated verification and limits

| Requirement | Evidence | Scope / remaining work |
| --- | --- | --- |
| Booking and coins | 15 native assertions per variant; live blocked pickup charges nothing; 42-coin boarding payment and exact cancellation refund pass | Final UI/cancellation 30/30 and fresh-process refund/return reload 11/11 pass |
| Trader walk/boarding | Actual counter-to-car and player walks; two fitted humanoid seat views; real chassis departure | Existing garment/body fitting and opaque exterior glass retain their prior limitations |
| Passenger ownership | Ordinary car/input regression checks pass; pause holds; stopped arrival and safe exit pass | Input guard retains one native movement owner; user interaction review remains separate |
| Independent return | Same car completes the 1.69 km return and trader walks to counter while player position/focus remain in Town 2 | Road edits/obstacles stop the service until cleared; early exit refunds the fare. No unvalidated U-turn or teleport recovery |
| Durable service identity | Native archives pass 35 per variant; unpaid reservation, paid outward and unoccupied returning fresh-process reopen pass, without another fare/refund | Arrival-only fresh-process test is not independently exercised; native phase contracts cover its archive |
| Production reachability | Full quoted outward/return driven in one actual generated-world fixture; repeat booking reuses the same car | Conservative graph/profile can omit routes; this is not every seed/network or arbitrary edited-road acceptance |
| Presentation/performance | Menu, arrival, departure and fitted seat images inspected; final short run wall intervals p95 19.11 ms, worst 51.84 ms. Long run private memory 3.84 GiB, dedicated GPU 1.40 GiB | Earlier long-run metrics are Godot process deltas (p95 19.09 ms, worst 133.31 ms). World active policy was 60 FPS despite launch requesting 30; no universal frame-time or world-quality acceptance |

The full-reload report `20261101T175223024902Z` passes all 16 functional/lifecycle
checks but is retained as an overall failure because its final offscreen pointer
assertion failed. The shared mouse helper now rejects capture in offscreen
sessions explicitly; cancellation report `20261101T180138538968Z` passes 27/27
with zero captures. Repeat-booking report `20261101T180310509234Z` passes all ride,
refund and pointer checks but retains a premature help-publication assertion;
the harness now waits for the host's process update. Final report
`20261101T182542058854Z` passes all 30 checks, including the corrected help and
stopped/refund feedback; `20261101T182722483062Z` passes all 11 unoccupied-return
reload checks. These are distinct from
physical journey failures and must not be presented as wholly passing reports.
The earlier too-high seat pose and boarding-payment failures remain in the
tracker. The fitted final occupants were inspected in the actual world. Coordinated
native-artifact commit/export belongs to the main work; no installed-build claim
is made from source runs.

## Provenance

New planner, tests and design are original AI-assisted work for this user request,
with code under 0BSD. Existing driving code/assets retain their terms and notices.
No external code, asset, dependency upgrade or license exception is introduced.
Evidence and failed trials: [trader travel tracker](../issues/trader-travel/README.md).

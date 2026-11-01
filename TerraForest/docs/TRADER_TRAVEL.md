# Paid trader road travel

Requested 2026-11-01. **In progress; not a playable service yet.**

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
   `NativeActorNavigator`/`ActorRoute`. Closed doors and missing floor/collision
   remain obstructions. Do not silently grant NPC door-opening permission.
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

## Implemented foundation

`NativeRoadJourney` builds a bounded graph from published road segments, splits
same-grade junctions, excludes paths narrower than 6 m and grades above 25%, and
uses actual route length for quotes. A departure heading can select a forward
return around a block. Disconnected/unavailable networks fail explicitly.
Node-based heading pruning is conservative; it does not prove every geometrically
possible vehicle route will be found.

Limits: 8,192 source roads, 131,072 spatial-bin references, 1,048,576 candidate
pair visits, 262,144 unique comparisons and 32,768 graph nodes/query visits.
Configuration/quoting are request-time native work. The control follower inspects
at most 32 adjacent path segments per physics tick, limits speed to 8 m/s,
requests service braking and exposes following, arrived, blocked and unavailable.
It emits controls and never writes a car pose.

The optional `autonomous_controls` callback is unset in ordinary play. Player
driving keeps its existing path. With an assigned controller, keyboard driving
cannot control the car and reset/underworld teleport recovery is suppressed.
`NativeDrivingPolicy` remains the chassis integrator.

Road metadata is not a promise that the road is intact. The caller must supply
live readiness/clearance, invalidate changed routes and validate the entire
chassis footprint, including bends. The centre-line deviation guard alone does
**not** establish full vehicle clearance. Flat physical fixtures do not establish
production-world acceptance.

## Remaining integration and closure evidence

| Requirement | Missing / prerequisite | Closing evidence |
| --- | --- | --- |
| Booking and coins | Coordinate trader UI with quest work; revision-bound quote and atomic payment/refund | Ordinary trader input, insufficient/stale/full cases, cancellation/reload without double charge |
| Trader walk/boarding | Mobile trader adapter, native route/profile, permitted door policy, seated occupant poses | Counter-to-car journey through actual entrance; blocked floor/door; both visibly seated |
| Passenger ownership | Seat/input/camera and safe exit in `world_vehicle` | Player keys cannot steer; pause/focus loss; physical arrival and clear exit |
| Independent return | Streaming currently writes the single player terrain focus; model paging selects one focus. Add bounded vehicle interest and archived model/block residency without moving player focus | Player remains at another settlement while car returns across residency regions; obstacles/unready coverage stop it |
| Durable service identity | Native validated compound-snapshot state, reserved fleet identity, trader seat/location and payment | Fresh-process reload in booking, outbound, arrival and return; no duplicate trader/car/free ride/double fee; old saves preserved |
| Production reachability | All lifecycle pieces and current generated road metadata | Connected countryside → Generate & play → ordinary trader → ride → exit → return → save/reopen, no review switches |
| Presentation/performance | Coordinated rendered-test window and integrated service | Inspect occupants/route/stop at 1920×1080; report p95/worst frame, memory, collision holds and return work; user review separate |

The coordinated export may include only this inert foundation after checks pass.
Do not advertise or enable paid travel. Resume integration after the shared
native/render test window and trader UI ownership are coordinated; rerun dependent
checks when prerequisites land. This milestone does not close the requested ride.

## Provenance

New planner, tests and design are original AI-assisted work for this user request,
with code under 0BSD. Existing driving code/assets retain their terms and notices.
No external code, asset, dependency upgrade or license exception is introduced.
Evidence and failed trials: [trader travel tracker](../issues/trader-travel/README.md).

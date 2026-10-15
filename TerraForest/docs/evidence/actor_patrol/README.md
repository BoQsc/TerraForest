# Native actor patrol — 2026-10-16

Two-point patrol extends NativeActorOrders and the existing bounded activation/routing system. Developer actor HUD and Actions > Development expose Patrol to aim. Select an actor first, aim at dry static ground, then use the action. The actor walks between its current position and the chosen point, 1–16 m apart. Stop clears the order; Select / send replaces it with a single destination. Telemetry distinguishes a patrol route.

Only active, collision-ready bodies can reverse a patrol leg, after routing reports arrival and the body is within0.3 m horizontally and vertically. No new per-actor script, timer, navigation map or dormant-population scan. Route planning and proxy limits stay unchanged. Unreachable routes retain existing blocked/search-limit behavior rather than teleporting or silently skipping a leg.

Persistence keeps legacy version1 for single destinations. Snapshots containing a patrol use version2,64 bytes/order: identity, active target, return endpoint, mode and reserved word. Validation rejects malformed/nonfinite/orphan records atomically. Version1 restores unchanged; older builds reject version2 saves. Current leg is preserved. Clearing or replacing orders removes patrol behavior.

Evidence: graphical adapter check walks four legs, restores mid-patrol, refuses advancement with unavailable collision, and retains inactive orders. Actual main-world UI action selects an aimed terrain endpoint; normal save/browser return/fresh process verifies exact orders and persistent actor identity. Fifteen native order checks pass with the release DLL in a clean project. Both native builds reuse prebuilt godot-cpp. Screenshot inspected; it is functional evidence, not animation-art acceptance or timing qualification.

Retained failure: the older actor_orders fixture required horizontal movement on the first activation frame. Existing avoidance publishes velocity asynchronously; the revised check requires movement within six physics frames. No avoidance algorithm was changed. The full patrol path uses the existing actor_world/native route rather than this timing allowance.

Limits: two points only, local routing only, no offscreen catch-up, scheduled NPC activities, combat AI, dense patrol/crowd performance, multiplayer or endurance qualification. Main-world persistence fixture freezes simulation while authoring/saving; actual repeated locomotion is covered separately by the rendered adapter fixture. Water remains deferred.

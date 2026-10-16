# Actor bridge integration — 2026-10-16

Production timber bridge prefab, native block collision, existing actor_world adapter, native local routing, avoidance and persistent patrol behavior. Two static banks leave a12 m empty span; actor endpoints are16 m apart. No manually authored navigation waypoints, teleports or special bridge movement.

Single actor completes crossing and return. Two opposing actors each complete crossing and return, ascending/descending the same block stairs and passing within the narrow rail corridor. Minimum body-centre height remains above0.85 m; actual minimum is recorded in trace. Activation stays within one/two bodies, and route work remains at most12 candidate edges per tick. Whole-frame performance is not measured.

Capsule nonintersection is checked each physics tick using distance between the vertical capsule centre segments (radius0.35 m,height1.8 m), including stair-height differences. Threshold0.699 m allows1 mm numerical tolerance. Observed minimum segment distance: 0.764223694801331 m. Earlier centre-distance-only probe was strengthened before acceptance. Full traces, commands and graphical screenshot retained;1920x1080 fullscreen cap60.

This closes the specific bridge/patrol interoperability check, with no runtime algorithm change needed. It does not prove many-actor throughput, arbitrary narrow layouts, dynamic bridge demolition, rotated bridge behavior, streamed terrain readiness, long travel or endurance. The previous actual-world bridge/patrol persistence evidence remains separate.

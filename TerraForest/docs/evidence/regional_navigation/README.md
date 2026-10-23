# Regional walking navigation — 2026-10-23

Selected engineering journeys pass on `codex/character-integration`, with world
checkpoint `6e3575fc` merged as `8ae421d8` and combined native libraries rebuilt.
No generator recipe or saved schema changed. The original world checkout remains
independent. This qualifies the cases below, not the complete 2 km world.

| Final check | Result |
| --- | --- |
| Actual saved tower, generator12 | 13/13: street, break the closed wooden door, climb two flights, attack the player on the second upper floor, return to the street |
| Actual saved cave, generator6/seed1703 | 9/9: exterior approach, supported ridge/mouth descent, attack beneath the terrain roof, climb back out and return |
| Regional graph | 14/14: complete40m detour, tile portals, separate storeys, cache reuse, missing frontier/resume, edited disconnection and recovery, caps |
| Residency | 11/11: additional terrain refinement, distant block publication/retirement, primary model priority and unchanged proxy budgets |
| Local zombies / legacy route contract | 14/14 each, including water admission, missing coverage and edited obstacles |
| Actual-host door interaction | 14/14, including intact-door blocking, authored damage, removal, hinge cleanup and no player salvage/wear |
| Native release DLL project | All four fixtures pass: regional graph, residency, slow narrow/authored stairs, player stairs/tall-wall/low-ceiling regression |

Standing32-degree pursuit/contact and rejected46-degree ascent pass. The slow
0.24m capsule climbs four authored entrance treads while respecting the30cm rise
limit and regaining physical floor contact. Terrain planner passes184 assertions.
Release checks use an isolated project and actual release libraries; they do not
qualify an exported game or full-host release journeys. The isolated player-stair
fixture reports a missing texture-set fallback; its scope is physics, not art.

`final/tower/` and `final/cave/` contain matching results, logs, invocation/native
hashes and inspected1920x1080 images. The tower's minimum intact-door plane
clearance is0.874m. All210 tower-save files and37 cave-save files, including regional
sidecars, retain their hashes. Lock files are excluded as transient semaphores.
NPCs receive no fixture waypoints, jumps, position corrections or collision bypass.
Only initial spawn, player goal changes, camera and lighting are fixture controlled.

| Rendered timing | Tower | Cave |
| --- | --- | --- |
| First complete outbound path | 16.672s | 9.762s |
| First complete return path | 14.883s | 5.083s |
| Outbound contact, including planning/door/walking | 110.122s | 48.209s |
| Return contact, including planning/walking | 74.474s | 59.138s |
| Peak measured planning | 960us | 987us |

The native service stays within48 planning quanta; the750us deadline remains
cooperative. A rendered tower interval reaches773ms. Short frame samples and HUD60
are not sustained frame-time or population qualification. The containing-box
readiness cache lasts only one synchronous planning pass; failed larger boxes fall
back to exact readiness. Actual movement guards always query live readiness.
Cold route latency remains a material limitation despite the reduced repetition.

Images show the zombie against the intact door, upstairs beside rails/furniture,
back outside, inside the arched cave and returned to its exterior. They do not
accept the rejected district layout, historical cave art, foot planting/IK or all
character presentation. The current encounter domain is96m and six residents.
The80m auxiliary-residency cases are component checks; arbitrary travel across the
full admitted domain under paging pressure still needs live endurance evidence.

`failed_live_world/`, `before_adaptive_graph/`, `height_guidance/` and
`pre_readiness_cache/` retain earlier outcomes. Diagnostic exits4294967295 were
owned test processes stopped after reproducing stalls, not successful journeys.
Older manifests without native hashes do not establish final binary identity.
Failures uncovered discarded sampled heights, coarse search flooding, mismatched
slope limits, riser contact/gravity, and a door approach beside the jamb. Fixtures
also needed layer2 on the slow capsule, an entrance-only direct driver, safe
collision logging and a32m roof ray for this roughly16m-high tunnel. The earlier
readiness mock was not a whole-box gate; its replacement uses a spatial resident
island and observes unavailable before the automatic retry, rather than at a fixed
instant. One terrain-planner wrapper used the wrong completion marker; the184
assertions passed, and the corrected invocation is retained. These failed runs are
not relabelled as passes.

Remaining: faster cold searches, full resident-domain pressure/travel, current
owned-mine and broader building/seed journeys, continuous moving-target endurance,
heterogeneous crowds, automatic qualified ladder/jump links, tight crawling,
fresh-process door-destruction persistence, and sustained host/population cost.
See [regional contract](../../REGIONAL_NAVIGATION.md) and the existing character
entry in [foundation status](../../WORLD_FOUNDATION_STATUS.md).

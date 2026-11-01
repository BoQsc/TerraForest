# Gameplay expansion implementation contract

Requested 2026-11-01. Status: in progress, not a completed expansion.
Source: user objective attachment `ffc74909-5ecb-41ba-9007-26470ea80b63/goal-objective.md`.
This checklist preserves the whole requested scope across implementation turns.
Existing house approvals, player saves, 60 FPS/VSync and Quiet Mode remain intact.

## Delivery order and acceptance

1. Native encounter state, stable variety and sleeper animation/physical lifecycle.
2. Authored off-road POIs, occupied houses, supplies, locks and quest lifecycle.
3. Player progression, food/buffs, consumable reading and inventory navigation.
4. Expanded world recipes, biome content, paths, roads, bridge and building lights.
5. Ordinary-generation integration, fresh-process persistence, visual and performance review.

Implementation alone does not close a row. Every feature must be reachable through
ordinary gameplay, not only a developer toggle or an isolated fixture. Capture
matching source/package evidence, save/reopen, interaction and populated-world
performance. Inspect animation frames from multiple angles. New/revised buildings
return for individual approval before replacing approved content. Native bounded
hot paths, binary authoritative storage and shared/baked assets are required;
compute shaders are used where measured workloads justify them, not as a label.

## Full requested scope

| Requirement | Current state / closure evidence needed |
| --- | --- |
| Zombie variety, including already missing limbs | Native recipes installed; ordinary source/pack admission and anatomy reload checked; new visual character variety and balance still pending |
| Less irritating surface zombies, more wandering, finite pursuit and a faster minority | Native timers and configurable temperaments installed/tested; natural player encounters, jogging clip and locomotion review pending |
| Seated and lying sleepers, awakened by hearing or damage | Live native-clearance lifecycle integrated; default generation now registers stable house residents; crafted underground POIs and natural encounter review remain |
| Wake-animation frame-by-frame, multiple-perspective review | 58 pose/bounds checks, live interruption checks, both poses through furnished A2/C1 collision at all rotations; arbitrary slopes, moving obstacles and player visual acceptance pending |
| Sleeper residents inside some houses and underground locations | New-world A2/C1 anchors, bounded priority admission and persistent wake/death implemented; default generated cottage verified; populated C1 visit, crafted underground anchors and street-to-room player route evidence remain |
| Off-road watchtowers | Pending modular destructible design, access, terrain fit, loot and approval/review |
| Small art-directed caves and mines | Pending differentiated entrances, rooms, side spaces and some built mine structures; no generic straight tunnels |
| Cave/mine crates and supplies | Pending meaningful placements, reachability, loot and save/reopen |
| Trader quests targeting POIs | Pending stable location identities, quest objectives, rewards and trader UI |
| Large question-mark start interaction near POI, E acceptance and location reset | Pending bounded reset transaction with explicit location ownership, player-edit safety and persisted quest state |
| Locked wilderness/building containers | Pending rare deterministic locks, E lockpick consumption with small break chance, no minigame |
| Locked-container forced entry | Pending doubled durability while locked, damage opens lock, preserves contents and persists |
| Rare locked/barricaded doors | Pending locally destructible barriers, entry choices, navigation and saved state |
| Double the largest world-content recipe | Pending measured counts/capacity, distributed towns/cities/POIs and generation/loading limits |
| Less chaotic main roads linking towns and cities | Pending corridor planning and actual connected on-foot/vehicle routes |
| Large interesting-shaped lakes | Existing varied lakes are baseline only; requested larger-content layout still needs world evidence |
| New medium-sized bridge | Existing timber bridge is not this new deliverable; pending new modular design and land/vehicle/water approaches |
| Parked vehicles in garages/warehouses | Pending footprint/clearance-aware placements, entry/exit and persistence |
| Efficient house-light expansion: fireplace, torch and fixtures | Pending original models, bounded light residency, emissive/distant representation and indoor performance |
| Slightly varied safe player starts | Pending second-floor house, roadside and path starts with collision/readiness and no hostile immediate spawn |
| Paths with a new imagegen texture | Pending original generated material/provenance, path planning and natural road/terrain transitions |
| Improved main-road texture | Pending separate imagegen material, correct physical scale and populated-world comparison |
| Ultra-thin white median/road-strip building shapes | Pending individual destructible grid-owned pieces and suitable marking textures; no continuous roadside meshes |
| Desert, lowland snow and rubble/ruins biomes | Pending generation and map integration, not snow restricted to mountaintops |
| Different biome traders | Pending varied original presentation/catalogs and ordinary-world reachable trade |
| Desert aloe, medium cacti and fewer trees | Pending original asset expansion, harvesting, biome distribution and near/far rendering |
| Snow berries and snowy-tree expansion | Pending original assets, gathering and bounded LOD/residency |
| Player buffs | Pending native effect identities, durations/stacking, UI and persistence |
| Skills, XP and skill points | Pending native progression and transactions, save migration, rewards and actual gameplay hooks |
| Learn by doing and crafting | Pending bounded event-driven awards with exploit/replay prevention |
| Books, letters and journals give mild learning | Pending items, left-click use, inventory double-click and USE context action with atomic consumption |
| Accumulating right-side XP notification | Pending aggregation beside resource gains, not per-frame UI churn |
| Hunger and food items | Pending time-scaled hunger, consumable food effects, inventory/use UI and persistence |
| Inventory top tabs: backpack, character, skills, journal, map, quests | Pending shared navigation and ESC/input ownership; backpack never duplicates toolbelt |
| Character 3D representation, equipment slots, bag on right | Pending cached/on-demand presentation, equip state and proper ordinary UI |
| Extensible addon/plugin/module boundaries | Pending content registration and validation across encounters/POIs/quests/items/biomes/lights; native encounter profiles are only the first boundary |
| Streaming, CPU/GPU/RAM/VRAM/storage efficiency under new content | Pending doubled-content generation/loading and populated travel/interaction/endurance measurements; preserve 4 GiB VRAM target and existing budgets |

## Current work and next dependency

Native encounter profiles and limb-loss recipes are the first implementation slice.
Sleep/wake state does not imply sleepers are playable before pose, collision,
animation and persistence integration. The existing ragdoll and route owners remain
authoritative; a sleeper is a living entity, not a corpse resurrected by a timer.
Full body/limb health remains separate and linked. No player save is regenerated.

The six-clip library now drives living sleepers through one body owner. Native
clearance queries hold blocked poses and retry at 10 Hz; ordinary sleep adds no
repeating clearance queries. Version-three population records preserve 44 bytes
of sleep intent/pose state, with old saves retaining their original layout. Live
flat-host tests cover ceiling refusal, hits, leg loss (including the completion
handshake), death, suspension and fresh-process restoration. A float32 boundary
reload defect was reproduced and fixed; rejected evidence remains available.
House registration now runs in ordinary generation after approved buildings are
placed. Half the eligible A2/C1 houses are selected deterministically, subject to
the initial 40 m safe zone. Existing worlds are not populated retroactively.
The default seed-1703 browser recipe creates two registered house residents;
actual cottage wake, fresh-process damage/death and hidden nonloading admission
are tested. Both poses clear both unchanged furnished resources in all four
rotations. The C1 collision fixture is not a populated-world C1 visit; teleport
arrival is not a street-to-room player traversal or frame-pacing qualification.
Next: crafted watchtower/mine/cave layouts and ordinary route/terrain-fit review,
then shared location ownership for quest reset, locks, supplies and persistence.

Sleeper integration uses `ZombieWorld.put_to_sleep(actor, 1)` for seated and `2`
for lying, or `sleep_pose` in a validated encounter descriptor. The host owns the
native awareness handshake; standalone animation playback does not authorize
combat or persistence. `hear_noise(source, radius)` is bounded to six residents
and the native hearing limits. `NativeZombiePopulation.register_sleepers` accepts
up to 256 keyed anchors atomically and never resets existing identities. Version
four uses 140-byte records, preserving tombstones after a house is cleared. Native
v1-v3 readers remain; no authored keys are invented when old worlds load. The
six-active-body and two-sight-probe limits remain. House admission prioritizes
authored residents without removing nearby, visible or fighting inhabitants.
Visibility uses bounded ray samples, not a universal visibility proof. Quest/POI
reset ownership is still separate unfinished work; ordinary loading never resets
or resurrects an authored resident.

Evidence and retained failures: [expansion tracker](../issues/gameplay-expansion/README.md).

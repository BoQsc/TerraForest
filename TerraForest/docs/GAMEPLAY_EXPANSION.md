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
| Seated and lying sleepers, awakened by hearing or damage | Live native-clearance lifecycle integrated; default generation registers stable house and cave/mine residents; broader natural encounter review remains |
| Wake-animation frame-by-frame, multiple-perspective review | 58 pose/bounds checks, live interruption checks, both poses through furnished A2/C1 collision at all rotations; arbitrary slopes, moving obstacles and player visual acceptance pending |
| Sleeper residents inside some houses and underground locations | New-world A2/C1 and authored underground anchors persist; cottage and both underground locations checked; populated C1 visit, broader street-to-room routes and encounter balance remain |
| Off-road watchtowers | W1 installed in ordinary new worlds using shared native lot fitting, connected approaches, stocked upper-deck chest and persistent sleeper; source/package generation/travel/loot/wake/reload pass; broader seeds and visual/NPC/performance acceptance remain |
| Small art-directed caves and mines | Branching mine and bent two-chamber cave generate on fitted hillsides; recessed portals remove the reproduced thin-roof patch; native cuts, timbers and entry walks checked; richer art/dressing and full acceptance remain |
| Cave/mine crates and supplies | Five grounded stocked chests across the two layouts; actual UI withdrawal and fresh-process contents persistence checked; loot balance, locks and quest ownership remain |
| Trader quests targeting POIs | Pending stable location identities, quest objectives, rewards and trader UI |
| Large question-mark start interaction near POI, E acceptance and location reset | Pending bounded reset transaction with explicit location ownership, player-edit safety and persisted quest state |
| Locked wilderness/building containers | Source verified: rare new-world locks, craftable/tradable picks, E unlock with 10% break chance; ordinary generated-chest interaction and fresh-process restore pass; matching export/package verification pending |
| Locked-container forced entry | Source verified: 180-health lock, live picking/contact adapter unlock preserving supplies, partial damage and fresh-process reload; package verification and direct animation-input playtest pending |
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
| Skills, XP and skill points | Installed: native bounded XP/levels/points, three functional harvesting/combat skills, Skills panel and compound-save migration; source earned-level/reload and matching package reload verified; wider balance and remaining navigation/content pending |
| Learn by doing and crafting | Published mining, natural harvesting, actual zombie health loss and successful paid crafting award XP; duplicate/failed/dev actions excluded; source real-world mining/felling/reload checked; broader ordinary combat and anti-grind balance remain |
| Books, letters and journals give mild learning | Pending items, left-click use, inventory double-click and USE context action with atomic consumption |
| Accumulating right-side XP notification | Implemented in existing five-row event-driven resource feed, fixed control pool and no idle processing; gameplay adapter aggregation checked; broader player presentation review remains |
| Hunger and food items | Pending time-scaled hunger, consumable food effects, inventory/use UI and persistence |
| Inventory top tabs: backpack, character, skills, journal, map, quests | Pending shared navigation and ESC/input ownership; backpack never duplicates toolbelt |
| Character 3D representation, equipment slots, bag on right | Pending cached/on-demand presentation, equip state and proper ordinary UI |
| Extensible addon/plugin/module boundaries | Pending content registration and validation across encounters/POIs/quests/items/biomes/lights; native encounter profiles are only the first boundary |
| Streaming, CPU/GPU/RAM/VRAM/storage efficiency under new content | Pending doubled-content generation/loading and populated travel/interaction/endurance measurements; preserve 4 GiB VRAM target and existing budgets |

## Current work and next dependency

### Native player progression

`NativePlayerProgression` is part of the existing player runtime DLL, not another
extension or per-frame service. It keeps XP, level-derived points and skill ranks;
the initial three skills take 48 binary bytes (up to 32 skills take 280 bytes).
Levels use `125 * (level - 1) * level` cumulative XP, capped at level 50. Each level
grants one point; each of five ranks costs one point and adds 5% relevant damage,
rounded to the nearest integer. Mining covers terrain/natural stone, Woodcraft
covers natural trees/plants, and Melee affects living zombies. Balance is provisional.
The existing recipe/harvest/encounter owners still decide whether an action occurs.

Awards happen only after publication/accepted damage or successful paid crafting.
Mining uses removed sample counts (maximum 20 XP per published edit); natural
harvesting uses paid resources and a finishing bonus; combat uses actual lost
overall health, capped per hit, plus a one-time finishing bonus. Inventory transfers,
tool windup, refunds, no-ops, refused hits, rollback and dev-belt actions award none.
Terrain place/mine cycling is still possible practice with material/tool costs;
there is no claim of a general anti-grinding or authored-terrain-origin ledger.

The compound-save component restores old worlds to zero XP only when absent.
Native expected revisions prevent stale award/spend transactions; existing edit
tickets/contact ownership prevent repeated events. Malformed bytes and unknown
saved skill IDs fail without mutation; adding stable skill IDs retains old ranks
and initializes the additions at zero. Removing skills or reducing rank limits
requires an explicit migration. The compact bounded definitions live in
`addons/player_runtime/progression_rules.gd`; they are not a complete mod loader.

The current Skills side panel is reachable from inventory while preserving the
separate 22-slot backpack/10-slot belt. It is not the requested complete top-tab
navigation or 3D character screen. Readables, hunger/food, buffs, journal/quests
and location-reset ownership remain the next dependencies in the full checklist.
Source/package evidence and retained fixture failures are in the expansion tracker.

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
Ordinary generator 29+ now plans two compact underground layouts before baking:
a nine-segment looping survey mine and a five-segment bent cave. Native bounded
fitting avoids buildings, earthworks and lake envelopes; approach cut/fill, floor
support, roof cover and shared model-ground checks precede publication. Existing
saves never receive retroactive excavation. Five chest supplies and five keyed
sleepers use the existing binary model/container/population owners, not a parallel
scene or per-frame script population. Entry walks, actual chest UI, waking and
fresh-process clearing are tested. The reproduced isolated dark rim patch came
with a thin rock layer; bounded authored entrance recesses now remove that layer
instead of modifying global lighting. Faceting and sparse dressing are not final
art; town-to-entrance paths and general NPC routes remain.
W1 watchtower uses the shared lot planner with an explicit regional-access mode:
arbitrary road directions and their actual cubic height profile, unchanged 2 m
fill/3 m cut limits, bounded candidate search and lake/building/cave exclusions.
Normal preview includes the roof geometry; publication checks terrain contact and
actual thin-deck prop support before stock and keyed sleepers are registered.
Plan v34 fingerprints the baked resource. Existing worlds are never retrofitted.
Source ordinary-generation tests now walk both approaches and staircases, withdraw
supplies, wake residents and verify fresh-process stock/death persistence. Matching
installed-package checks pass too. Broader seed/art/NPC traversal and foreground
performance acceptance remain distinct.
Refine location dressing, then add shared stable location
ownership for quest reset and locks. Supply grants occur only during generation;
loading a looted location never grants or resets its contents.

### Exploration addon boundary

`addons/exploration/small_locations.poi.json` is original CC0 authoring data.
`cave_layouts.gd` validates a 64 KiB, 1–8-layout catalog, 2–16 flat arched segments
per layout, finite bounded coordinates and at most 16 anchors in each group.
Unsupported data fails rather than silently dropping pieces. Quarter-turn grid
rotation is shared with the native prefab owner; timbers remain individual blocks.
Optional `entrance_cuts` contains up to four `[x, front_z, back_z, half_width,
clearance]` records. These are explicit open-air portal recesses, not covered
tunnels: x is within ±4 m, front -4..0 m, back 1..7 m, half-width 1..4 m and
clearance 8..12 m. Native fitting surveys the full half-metre footprint, rejects
unsupported ground or a buried cut top, and reserves the complete envelope.
They use existing subtractive rectangular excavation packets; ordinary road/lot
fill and cut budgets are unchanged. Old catalogs without recesses still load.
`TerrainCore.plan_exploration_sites` tests at most 4,096 candidates per layout and
four rotations against bounded reservations. No eligible site means an explicit
skip, not a destructive fallback or increased cut/fill allowance. The v33 plan key
includes catalog contents and native identity. Ground probes and excavation run
once during generation, not during frame updates or save loading. Native prefab
transactions return exact new model IDs for container grants; model-only sites
do not manufacture placeholder blocks, block revisions or undo entries. This is
a validated content boundary, not yet the requested complete mod/plugin system.

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

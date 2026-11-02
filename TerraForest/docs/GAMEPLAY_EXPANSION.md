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

### Upstairs introduction and quest search — 2026-11-02

- New Frontier starts select a collision-qualified upper floor of the nearest
  approved C1 house within 200 m of the trader (seed 1703: about 190 m). No house
  geometry is changed; rejected room/site selection fails publication explicitly.
- Approved five-second first-person waking motion: 4.4 seconds of hand gestures,
  then selected-item return. First-spawn intent occupies one bit in the existing
  56-byte native pose record; legacy/played saves do not replay it. ESC/UI/focus
  interruption returns equipment and control. Native persistent health now connects
  actual zombie/explosion damage to shelter respawn and the approved wake motion.
  Inventory is retained; health resets to 100. See
  [lifecycle checks and bounds](../issues/player-respawn/README.md).
- Native quest arrival replaces the destination point with a circular active
  area. A bounded 2 Hz adapter supplies awake red blinking compass spheres.
  After one kill and 60 active in-area seconds without another kill, remaining
  sleepers gain yellow spheres. Focus loss/UI pauses time; kills reset it;
  completion clears contacts. Binary quest v1/v2 loads remain supported.
- New churches receive ten keyed sleeper anchors across nave, crypt and vestry,
  retaining the initial sanctuary and existing six-live-body budget. Existing
  played worlds are not populated retroactively. All forty rotated anchors
  admit and complete their wake animation against unchanged furnished geometry.
- Pursuit uses a baked aggressive upper-body hunch/reach; wandering, speed,
  detection, attacks and ragdoll ownership remain unchanged. All 121 sampled
  frames preserve original hips and feet (maximum positional difference <1 µm).
- Focused evidence: 81 native quest checks in each build; 161 room/stair/church
  checks; seven quest UI checks; four posture checks. Wake approval video:
  `reports/expedition_motion/20261102T102506379981Z/Wakeup.proposal.mp4`.
- The first long walking harness failed because it bypassed normal player
  physics without advancing terrain focus; corrected test updates the same focus
  before actor residency. No production scheduler guard was relaxed. Failure:
  `reports/frontier_expedition/20261102T102649420509Z`.
- Package/ordinary-world evidence and remaining acceptance live in the
  [tracker](../issues/gameplay-expansion/README.md). This does not close the older
  broad-seed road admission, foreground frame pacing or full expansion backlog.
- Installed ordinary route/save: 188 checks; fresh-process reload: 12. The final
  selected-item idle-return correction now passes 23 packaged assertions. After
  correcting the overly restrictive disk reserve, the final export also passes
  guidance/posture checks and a new installed-executable reload. Exact pack
  identities and scopes are retained in the tracker.

### Frontier expedition continuation — 2026-11-02, installed scoped verification

- New default recipe: three towns, two districts each, woodland base biome, connected
  roads/trails, mineral veins and trader introduction. Seed 1703 publishes 51
  buildings; this is not evidence that the largest recipe was doubled.
- Native introduction grants a torch, automatic rifle and 180 rounds atomically,
  once. Quests/Trade UI, initial trader marker, defeat/reward adapter and free
  expedition/wait/unfinished-return states are installed and scoped-tested below.
- Native planning selects mine candidates near the trader's connected road
  component, surveys the footpath and requires an outbound/forward-return route.
  No collision bypass or increased earthwork allowance. Initial disconnected-road
  failures remain in `reports/checks/20261102T073607631203Z`.
- Ordinary new-world generation and near-trader spawn pass. The physical player
  walk exposed an entrance lip (`reports/frontier_expedition/20261102T075144079467Z`).
  A surveyed level landing now passes actual player/trader traversal; other buildings
  retain their existing approaches and exact approved geometry. The attempted
  universal landing caused layout rejection and was not retained.
- Native bounded gun-hit spring and automatic recovery pass synthetic skeletal
  checks and 31 actual-model standing/missing-forearm/sleeper/death assertions
  (`reports/zombie_sleepers/20261102T082449634385Z`). Front/side/rear impact,
  recovery and death frames inspected: visible recoil, preserved anatomy and
  return to animation, with no continuing spring after death. The final package
  repeats all 31 assertions in `reports/zombie_sleepers/20261102T094107055814Z`;
  standing impact/recovery and seated impact images were inspected. Player combat
  feel remains unreviewed; this is bounded skeletal deflection, not a second
  freely simulated living-body physics owner.
- Trader counter interaction and exact one-time supplies pass in ordinary seed
  1703. The driver initially stopped on a narrow terrain facet; retained reproduction
  `reports/frontier_expedition/20261102T080453594352Z`. Native route support
  sampling and bounded rejected-connector replanning are corrected in `bb941b06`,
  without relaxing slope/collision guards (10 sampling checks, debug/release).
  The separate three-storey tower route also fails with the unchanged baseline
  (`reports/checks/20261102T082555035676Z`); do not call navigation universally
  verified.
- Source saved outbound/wait/unfinished return passes 19 checks in
  `reports/frontier_expedition/20261102T084348393166Z`. A revisit does not duplicate
  supplies. Physical mine traversal and real rifle fire kill all 13 residents,
  using 145 of 180 rounds (`20261102T090258910289Z` in the same report family).
  That run exposed a stale streamed static-contact RID and stopped at the return
  walk: retain it as a failed run, not an end-to-end pass. `0b4a4139` removes the
  stale query; 33 support checks and four-direction corpse walk-over pass.
  Corrected continuation `20261102T091419444955Z` walks back, pays the reward and
  saves the completed quest (12 checks). Earlier door/selection/tight-waypoint
  harness failures are retained; no teleport, fabricated kills or extra ammunition.
- Packaged counter testing found a real range edge case: the visible trader capsule
  was reachable but its centre was just beyond three metres. Reach now uses the
  actual first scene hit within three metres, retaining wall occlusion. Source
  booking/departure passes 27 checks in `reports/frontier_expedition/20261102T092544678312Z`.
  The failed packaged approach `20261102T092236953171Z` remains evidence.
- Final installed PCK `00fbf8673149224998f2e9e299457e265ae6476388f997ae8efbd753a3060eb6`
  creates another seed-1703 world through ordinary Generate & play, then passes
  physical spawn-to-counter/Quests/Trade/supplies/boarding/departure (26 checks):
  `reports/frontier_expedition/20261102T094124645675Z`. Existing plan/map caches
  were warm; not a cold generation benchmark. The same PCK
  and all 14 matching libraries pass actual-executable mine travel, physical
  traversal, all 13 rifle kills, return drive/walk, reward and durable save:
  `reports/frontier_expedition/20261102T093348769676Z`, 48 checks. This run uses
  162 of the supplied 180 rounds. Fresh-process exact quest/inventory/car restore
  passes 10 checks at `20261102T093853957204Z`. No fabricated kills, extra ammo,
  teleport or pointer capture. Final packaged support/walk-over regressions pass
  at `reports/checks/20261102T094000735287Z_zombies_pack`.
- Final-package unfinished return (`20261102T094412000415Z`) passes the drive,
  waiting, E exits and retained quest, but the overall 19-check run has one failure:
  its stationary player blocks the trader's home-walk capsule. Retain that failure.
  Reopening the owned fixture and physically walking clear lets the trader replan
  and return to the counter (`20261102T094839105930Z`, 10 checks). The harness now
  walks away after exit, as the successful completed-mine test already did.
  No collision bypass was added. Arbitrary crowd avoidance and same-process
  recovery after a prolonged obstruction are not qualified by this continuation.
- The full mine run peaks at 4.08 GiB private commit (above the 4 GiB warning,
  below the provisional 6 GiB cap) and 1.66 GiB dedicated GPU allocations.
  Offscreen wall-frame p95 is 22.162 ms, worst 122.188 ms; **not smooth-frame
  qualification**. Keep 60 FPS/VSync/Quiet Mode. Return to focused populated
  travel/combat profiling before closing performance headroom.
- Broader default-recipe qualification is **not complete**. Seeds 8147 and 91823
  fail crossing/road cut-fill admission after bounded layout retries:
  `reports/checks/20261102T091524745580Z` and `20261102T091540307279Z`.
  Generation refuses unsafe publication; no terrain budget was increased and no
  content was silently omitted. Return to corridor/site planning for these seeds;
  require successful ordinary publication and physical routes before closing.
- [Frozen package evidence and images](../issues/gameplay-expansion/README.md#frontier-expedition--2026-11-02)
  distinguish source continuations, earlier failed packages and final checks.
  None of this closes repeatable POI resets, question-mark activation or the
  other pending expansion requirements below.

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
| Trader quests targeting POIs | Introductory Quests/Trade, supplies, real mine clear, waiting/free return and reward installed; actual executable passes mine/reward and exact fresh-process restore; broader seeds and repeatable reset quests remain separate |
| Large question-mark start interaction near POI, E acceptance and location reset | Location ownership is implemented; actual multi-owner reset, preserved baselines, player-edit safety and marker/E interaction remain pending |
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
| Paths with a new imagegen texture | Original imagegen source candidate and exact prompt/provenance retained in `addons/exploration/art/`; tiled/surface review, runtime bake, path planning and natural transitions remain pending |
| Improved main-road texture | Original imagegen asphalt candidate and prompt/provenance retained in `addons/exploration/art/`; runtime bake, tiled/physical scale review and populated-world comparison remain pending |
| Ultra-thin white median/road-strip building shapes | Pending individual destructible grid-owned pieces and suitable marking textures; no continuous roadside meshes |
| Desert, lowland snow and rubble/ruins biomes | Pending generation and map integration, not snow restricted to mountaintops |
| Different biome traders | Pending varied original presentation/catalogs and ordinary-world reachable trade |
| Desert aloe, medium cacti and fewer trees | Pending original asset expansion, harvesting, biome distribution and near/far rendering |
| Snow berries and snowy-tree expansion | Pending original assets, gathering and bounded LOD/residency |
| Player buffs | Installed native Well fed damage and Focused learning modifiers, active-time expiry, refresh-not-stack and binary persistence; source/package world use/reopen pass; balance review remains |
| Skills, XP and skill points | Installed: native bounded XP/levels/points, three functional harvesting/combat skills, Skills panel and compound-save migration; source earned-level/reload and matching package reload verified; wider balance and remaining navigation/content pending |
| Learn by doing and crafting | Published mining, natural harvesting, actual zombie health loss and successful paid crafting award XP; duplicate/failed/dev actions excluded; source real-world mining/felling/reload checked; broader ordinary combat and anti-grind balance remain |
| Books, letters and journals give mild learning | Installed three baked original items, ordinary loot/trade, shared native atomic use, held-use routing, double-click/Use menu and persistent Journal; source/package world loot/use/reopen pass; direct captured-mouse input/animation and broader art/balance review remain |
| Accumulating right-side XP notification | Implemented in existing five-row event-driven resource feed, fixed control pool and no idle processing; gameplay adapter aggregation checked; broader player presentation review remains |
| Hunger and food items | Installed native active-time food state, three baked food items, actual loot/trade/drop/use and binary restore; old merchant food migration preserves spent stock; source/package world checked; renewable sources and broader balance remain |
| Inventory top tabs: backpack, character, skills, journal, map, quests | Installed: source/package verified shared navigation, real cached map, first-ESC closes UI and standalone M movement; Quests is explicitly unavailable until contracts/reset are implemented |
| Character 3D representation, equipment slots, bag on right | Installed: source/package verified on-demand current player model, rotations, real equipment transactions and separate bag; current woven garments restore in both views; user presentation review remains |
| Extensible addon/plugin/module boundaries | Pending content registration and validation across encounters/POIs/quests/items/biomes/lights; native encounter profiles are only the first boundary |
| Streaming, CPU/GPU/RAM/VRAM/storage efficiency under new content | Pending doubled-content generation/loading and populated travel/interaction/endurance measurements; preserve 4 GiB VRAM target and existing budgets |

## Current work and next dependency

### Native location ownership and quest state

`NativeQuestLog` registers generation-owned bounds, resident anchor keys and chest
placement IDs. The TFQ1 binary component caps 128 locations, 32 residents and 16
chests per location. Registration is atomic; shared identities, overlapping bounds,
changed definitions and malformed storage reject. Native travel/reset/clear/return
states use revision checks and monotonic attempt tokens. An unfinished reset is
not saveable; rewards use the existing native inbox and progression owner.
No per-frame catalog scan or whole-world snapshot is added. Plan version 37 emits
metadata for newly generated caves, mines and watchtowers, without retrofitting
existing saves.

This historical ownership milestone alone did not provide playable quests. The
Frontier continuation above now implements the one-time non-reset introduction,
offers, live mine clear and reward. Next for repeatable quests: exact bounded
terrain/block/model/stock/resident baselines and reset rollback; explicit player-edit
safety and question-mark/E start.
Return immediately after persistence qualification. Close only with normal
generated-world accept/travel/reset/clear/claim/reopen evidence, outside-region
preservation, failure rollback and performance measurements. Source generation,
streamed ownership and persistence checks pass; matching package generation and
fresh-process restore initially pass 25 + 10 checks. The combined content package
then passes 27 + 10 with five locations, twenty residents and twelve stocked
chests in 877 bytes. These are ownership checks, not playable quests.
The expansion tracker retains the first failed save-return test and the separately
reproduced cache-accounting priority fix.

The next reset primitive, `TerrainCore.capture_field_patch` / `restore_field_patch`,
passes rebuilt debug/release native and archived-storage checks and is included
in the combined package; it is not connected to gameplay. It captures a bounded integer
sample box as TFP1: 48 bytes of metadata/checksum plus three bytes per density/material
sample, at most 1,048,576 samples and 128 samples per axis. Coordinates exclude the
protected bottom and exterior. Capture is read-only; restore requires matching
seed/generator, current revision and owner epoch. Allocation/admission completes
before publication; failure retains authoritative samples. Existing samples outside
the box stay unchanged, including samples sharing the same storage page. An absent
page uses the normal terrain edit path's 1/1024 m density quantization when admitted.
Changed page versions, geometry digests and lighting are invalidated together.
Run this cold operation on the existing terrain worker, not a frame-loop scan.

`NativeBlockWorld.capture_cell_patch` / `restore_cell_patch` now provides the
separate building-cell primitive in source. TBP1 stores all cells, including air,
as uint16 shape/material/orientation words, a bounded header and SHA-256 digest.
Limits are 128 cells per axis, 262,144 cells and 524,356 serialized bytes. It uses
local integer cell coordinates; it does not move the building grid. Current
content revision and owner epoch are required. Unavailable regions, invalid
words, capacity failures and reentrant admission reject without overwriting
neighboring cells. Successful changes use existing chunk/halo invalidation and
signals. No history command is created. Debug/release pass 28 assertions each;
full region, prefab, history, worker and model-admission regressions pass.
The maximum empty-baseline fixture restores two changed edge cells in 4.60–5.72 ms;
this is not a dense restore or rendered gameplay timing guarantee.
[Building-cell evidence](../issues/gameplay-expansion/block-patch-evidence.json).

`TerrainCore.capture_cube_patch` / `restore_cube_patch` supplies the separate
exact terrain-cube owner. TCP1 includes air and materials, capped at 262,144 cells
and 262,192 bytes. Both variants pass 38 native and 35 binding checks: allocation
failure, world capacity, stale revision/epoch, preserved neighboring edits, cached
geometry, stale worker rejection and durable checkpoint/reopen. Dense maximum
restoration takes 7.23–8.06 ms in the standalone fixture, not gameplay timing.
Preflight reserves affected columns and hash capacity before mutation; deletion
compacts each affected column once. Rare hash growth/tombstone cleanup visits the
global cube map. Schedule on the existing worker, never the frame loop.
[Cube reset evidence](../issues/gameplay-expansion/cube-patch-evidence.json).

`NativeContainerStore.capture_container_patch` / `restore_container_patch`
preserves selected supplies and locks, including empty targets, tool wear and
water volume. TFCP1 is capped at 64 containers/34,872 bytes and requires the live
owner/revision token. Prepare all selected replacements before mutation; unrelated
contents, locks and nonempty transfer views remain unchanged. Both native variants
pass 42 checks plus the five existing lock/inventory suites and 53 quest assertions.
Restoring 64 targets among 2,048 containers takes 0.48–0.61 ms headlessly, not a
whole-reset or gameplay-frame guarantee. [Evidence](../issues/gameplay-expansion/container-patch-evidence.json).

`NativeStaticBatch.capture_placement_patch` / `restore_placement_patch` adds
bounded model restoration. TFMP1 stores exact IDs/transforms and asset/prototype
identity within a local integer box, at most 128 m per axis, 4,096 models and
229,652 bytes. It examines at most 4,096 group bounds and 16,384 candidate records;
over-budget, straddling, unloaded, protected or externally moved identities reject.
Selected replacements are staged together; outside models, live bodies and runtime
protection survive. Changed collision/exclusion and persistent visual pages update
through existing native owners. No whole-world copy or per-frame work is added.
Both variants pass 52 checks plus three fresh-process reopen checks. Existing
history, pages and horizon suites pass; restoration preserves exact IEEE transform
bits without stale visual records. The installed package passes 52 model checks,
three fresh-process checks and 63 horizon checks. Maximum capture/restore measures
2.44–2.55 / 3.29–3.64 ms headlessly;
renderer allocation failures and foreground frame pacing are not qualified.
[Model reset evidence](../issues/gameplay-expansion/model-patch-evidence.json).

Selected native hinge and damage state now also have bounded patches. Door patches
retain exact open/closed/mid-swing state, clip phase and blocked status for up to
256 IDs; damage patches retain up to 4,096 keys, including healthy absence. Both
use current owner/revision tokens and stage selected replacements before mutation.
Door publication rejects reentrant changes and mixed model/hinge save capture.
Both variants pass 58 owner checks, six fresh-process checks and existing combat,
harvest and container suites; 29 real authored-door checks cover blocked restoration.
The installed package repeats these checks and the attack/door-component suites:
224 counted assertions pass across eight suites; no foreground performance claim.
Live rig quiescence and matching model/state pairing still belong to the upcoming
transaction. [Owner-state evidence](../issues/gameplay-expansion/owner-patch-evidence.json).

Selected authored residents now also have a native TFRP1 patch: at most 256
identities and 37,952 bytes. It preserves exact anchor, pose, anatomy and sleep
phase, stages affected spatial buckets and requires current owner/revision plus
matching world/anchor identities. Ambient and developer-spawned residents are
not reset. Both builds pass 64 reset and four fresh-process assertions plus
population/encounter regressions. Live controller quiescence and corpse cleanup
are not part of this data primitive.
[Resident evidence](../issues/gameplay-expansion/resident-patch-evidence.json).

Corpse ownership/reset storage is now bounded to 64 explicitly keyed residents.
TFZC2 preserves resident/anchor ownership; TFZP1 restores selected body poses and
loot without rolling back player inventory or unrelated corpses. Legacy unowned
bodies remain unowned. Debug/release tests each pass 60 create, 5 fresh-reopen,
10 clothing-loot, 42 container-patch and 56 lock assertions plus capacity checks:
`reports/corpse_patch/20261102T065327591276Z/run.json`.
This is source/native verification, not installed-package or live cleanup evidence.
Return to live quiescence and coordinated reset after the new-player trader journey.

These primitives are not a complete location reset: live residents/corpses,
vegetation and any editable water require
their own bounded capture/restore and a coordinated transaction. Preserve their
outside edits too. Persistent baseline retention, worker scheduling, rendered
publication, player/vehicle exclusion and rollback across owners remain prerequisites
before enabling the marker/E interaction or trader offers.
Evidence, retained fixture failures and an unchanged older golden-data mismatch:
[field patch checks](../issues/gameplay-expansion/field-patch-evidence.json).

### Shared inventory navigation and character view

Six top tabs share one close button. Backpack retains crafting and the 22 bag
slots without duplicating the ten belt slots. Character shows the current player
model beside the bag and three native equipment slots. Its 384 x 448 viewport is
created on first use, renders once per reveal/rotation, and stops both rendering
and animation while idle. It reuses the model resource already loaded in-world,
not the full first-person rig. Measured source-world creation fell from 35.8 ms
for the initial full-rig prototype to 5.7 ms for this model-only implementation;
an isolated cold HUD still loads the model in about 1.2 s. These are individual
measurements, not universal latency or frame-pacing guarantees.

Map reuses the same survey/cache, with a compact destination selector inside the
inventory. It does not generate a second map. First ESC closes map plus inventory;
the next opens the pause menu. Standalone M still allows movement, whereas the
inventory Map tab owns input. A coalesced resize and redraw correct first-open
blank/clipped map content. There are no new per-frame inventory/portrait loops.

Source HUD checks cover native equipment drag/stale-revision handling and cached
rendering. The generated-world check dispatches actual local viewport ESC/M input,
verifies map imagery/layout, saved Journal and unchanged carried/equipped state,
without capturing or repositioning the desktop pointer. Evidence and earlier
failed fixtures are retained in the expansion issue. Matching installed package
passes 24 HUD and 21 generated-world assertions, plus 49 clothing and 8 existing
clothing-world restoration assertions. A new owned package world passes another
15 crafting/equip/save and 8 fresh-process restore checks. Quests currently reports that
contracts are unavailable: mission offers, location identity/reset and rewards
remain the next dependency, not a completed tab feature.

### Food, reading and timed effects

`NativePlayerSurvival` owns bounded nutrition, up to 8 effects and 32 consumables.
The current catalog adds field manual/letter/journal (25/10/15 XP) and beans/bread/
dried berries (35/20/10 percent food). Beans grant three active minutes of +5%
action damage; the journal grants two minutes of +10% XP. Reuse refreshes duration,
not strength. Food lasts one active hour from full; <=20% gives -10% damage and
zero gives -20%, not death. These are provisional balance values, not a health system.
One 1 Hz timer advances native counters only during focused, ready, nondeveloper
gameplay outside menus/loading. There is no offline decay or per-item processing.

One native revision-checked transaction consumes an item, awards reading XP and
updates food/effects/history without intervening callbacks. Full-food and stale
requests consume nothing. Three UI routes share it: held left-click, inventory
double-click and right-click Use. The Journal retains original read text after
consumption. No new held eating/reading animations or full navigation/3D character
screen are claimed. The passive world card now hides while backpack tabs are open.
Backpack still excludes the ten toolbelt slots.

The TFSS v1 condition record is initially 24 bytes, bounded to 344 bytes. Stable
added item/effect IDs accept older records; removed identities require migration.
Original models are baked offline into six drops and six static atlas tiles;
their adjacent provenance covers original geometry/narratives, not inherited tiles.
No realtime icon rendering is added. New plan version 36 stocks exploration chests
and some rare locked chests; finite merchant offers provide all six items.

`NativeTraderStock` wraps the existing inventory snapshot with a 16-byte header
and at most 32 pending item/count pairs. Legacy raw merchant records receive newly
introduced foods/readables once, preserving original money and stock. Full stores
retain queued additions until a successful trade creates room; saves retain that
queue. Versioned sold-out goods never refill on reload. Existing generated chests
are deliberately not reseeded. This is one catalog migration, not renewable food,
automatic merchant restocking, procedural books or a complete mod-content loader.

Source generated loot, actual E/hatchet-contact/storage UI, finite trade, native
drop/pickup, reading, food use, menu pause and exact fresh-process restoration pass.
The fixture accelerates 12 active minutes through the same native clock to test
eating without a 12-minute wait; a separate real 1 Hz timer assertion also passes.
It uses scripted travel and contact selection, not a movement/animation qualification.
Package validation and evidence are recorded in the linked issue tracker.
Next: full navigation/3D character, broader action-input and food balance checks,
quest ownership/reset, remaining world/content expansions and measured headroom.

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

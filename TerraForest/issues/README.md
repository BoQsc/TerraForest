# Visual issue tracker

[Strict walking-performance lab](runtime-performance/WALKING_LAB.md) now treats
every sub-60 FPS walking frame as critical and separates 61 FPS capacity,
headroom, diagnostics and presentation. It has proved and locally fixed a native
LOD mesh-switch GPU readback; remaining critical frames and human acceptance keep
qualification open.

**[★ Notable investigations](notable/README.md)** — unusual cases and reusable
lessons, kept visible after resolution. The [vegetation flicker case](vegetation-lod/LESSONS.md)
is starred; human source playtest confirmed the flicker improvement. The subsequent
[stone-proxy regression and fade](vegetation-lod/TRANSITIONS.md) have causal lab
evidence and a passing 220 m physical movement check; the user accepted that checkpoint for commit/push. Near-LOD handoffs, rectangular
patches now have a human-verified [broader transition snapshot](vegetation-lod/FAR_HANDOFFS.md)
with passing causal and physical movement checks. Broader
coverage and the separate GPU-tail target remain open. The subsequent
[foreground band regression](vegetation-lod/SHADOW_BANDS.md) is now reproduced as
invalid far-proxy projection; the integrated guard passes exact nearby comparisons.
Physical walking passes 189 m with 192 verified frames; human standing/walking validation passed on 2026-11-28.

[Native generation and binary inspection](../docs/NATIVE_GENERATION.md) now cover
outdoor placement, ordinary main-building placement, road/foundation batches,
save/map publication and generated-world storage verification. Generate-to-play
is 89.903 s with a cached plan; the complete 30-second target remains open.
Migration of remaining generation passes and component schemas is
open; scoped timing and
exact-output checks do not establish whole-world quality or clean exit acceptance.

[Metropolis and inhabited-region generation](world-generator/README.md#metropolis-recipe--2026-11-27)
adds a 36-building city, six communities and three required bridges. Source
planning, preview, final contacts, normal publication/trading and fresh restoration
pass. Installed scope, intermittent exit cleanup, world-quality approval and the
60 FPS target remain separately open.

[Inhabited island first playtest](world-generator/README.md#inhabited-island--2026-11-28)
adds a separate native geography/recipe with a three-quarter city, two towns,
four smaller communities and three required bridges. All 109 functional
creation/interaction/restore checks pass; strict shutdown cleanup still fails.
Human review called this a good start. Its original map retains a square coast,
straight lakes and fragmented streets. Cold Generate-to-play is 80.142 s; the
30-second requirement, natural geography and missing infrastructure remain open.

[Native shore habitats](world-generator/README.md#native-shore-habitats--2026-11-28)
promote LFP1 v3 / terrain 38 into **Inhabited island · living shores** worlds.
Bounded native filling restores the missing lake arm; continuous banks, rolling
shoulders and persisted grove/meadow blends improve the shores. Existing human
saves remain unchanged. The laboratory passes 91 checks and the full world
passes 128 functional assertions with vegetation enabled. All six final lake
views were inspected. The subsequent [native reuse pass](../docs/COLD_GENERATION_REUSE.md)
fixes first-play Water rebuilding and measures **84.627 s** versus 99.469 s,
still failing 30 s. All layers now reuse certified maps; 129 functional checks
pass, while strict shutdown warnings remain. Broad smooth areas, city/town graphs, broader seeds
and human approval remain open. Earlier angular-margin and bank-crease images,
failed trials and the unexplained resource-loading crash remain retained.

[Three grand buildings](grand-buildings/README.md) adds a 60-flat block, a
cathedral with two cellar levels and twin bell towers, and a ten-storey street
tower with 58 flats and eight shops. They are additional construction choices;
user visual approval, terrain/site integration and dense-street performance
remain separate from the prefab engineering checks.

[Homestead Manor and outdoor object integration](homestead-manor/README.md)
now also records the generation-timeout fix and the requested Homestead Valley
with 52 buildings and 684 outdoor objects. It retains the first interior, contacts and cutaway,
new outdoor pack and inspection UI. User visual approval, generated terrain fit
and dense-scene 60 FPS remain open. The
[full-game rendering follow-up](../docs/OBJECT_RENDERING_PERFORMANCE.md) records
reduced geometry/material costs, distance LODs and 1,000-object walking checks;
slow-frame qualification remains open despite successful residency and gameplay
assertions. Character admission now spreads setup and hull preparation across
frames, and character material batching reduces visible surfaces from 45 to 14.
The final uncontended replay passes one of four strict frame gates. Investigation
is closed out at the user's request; the remaining 60 FPS requirement stays open.
The later future-house population adds pack furnishings to current house presets
and bounded outdoor groups to newly generated settlements. Native placement,
fresh-process restore and temporary gameplay checks pass; full-scale generation
timing and complete furnished-room traversal remain separately unqualified.

The 64 m dry and wet controls and the lake barrel missed the two-frame deadline. Both craters passed their bank contact checks. Suspended green patches appeared in one cut capture and were absent from the repeat. [Paired cameras and publication timings](../docs/REAL_TIME_TERRAIN_AND_WATER_EDITING.md#packaged-comparison-of-terrain-and-water)

The dry 64 m control now compares the visible meshes and registered collider faces across all 36 terrain owners on the second draw. [Triangle generation, first physics installation and frame timings](../docs/WORLD_EDIT_EXPERIMENTS.md#dry-64-m-cut-and-collider-installation)

[Hidden Coast crater backlog](explosive-combat/README.md#hidden-coast-crater-backlog) records the 37 outstanding edits, their saved water footprint, and the changes to live capacity, persistence and firing during terrain updates.

The [shoreline mining fix](explosive-combat/README.md#shoreline-mining-in-normal-gameplay) connects deferred tool hits to the normal gameplay tick. In-game confirmation remains open.

The Windows package includes the player simulation-distance setting and the fix for chains crossing unloaded object pages. [Distant barrel chain investigation and package checks](explosive-combat/README.md#saved-barrels-beyond-the-player)

The [full-cut physics and timing decision](../docs/WORLD_FOUNDATION_STATUS.md#full-cut-physics-and-timing-decision) records the resting-body correction, two-angle shoreline evidence and the outstanding full-footprint publication deadline.

The [joint publication measurements](../docs/WORLD_FOUNDATION_STATUS.md#joint-publication-on-the-packaged-shoreline-route) cover the full cut, both shoreline camera pairs and the outstanding two-frame deadline.


The [changed-triangle gameplay test](../docs/WORLD_FOUNDATION_STATUS.md#changed-terrain-triangles-and-the-two-frame-edit-gate) still misses the two-frame requirement.

Shoreline latency is parked for the [regional basin architecture](explosive-combat/water-plan.md).
The [resident geometry trial](../docs/WORLD_FOUNDATION_STATUS.md#resident-terrain-geometry-and-shoreline-contact) measured 224–274 ms at the lake and 108–127 ms at sea.

In an earlier [water check](explosive-combat/water-plan.md), two-angle
shoreline contact passed and lake publication took 288 and 302 ms.
The dedicated bucket path now preserves transfers across command retries.

The latest [shoreline check](explosive-combat/water-plan.md) retained
two-angle sea and lake contact after enabling same-frame mesh dispatch.
Lake water still missed its publication budget.

Wet deposition in a cross-boundary crater now has a local gameplay and
dedicated-host regression. Barrel response time remains open at both shores.
See the [water issue](explosive-combat/water-plan.md).

**Water status, November 20.** Packaged Cedar Vale first showed matching crater water and collision at frame 9 at sea and frame 15 at the lake after terrain admission. Both miss the two-frame gate. The installed game fills both shoreline craters while wider settling continues. A reproduced 123 mm surface dip around a construction cube was corrected and checked at all four walls. A faster update that produced an angular lake ridge was rejected. The current build prepares the 132 urgent lake mesh owners in one job and matches all 66 first-publication samples against the committed field. The lake still misses the 250 ms check, and both shores exceed the two-frame target. The first local edit now levels enclosed basins across region boundaries. Cedar Vale still took 469 ms in packaged run `20261120T145825355695Z`. See the [water plan](explosive-combat/water-plan.md).

One folder per problem: relevant images, current status, changes, remaining work
and a practical place to resume. Detailed evidence stays at its existing location.

| Issue | Status | Latest review / next investigation |
| --- | --- | --- |
| [Roof material flicker](roof-material-flicker/README.md) | Fixed for reproduced shader case / world review pending | Flat categorical material codes preserve zinc shading during camera motion; eight rendered reference comparisons and 19 roof checks pass |
| [PX9 Eclipse handgun](px9-handgun/README.md) | First-person accepted / configurable feel trial | Corrected live hands, running/jump state and empty-magazine locomotion, paired animations, native 15-round magazine, pistol/reload SFX and procedural muzzle flash/light/smoke; combined master checks pass; [independent pistol feel controls](px9-handgun/feel-trial-2026-11-10.md) installed with scoped packaged checks; user feel and foreground performance review pending |
| [Last World startup and launcher](last-world-startup/README.md) | Native launcher installed / reproduced generation failure repaired | Godot import bootstrap; normal seed-1703 Generate & play and fresh Continue reach playable state. Worker lifetime, bounded water preparation and save/map ordering repaired; headless checks are not new visual or FPS approval |
| [Generic held-item hand posing](generic-item-hand-pose/README.md) | First version selected / further tuning deferred | User preferred the integrated first animation; revision 02 retained as a rejected comparison; baseline stiffness remains a known limitation |
| [Torch attack arm deformation and motion](torch-attack-motion/README.md) | First-person integrated / third-person art deferred | User requested revision 02 integration; frame-26 melee contact, full recovery and cancellation verified in actual world; rejected first preview preserved; third-person presentation still needs a dedicated art pass |
| [Zombie walking resets](zombie-gait-continuity/README.md) | Fixed for reproduced cases / player review pending | Shared walk/alert foot phase and brief waypoint-pause pose retention; fast pursuit, skin planting and combat checks recorded |
| [World photograph availability](world-photograph-availability/README.md) | Installed / player review pending | Recent worlds had no PNGs; resource cover omitted existing photos. One automatic clean arrival, shared image lookup and early cover assignment; existing photos preserved |
| [Modular world UI sets](modular-world-ui/README.md) | Activation corrected / player review pending | Activation immediately opens selected world screens. Distinct Survey/Planet live compositions and Diorama/Campfire loading layouts; real GUI click and world flow checks. Original references and rejected palette-only comparisons retained |
| [Empty larger buildings](building-zombie-population/README.md) | New-world population verified / player review pending | Three persistent sleepers per large building; four in factories/apartments. Full pose/wake clearance, generation, retirement and reload checked. Starting sanctuary exempt; existing worlds unchanged |
| [Passive zombies and sleeper ambushes](zombie-aggression/README.md) | Tower round trip corrected / latency and player review open | Ordered tread probes and blocked-connection recovery permit actual tower contact/return. Cold search still takes 18 s in the fixture, 35–45 s in the host; physical guards retained |
| [Steam installation consistency](steam-installation/README.md) | Artwork and Browse Local Files UI checks pending; entry/link checks pass | Latest remote artwork log still runs old code; fix delivery identified. Browse Local Files does nothing: plain StartDir repair now matches Steam's folder picker; actual menu confirmation pending |
| [G and universal item dropping](item-dropping/README.md) | Installed / functional checks pass; timing open | Default-on original-size tool option aligns rendering, physics, placement and pickup; compact option retained. Package 28 size / 32 input / 15 model checks, source 77 physics / 440 universal pass. Targeting p95 goal fails; visual/motion review pending |
| [Windowed mode across stages](windowed-mode/README.md) | Installed / scoped checks pass | Persistent host/global F11; 22 source + 22 executable transition checks. Follow-up loads mode before splash: source/package windowed, fullscreen and default startup pass with zero mismatches. User desktop review pending |
| [Footstep onset delay](footstep-delay/README.md) | Improved-partial / listening review pending | Short 0.15 m first-step trigger, 60 Hz sampling and material lookup outside playback; cadence and actual-floor checks |
| [Breakable room-light objects](house-lights/README.md) | Installed / scoped checks | Three GLB props, GPU flames, native four-light pool and 203 room placements; packaged salvage/destruction/reload and old-save compatibility pass. Art acceptance and broader route/performance coverage remain |
| [Vehicles in garages and warehouses](building-parking/README.md) | Installed / scoped checks | Native admission, player aisle/entry/exit, drive-out and packaged generation/fresh reopening pass; broader street/NPC/endurance and visual review remain |
| [Improvised door reinforcement](door-reinforcement/README.md) | Installed / scoped checks | Rough boards, native locks and player entry; packaged new-world/save/reopen and native lock/paging/reset pass. Source zombie forced entry passes; full generated-house journeys and visual approval remain |
| [Player health and respawn](player-respawn/README.md) | Installed / scoped checks | Native persistent health, real damage/death, safe shelter return and approved waking; fresh packaged upstairs save/reload and blocked-anchor fallback pass. Inventory retained; catastrophic obstruction and full moving-service death need further qualification |
| [Player notices and active objective](player-notices/README.md) | Installed / scoped checks | Added quest after waking, general notices above toolbar and upper-right objective; packaged creation/reload and notice/wake/guidance checks pass. Oversized first layout retained as rejected; user visual review pending |
| [Quiet notices, salvage and trading](town-loot-and-trade/README.md) | Installed / scoped checks | Routine toasts quiet; four useful salvage items; one-time town chest loot; two-list drag trading. Executable shop23 + reload15 pass; generation37 and source restore14 pass; user review separate |
| [Mountain coal mine](coal-mine/README.md) | Installed prototype / scoped checks pass | Branches, loop, five modular rails and ten-zombie station; original package full journey 59/0, updated package physical re-entry 59/0 and genuine inside reopen 46/0. Earlier failures retained; visual/crowding and foreground performance review remain |
| [Trader rides](trader-travel/README.md) | Return and door choice fixes / installed | Closed-stockroom/entrance boarding checks pass20 source +20 installed. 2026-11-03 stuck-save recovery/homecoming: source18 pass; executable18 functional pass with exit cleanup warning retained. Full source journey/return exercised; final UI/cancellation 30/30 and return-reopen 11/11 pass. Actual executable booking/departure 24/24 and paid-reload 14/14 pass; full package journey untested. Earlier pointer/timing failures, garment/glass limits and user review remain explicit |
| [Town roadside signs](town-road-signs/README.md) | Installed / scoped checks | Normal generation 17 + fresh-process reopen 18 pass; two signs per seed-1703 town, final images inspected. User visual review and broader coverage remain; retain 67.10 ms stationary outlier |
| [Two-block door height](door-height/README.md) | Fixed for new generation / package checks | Shared 2.75 m stretch and three-cell openings corrected; all 15 city/E2 buildings pass size and lintel checks. Existing saves retain their stored geometry |
| [World entry fly-in](world-entry-fly-in/README.md) | Fixed sequence / installed checks | Upstairs entry now flies in before waking; covered spawns fade into the character view and focus loss pauses flight. 75 installed checks pass across browser, populated reload and saved upstairs room; prior performance work and user review remain open |
| [Wearable clothing and trader outfit](woven-clothes/README.md) | Installed / scoped source and package checks | Minimal starter, all six craftable pieces, new-corpse trail loot and woven trader outfit pass 197 package checks; inherited body fitting and in-game review remain separate |
| [Authored door Open/Close](door-animation/README.md) | Installed / scoped checks | Authored GLB handle/latch and leaf motion; normal E, streamed visual ownership and mid-swing save/reopen pass in source/release/PCK; actual main executable checked, visual review pending |
| [Startup and browser latency](browser-responsiveness/README.md) | Improved-partial / full source launch measured | Complete source launch to responsive menu 40.49 → 2.07–2.73 s with reusable preparation; first input about 4 ms. Forced preparation, cancellation, invalidation and 22 Python checks pass. Batched outdoor queries cut the measured outdoor stage 44.6 to 16.6 s and creation 154.0 to 129.8 s, with all 684 placements identical. Cached recipe reuse and asset overlap then reduce planning 26.7 to 16.8 s and creation 129.8 to 121.0 s; exact plan/prefab/terrain checks pass. Removing an object-read frame delay reduces a furnished-world read-only load 41.8 to 33.9 s and normal Generate-to-ready 163.3 to 149.6 s; 70 native checks pass. Bounded saving and map preparation then improve save 25.4 to 10.8 s and map 16.6 to 4.9 s; Generate-to-ready improves 168.8 to 135.9 s with matching terrain, structures and map pixels. Mesh preparation then improves 10.1 to 2.7 s and one same-save load 39.4 to 33.4 s. Initial sea-fill ordering is now fixed; two full generations match saved terrain, structures and water, with 166 water assertions passing. Optimized generation is 123.5 s versus a 126.5 s original-mesh control and the earlier 168.8 s pre-save/map baseline (26.8% cumulative gain). Mesh-only generation timing remains unqualified; failed attempts are retained. Scoped prefab-input retention then reduces measured Generate-to-ready 123.5 to 102.8 s (16.8%), with exact saved-content gates and 20 startup checks passing; final loading 28.7 to 27.4 s does not establish a stable load-time gain. The stage audit identifies serial construction of 64 coarse terrain roots (~12.9 s) as the next bounded concurrency experiment; no runtime change or new speedup is claimed by the audit. Post-reboot cold launch, normal world-entry and foreground/package acceptance remain open |
| [Gameplay expansion](gameplay-expansion/README.md) | In progress / upstairs waking approved and installed | Packaged trader selection, mine rally/reset and fresh reopen pass with old/new water storage; duplicate offers show distance/bearing. Checkpoint admission no longer waits for background cache accounting. Uninterrupted journeys, all-layout/crash coverage, visuals and foreground performance remain open; earlier timeout evidence retained. Legacy reward-UI crafting assertion fails. Default seeds 8147/91823 still fail admission; rejected road experiments reverted |
| [Building expansion materials and joints](building-expansion/README.md) | E2 approved / production integration installed | Eight individual imagegen materials alongside retained optional older sets, shape/palette improvements and nine matched revisions; source/release/PCK, save/reopen and traversal checks pass; known older NPC planning and frame-pacing limits retained |
| [Trader and civic buildings](civic-buildings/README.md) | R1/E2 approved / production integration installed | Full trade, four basements, nine normal catalog choices and stock/inventory restore pass without review flags; source/PCK recipes and actual main executable checked; concurrent work preserved; broader frame pacing remains open |
| [Terrain crossing building blocks](terrain-building-contact/README.md) | Shared correction / enforced checks | Native shape-derived clearance, common datums and phase ordering, real footprint and exposed-surface publication gates; 30 debug/release + 64 catalog checks; human review and further recurrence coverage remain |
| [Unrequested mouse capture](mouse-capture/README.md) | Corrected / scoped checks | Click-to-play capture; loading and focus changes never reclaim the cursor; desktop review pending |
| [FPS / world overview](world-overview/README.md) | Partial / opt-in camera | Whole-world terrain/forest/boulder/static-prop/parked-vehicle coverage, archived exclusions and compact car LODs; prop paging/edit/reload checks integrated; transitions, dense costs, endurance and broader modules remain open |
| [Resource usage visibility](resource-usage/README.md) | Cached readings / storage retention corrected | Approved cleanup removes 12.67 GiB of verified generation duplicates and screenshot imports; ignores prevent report reimport and generation publication retires its working copy. Saves/evidence/history retained; 100 GB goal and broader test-world/worktree retention remain open |
| [Runtime performance](runtime-performance/README.md) | Construction/query and draw-work reductions verified / whole-frame p99 open | [Corpse/publication follow-up](runtime-performance/corpse-publication-2026-11-26.md) removes discarded rest-pose physics, shares indexed exclusion queries and drops exact collision duplicates. Admission/setup drift fixed; final six-leg gameplay and identity checkpoints verified. Overall p99 does not improve: 21.200 to 21.633 ms. Contended repeat excluded; process/draw bursts, engine waits, uncapped headroom and full human replay remain open. Earlier water draw-work gains remain verified in scope Cold generation: native street reuse/startup overlap reduces 70.772 to 64.241 s; 129 full checks and clean exits pass this run. The 30 s target, earlier intermittent shutdown warning and broader quality/FPS remain open. |
| [Long lakes and bridges](lakes-and-bridges/README.md) | Source lake checks / strict exit gate open | Three 360–480 m lakes; city/bridges and functional save/reload verified. Exit cleanup and high aerial visibility remain unqualified; installed baseline retained. |
| [★ Extended vegetation LOD](vegetation-lod/README.md) | Stone and near-fade snapshots approved / broader qualification open | Stone proxy regression isolated; corrected handoff/fade pass nearby/brightness checks and 220 m physical gameplay. [Near-handoff candidate](vegetation-lod/NEAR_HANDOFFS.md) passes causal controls, nearby parity and 312.75 m physical gameplay; snapshot approved for commit/push; detailed visual feedback remains open. [Remaining species/tier audit](vegetation-lod/REMAINING_HANDOFFS.md) and [far proxy/horizon/shadow controls](vegetation-lod/FAR_HANDOFFS.md) have a human-verified corrected snapshot, including [foreground projection guards](vegetation-lod/SHADOW_BANDS.md), 107 causal checks and a 189 m physical walk. Broader coverage and increased GPU tails remain open |
| [City buildings](city-buildings/README.md) | Approved designs / integration installed | Six exact approved designs on surveyed lots in larger recipes; populated-world player/NPC/vehicle routes, save/reopen, LOD and packed resources checked; site visuals and broader qualification remain |
| [Building geometry LOD](building-lod/README.md) | Installed / scoped checks | Default-on native geometry LOD plus world-wide distant block rendering, including never-visited archives; edits/reload and populated-world coverage checked; player review and denser-world endurance remain open |
| [Natural world-map presentation](natural-world-map/README.md) | Improved-partial / scoped checks | Cached water ready before first M; 1024² terrain, asphalt-first material ownership and unpainted shoulders; optional annotations; clustering/saves unchanged; finite zoom detail and shoulder geometry remain reviewable |
| [World generator UI and city layouts](world-generator/README.md) | Shuffle fix installed / scoped verification passed | 32 default seeds, both reported release-library seeds, packaged UI/terrain/road checks, actual generation and fresh-process restore pass; world-quality/user review remains open |
| [Building/POI terrain fit](site-terrain-fit/README.md) | Improved / scoped checks | Full-envelope/apron and driveway surveys, rectangular local pads; actual support/traversal checked; populated-site review pending |
| [Mouse capture / focus return](mouse-capture/README.md) | Fixed for reproduced cases / player review pending | No-click world entry and Alt+Tab return; actual Windows round trips pass; Esc/modal cursors and hidden-world isolation preserved |
| [Additional large house C1](large-house-c1/README.md) | Approved addition / integrated | New fitted neighborhoods and construction palette; native basement/slab preparation, multi-door publication and terrain traversal checked |
| [Dev Shapes catalog](developer-shapes/README.md) | Implemented / scoped checks | Searchable native-shape thumbnails, material grants and one-click placement setup; all 18 pieces tested; UI review pending |
| [Progressive harvesting](progressive-harvesting/README.md) | Implemented / scoped checks | Natural resources pay on damaging contacts with larger finishing rewards; native transactions and boulder save/reload verified; balance review pending |
| [Vegetation targeting flicker](vegetation-target-flicker/README.md) | Corrected / scoped checks | Removes running/turning preview lag and reach-edge disappearance; 70 packaged assertions pass; original-location review pending |
| [Player navigation and menus](player-navigation-menus/README.md) | Installed / scoped checks | ESC/inventory ×, quick quit, saved map markers/compass; 129 initial assertions and 48 inventory-follow-up assertions pass; user review pending |
| [Headlamp self-lighting](headlamp-self-lighting/README.md) | Corrected / installed, scoped checks | Excludes hands/tools in all three rendering modes; world beam unchanged; 305 packaged assertions pass, user review pending |
| [First-person world clipping](first-person-clipping/README.md) | Native-depth replacement / installed, scoped checks | Initial checkpoint comparison matched 13 scenes and 277 packaged assertions passed; later headlamp exclusion is intentional; user visual review pending |
| [Separate diagonal pickaxe study](pickaxe-crosscut/README.md) | Tip-first alternate retained / not default | User wants to keep this version for comparison but says its feel is still weaker; isolate the unsatisfying moment before another revision |
| [Discoverable material veins](material-veins/README.md) | Surface continuity corrected / scoped checks | Native pre-mesh material stems connect stones directly to buried veins; mining/persistence checked; appearance/balance await player review |
| [Player facing after vehicle exit](vehicle-exit-facing/README.md) | Fixed for reproduced behavior / scoped checks | Player faces current car front, input yaw stays synchronized; 110 focused/world checks pass, user review pending |
| [Reported fast-exit return](vehicle-fast-exit-return/README.md) | Unconfirmed / not reproduced | Four actual-world exits and seven resident-floor cases show no return; exact mod/build/speed and return destination needed |
| [ESC Player settings](esc-player-settings/README.md) | Implemented / scoped checks | Third-person and embedding switches move from Session into Player; session actions stay unchanged |
| [Vehicle sinks on exit](vehicle-exit-terrain/README.md) | Fixed for reproduced failure / scoped checks | Exit contact transition and fresh parking observations pass 18 repeated world exits; original-save user review pending |
| [Fly wheel initial hover](player-action-hover/README.md) | Fixed for reproduced case | Holding backtick selects the centred Fly action; release no longer needs a mouse wiggle |
| [Zombie ragdoll stability](zombie-ragdoll-stability/README.md) | Corrected at default 60 Hz / scoped checks | Ten stress fixtures, forest contact and four-direction walk-over pass; alternate 30 Hz physics and endurance remain unqualified |
| [Torch hand deformation](torch-hand-deformation/README.md) | Improved / partial | Rebuilt wrists and finger wrap at 60 Hz, locked runtime grip; revised hands await player review |
| [ESC UI priority](escape-ui-priority/README.md) | Fixed for current UI / scoped checks | Close active UI first; a fresh ESC opens pause only after returning to gameplay |
| [Backpack/toolbelt separation](inventory-backpack-separation/README.md) | Implemented / scoped checks | Container inventories show backpack slots only, not duplicated toolbelt contents |
| [World interaction hints](world-interaction-hints/README.md) | Improved / partial | E toggles container UI; harvest-only grass no longer intercepts stone/flower pickups |
| [Black terrain patches while mining](terrain-mining-dark-patches/README.md) | Improved / partial | 2026-10-26: recurrence gets user-approved faint cave visibility; latest images await review |
| [Pickaxe hits without excavation](pickaxe-no-op/README.md) | Fixed for reproduced case | 2026-10-26: saved-pose checks pass; reopen for another failing contact |
| [Terrain/road fit to building grid](terrain-road-grid-fit/README.md) | Improved / unresolved | Default improvement accepted; shoulder still fails |

This initial index is not the entire backlog. Other work remains in
[foundation status](../docs/WORLD_FOUNDATION_STATUS.md).

## Conventions

- Start from [TEMPLATE.md](TEMPLATE.md); keep summaries concise and folders stable.
- Embed a few relevant local `images/` files with captions: world/seed/location,
  build, settings, and baseline/improvement/rejected status. Mark unknowns.
- Prefer matching viewpoints and settings; label mismatches. Preserve original
  pixels and older iterations. Keep source paths and SHA-256 in `images/manifest.json`.
- Keep real images here, not temporary-file links. Do not commit private saves.
- Link existing technical logs, tests and code; do not relocate historical evidence.
- Update this index, issue summary and linked foundation status together.
- Keep user feedback separate from engineering checks. A scoped fix is not an
  all-world guarantee. Partial/unresolved stays open; a regression reopens its folder.
- Mark **Resolved** only with explicit scope, closing evidence and required visual
  approval. Preserve rejected trials and remaining limits instead of hiding them.

`.gdignore` and export exclusions keep the archive outside game resources.

- [First firearm and volumetric explosive destruction](explosive-combat/README.md) ([open first-publication shoreline and latency regressions](explosive-combat/water-plan.md), [packaged editor, both shores and cut views](../docs/REAL_TIME_TERRAIN_AND_WATER_EDITING.md#packaged-strategy-editor-results)) — Installed package / scoped checks pass, 2026-11-01. Source and actual game executable each pass 33 combat + 11 save/reopen checks; native and melee/quest regressions pass. Packaged rifle/reload/blast/crater images reviewed; optional integrity defaults off. User visual review remains separate. 2026-11-10: [installed remote-blast fix and opt-in water settling](explosive-combat/distance-water-2026-11-10.md); package verified and installed; water timing and shallow-surface qualification pending. Player shoreline/teleport/contact repair installed and verified (2026-11-13): [current evidence](explosive-combat/water-repair-2026-11-13.md). Actual saved-world coast-to-lake and barrel sequence passes with unchanged original save; contact captures inspected. Combat p99 18.691 ms and water main peak 2.141 ms leave performance tails open; user visual approval remains separate.

- [Ranger automatic assault rifle](ranger-assault-rifle/README.md) — Installed original model, automatic fire and independent ammunition state. November 3 follow-up auto-equips the trader gift and reloads on an empty trigger; targeted source 27 and actual executable 28 checks pass, with broad results and retained harness failures linked in the issue. Source and actual executable each pass 51 combat + 12 reopen checks; native/presentation 79. Final aim/reload images reviewed; user visual review separate.

- [Dev Bag full-stack shortcut](dev-bag-full-stack/README.md) — Installed: Shift-click grants the registered stack, including 999 ammo. All 12 source and actual-executable checks pass; normal quantity and atomic capacity behavior preserved.

- [Carried objects and shoreline placement](carried-object-placement/README.md) - Installed / scoped source and packaged checks: grid/free previews, furniture Dev Bag entries, slope support and obstruction. Water remains qualification-only; distant tree loss not reproduced. Natural-shoreline user review pending.

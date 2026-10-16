> 2026-10-16 entity/construction integration: one actor and two head-on actors
> complete patrol crossing/return over the12 m timber bridge using normal
> block stairs and native routing. Capsule separation, support and existing
> work/body bounds pass; no runtime change was needed. Evidence:
> evidence/actor_bridge/. This does not qualify dense crowds or frame timing.

> 2026-10-16 entity behavior: native two-point patrol is available through
> development UI, preserving endpoints/current leg in compound saves. Four
> rendered legs, mid-patrol restore, inactive/unready behavior, actual-world UI
> authoring/fresh reopen and release order storage checks pass. Local1-16 m
> routes only; crowd/endurance/multiplayer remain unqualified. Evidence:
> evidence/actor_patrol/.

> 2026-10-16 construction coverage: timber footbridge is selectable in the main
> world.92 ordinary wood blocks,12 m deck, stairs and block railings; paid
> placement, no-jump crossing/return, lateral containment and fresh-process
> rotated persistence pass. Manual bank siting only; automatic bridging and
> vehicle/scale qualification remain open. Evidence: evidence/timber_bridge/.

> 2026-10-16 addon support: clean structures dependency ZIP loads104 resources
> and passes99 graphical shape/door/window/fence/rail assertions. Fixed the
> session menu hard-coded demo-browser dependency through a host-supplied path;
> main-world save/browser/reopen regression and all6 package tests pass. Evidence:
> evidence/building_bundle_current/. Distribution support remains Windows4.7;
> exported-game, other platforms and sustained performance are unqualified.

> 2026-10-16 construction coverage: native round column shape 7 is available
> in construction UI, with existing materials/costs, chunk rendering, collision,
> picking, editing/history and save/prefab paths. Targeted graphical and legacy
> mesh checks pass; dense-column performance remains unqualified. Evidence:
> evidence/block_cylinder/. Water remains deferred.

> 2026-10-16 combined regression after native building changes: gather/craft/
> paid-build/chest, cottage walking,12 m drive/brake/reverse/return, and fresh
> compound reopen pass on a source-preserving clone. Reverse failure did not
> recur and remains unexplained; no vehicle fix claimed. Terrain receive hitches
>133–160 ms remain. Evidence: evidence/mixed_gameplay_current/. Stop repeating
> this unchanged route; continue uncovered project work.

> 2026-10-16 local building readiness: native queries use addressed chunk-map
> lookups when cheaper than scanning authored records. 1000 local queries in a
> 512-chunk world perform1000 probes; wide/negative/transformed/dirty/unloaded
> regressions pass. Debug/release rebuilt. Work-count evidence only, not frame
> or thermal qualification. Evidence: evidence/building_readiness_scaling/.

> 2026-10-16 native building idle cost: collision selection now sleeps after
> settling and wakes on focus/radius/geometry changes. 512-chunk regression and
> 480-piece streaming test pass. 64 towers/4480 models report zero idle scans,
> frame p95 16.744 ms in one short run. Prior timing variation prevents attributing
> the full frame result or closing intermittent hitches/thermal gates. Evidence:
> evidence/building_collision_idle/.

> 2026-10-16 stair-rail integration: a quarter-turned tower placed in the actual
> persistent world retains exact rail identities/transforms and tower blocks
> after save/browser return/fresh reopen. All four rail physics rays pass before
> and after reload. Elevated free-placement fixture; grounded/paid/dense behavior
> remains unqualified. Evidence: evidence/tower_rail_persistence/.

> 2026-10-16 building access: new furnished towers gain sloping flight rails in
> addition to existing landing guards. Three floors now have70 attachments;
> four additional batched meshes and16 top-bar collision shapes. Placement,
> normal ascent/descent and four lateral-fall checks pass. Saved towers unchanged;
> dense/rotated/main-world persistence qualification remains open. Evidence:
> evidence/tower_stair_rails/ (including rejected whole-proxy attempt).

> 2026-10-16 world navigation: Actions > Session > World browser saves before
> returning, frees the old world, and retains changes on fresh reopen. Save
> failure stays in-session with feedback. Actual return/reopen route and stubbed
> failure guards pass; no performance or real disk-exhaustion claim. Evidence:
> evidence/world_browser_departure/. Water remains unchanged.

> 2026-10-16 browser launch verification: production command policy starts two
> sequential graphical processes; generator1/seed7129 and changed inventory
> survive ordinary compound save and fresh reopen. Both use 1080p fullscreen.
> Observing SceneTree substitutes for direct scene startup; actual mouse click,
> all presets and performance are not certified. Evidence: evidence/world_browser_route/.

> 2026-10-16 world entry UI: project starts at a saved-world browser with named
> creation, seed/preset selection and gameplay-cost selection. Existing launchers
> remain direct. Policy/UI checks and 1080p visual inspection pass; process
> handoff and full browser-driven save/reopen remain unqualified. See WORLD_BROWSER.md.
> Water remains deferred; doors/windows are already integrated.

> 2026-10-15 storage coverage: optional terrain mesh cache writes now check a
> native caller-available disk-space query and preserve a default 1 GiB reserve.
> Low/unknown space keeps reads available and throttles retries. Threshold,
> recovery, quota/ownership and junction checks pass; actual disk exhaustion,
> external-writer races, canonical-save space safety and endurance remain open.
> Evidence: evidence/cache_free_reserve/. Water is unchanged.

> 2026-10-15 cave round trip: direct return catches on mined floor edge; explicit
> walking detour around the excavation permits normal ascent. Surface position,
> inventory/wear and edited density restore after fresh reopen. Both results
> retained: evidence/natural_ore_return/. No movement/water runtime changes.
> Root README now lists playable checkpoints and current unified controls.

> 2026-10-15 continuous cave iron route: saved entrance to ore via ordinary
> walking passes without relocation/flying/jumps/terrain access edits.101 sampled
> contacts grounded; pickaxe yields2 iron; exact inventory and27 edited density
> samples restore in a fresh process. Known waypoints, not human discovery.
> Copper route/return walk and performance remain open. Evidence: evidence/natural_ore_walk/.

> 2026-10-15 natural cave ore: read-only survey finds exposed iron/copper without
> authored tunnels. Actual pickaxe strikes yield2 iron/1 copper with exact native
> reward counts and tool wear. Fresh process restores inventory and54 sampled
> edited density values; source save unchanged. Relocated fixture, not continuous
> discovery. HUD30/46 and153 ms reopen hitch mean no performance pass.
> Evidence: evidence/natural_ore_gameplay/. Next coverage: entrance-to-ore walk.

> 2026-10-15 persistent cave checkpoint: Play Natural Caves.cmd creates and
> verifies a separate generator6 save, then opens ordinary gameplay preserving
> edits. Grounded entrance pose and exact inventory survive fresh-process reopen;
> repeated preparation preserves the save hash. Three publication safety checks
> pass. Existing startup capture rejections/123 ms receive hitch remain recorded.
> Next: natural ore excavation plus reward/terrain persistence in this save.
> See NATURAL_CAVE_GAMEPLAY.md and evidence/natural_cave_preparation/.

> 2026-10-15 actor investigation disposition: 256 vs 1024 collision triangles
> gives inconsistent contact-cost changes; both fail actor budgets. Resident
> shapes rise 252 to 814 with identical triangle counts. Keep default 1024 and
> active actor cap 16. Stop automatic collision tuning; preserve this open gate.
> Next deliverable: main-world underground exploration/material gathering and
> save/reload coverage using existing caves/geology, without water changes.
> Evidence: evidence/actor_collision_piece_size/.

> 2026-10-15 route startup diagnosis: the 16-actor travel shortfall includes
> .53–.55 s of bounded planning. After readiness, all actors move 4.72–5.04 m
> in two seconds, grounded; startup passes a separate 1 s gate. Runtime unchanged.
> Terrain contact still fails actor cost gates; old end-to-end failures retained.
> Evidence: evidence/actor_contact_startup/.

> 2026-10-15 controlled actor contact: test-only fixed active/background 60 FPS
> caps restore 17–18 ms frame p95; actor budget still fails. Terrain/box/terrain
> diagnostics show motion p95 .820/.270/.844 ms, with similar grounded travel
> of 3.3–3.6 m that FAILS the >4 m fixture requirement. No runtime optimization
> or capacity increase. Evidence: evidence/actor_contact_comparison/.

> 2026-10-15 actor benchmark correction: actor updates now run on every engine
> physics callback with its supplied delta, summing all ticks per rendered frame.
> A completed run recorded four physics ticks per frame at 15 FPS even in the
> empty control. Budget gates fail; it is not comparable to the earlier 60 FPS
> run. Rendering conditions require investigation before optimizing movement.
> Evidence: evidence/actor_physics_cadence/. Runtime and active capacity unchanged.

> 2026-10-15 mixed actor cost: 0/16/64-record phases in the eight-building world
> retain the fixed 16-body cap with no readiness holds. Actor cost FAILS the
> existing 1 ms p95 budget (1.177 / 1.306 ms); moving16 max 3.082 ms also fails
> 2 ms. Frame p95 17.201 / 17.082 ms passes only the short fixture gate. Dominant
> measured component is collision/motion. Evidence: evidence/mixed_actor_cost/.
> Keep active capacity unchanged; larger crowds and sustained 60 FPS unqualified.

> 2026-10-15 actor removal: reproduced orphan damage after editor deletion.
> Editor/combat now share identity-based removal and clear orders, durability,
> selection and visuals. Stale hits reject before tool wear or damage allocation.
> Real-world ray/UI and combat checks preserve 80 coincident neighboring records.
> Evidence: evidence/actor_removal/. No broader AI/population qualification.

> 2026-10-15 furnished capture: editor capture now includes whole static model
> objects alongside blocks using native region-bound filtering. Cottage capture
> retains 13 objects, exact relative transforms under a rotated parent, library
> reload and rotated placement. Partial/unloaded objects reject instead of being
> omitted. Evidence: evidence/furnished_capture/. Captures geometry, not contents
> or live instance state; object-only capture and dense capture timing remain open.

> 2026-10-15 prefab publication: reproduced save/load mismatch for an asset with
> metadata exceeding the library's 8 MiB read limit. Authoring now stages, reopens,
> verifies geometry/attachments/title/metadata, then publishes; failed output is
> removed. Capture/stack/archive and settlement worker regressions pass. Evidence:
> evidence/prefab_publication/. No crash-durability or multi-writer guarantee.

> 2026-10-15 settlement capacity preflight: native metadata counts use the same
> seeded selection as composition and reject layouts above existing 262,144-block
> or 4,096-attachment limits before record copies/worker launch. UI reports the
> limit in the open dialog. Nine count/composition comparisons, independent
> model/block rejections and existing 26-check network regression pass. Evidence:
> evidence/settlement_capacity/. This does not raise city-generation capacity.

> 2026-10-15 settlement editor: visible layout naming, single-click building
> selection and cottage/mixed presets expose the verified layout through the UI.
> No prior prefab selection required. Empty choices stay open with feedback.
> Preset signal/native composition reproduces 6,771 blocks / 263 attachments;
> existing custom frontage checks pass. Evidence: evidence/settlement_presets/.

> 2026-10-15 mixed gameplay route: two fresh-copy runs complete earned gathering,
> crafting, paid construction, chest transfers, walking, driving/reversing and
> exact restart persistence in the eight-building neighborhood. An earlier run
> failed its reverse-return check; cause remains unresolved, not fixed by the
> later passes. Bounded reverse input/support/readiness telemetry is now retained.
> Evidence: evidence/mixed_gameplay_route/. No broad travel or frame-time closure.

> 2026-10-15 mixed neighborhood: offline preparation now supports five cottages
> and three furnished towers on connected graded streets, with 6,771 blocks and
> 263 attached objects. Fresh-process exact restore and all eight street-to-door
> player approaches pass. Review Mixed Neighborhood.cmd preserves a separate save.
> Evidence: evidence/mixed_neighborhood/. Cold preparation took 93 s, reopen
> verification 34 s; no loading-speed, city-density or frame-time qualification.

> 2026-10-15 wooden fence: production object catalog now includes a baked,
> batched two-metre fence section, four-wood gameplay cost, two-wood salvage,
> static collision and shared atlas icon. Targeted placement/damage/wear and
> object-menu checks pass. Evidence: evidence/wooden_fence/. No new per-frame
> script or per-rail physics bodies; settlement generation and density remain
> separate work. Water remains deferred as requested.

> 2026-10-15 door occupancy: native toggles now query the physics broadphase
> for active actor/vehicle layers before mutation (one result, click-time only).
> Opening/closing rejection preserves model and hinge snapshots; fixture fails
> before the fix and passes after. Generated-settlement actor entry/exit remains
> passing. Both builds updated. Evidence: evidence/door_occupancy/. Tests use
> representative collision-layer bodies for rejection; no population cost claim.

> 2026-10-15 actor/door integration: one native actor in the generated enclosed
> settlement stays outside a closed door, enters after the hinge changes, stays
> inside after closing, and returns downstairs after reopening. Existing model
> change invalidation recovers the route; planner work <=12. Evidence:
> evidence/actor_doors/. No runtime change required. Doors are toggled by the
> fixture, not actor AI; auto-opening, crowds and performance remain unqualified.

> 2026-10-15 correction and combined-route PASS: the earlier 'cottage Y79'
> diagnosis was wrong; that was a changed review-save PLAYER position. Actual
> saved doors are Y49 and terrain/roads Y47; generator4 restores correctly.
> Source hashes show the review changed after publication (also one door removed).
> Its progress is preserved. A clone of the retained ORIGINAL staging checkpoint
> passes gather/craft/place/chest, door opening, walking, ~9 m drive/reverse/return
> and fresh reopen with exact inventory/storage/door state. Evidence:
> evidence/enclosed_combined_pass/. No runtime height correction was needed.
> This short route does not qualify long-distance travel, crowds or performance.

> SUPERSEDED DIAGNOSIS — 2026-10-15 enclosed combined route FAILS before travel: gathering finds no
> stones within 25 m of saved cottage spawn Y79.5. Nearest natural stones are
> around Y47.6; asynchronous native terrain rays confirm those ground heights.
> The enclosed-generation save/reopen and entrance tests did not prove connection
> to surrounding terrain. Investigate grading/generation/persistence height
> agreement before calling this a coherent gameplay checkpoint. Source review
> unchanged. Evidence: evidence/enclosed_combined_route/. No performance or
> route closure; do not merely widen gathering radius to hide the mismatch.

> 2026-10-15 generated entrance correction: real held-W approach exposed door
> protection rejecting all four players touching a closed door. Door interaction
> now uses actual capsule radius, without an extra inflated leaf margin. Four
> stair approaches, normal E opening and production-controller interior walks
> pass on a cloned settlement. Occupied closing regression still passes; both
> native builds updated. Evidence: evidence/enclosed_settlement_walk/.
> Source review save unchanged; actor access and general travel remain open.

> 2026-10-15 enclosed settlement: fresh combined-world preparation now chooses
> cottages with doors/windows and verifies their snapshots on fresh reopen.
> Review Enclosed Settlement.cmd prepares/opens a separate exclusive save;
> existing combined_gameplay is retained. Grading, staged placement and exact
> disk reopen pass; inspected furnished interior. Six preparation safety tests
> pass. Evidence: evidence/enclosed_settlement/. Whole-settlement entrance walks,
> driving and actor routes with the new closed doors remain unqualified.

> 2026-10-15 structures distribution: current dependency ZIP passes clean
> extracted import/load (102 resources) and 12 runtime building checks: native
> world, catalogs/icons, closed/open door collision and exact hinge/model restore.
> Explicit 100 ms import-frame-delay workaround retained. Evidence:
> evidence/building_bundle/. Does not qualify host adapters, exports, other
> platforms, default import reliability or broad addon independence.

> 2026-10-15 building salvage: shared attack/removal now recovers 3 wood from
> doors, 2 wood from windows and 2 metal from guardrails via existing native
> salvage transactions. Successful door removal clears its hinge state. Actual
> world ray targeting, repeated attack, tool wear, protected rejection and
> duplicate-reward rejection pass. Evidence: evidence/building_salvage/.
> Whole-window destruction only; glass-only breakage remains unimplemented.

> 2026-10-15 object chooser: two columns, larger baked icons and cost tooltips
> replace thin rows. Normal-world 1080p test confirms workspace bounds, every
> choice scrolls into view, button signals select corresponding models and
> returning to world retains the selection. Render inspected. Evidence:
> evidence/building_object_menu/. No placement/physics or water changes.

> 2026-10-15 building object icons: windows, doors and guardrails now resolve
> baked icons through their production catalog titles. Actual model renders
> share the existing atlas (1024x640, 2.5 MiB uncompressed, +0.5 MiB); no runtime
> icon viewports. Rendered catalog inspected and lookup checks pass. Evidence:
> evidence/building_icons/. No new gameplay inventory identities or crafting
> mechanics are implied; this completes the object chooser's missing images.

> 2026-10-15 player collision readiness: production controller preserves held W
> while a nearby model awaits collision, then resumes walking without another
> key press. Normal-world rendered 1080p check passes. Evidence:
> evidence/player_structure_readiness/. Admission was deliberately delayed for
> one real window fixture; this is not continuous dense-city travel, vehicle,
> multiplayer, or performance qualification. Water remains parked.

> 2026-10-15 dense collision travel: all five abrupt focus relocations across
> 64 towers become ready within 32/15/6/6/6 observation frames; body/shape caps
> and per-physics-tick creation budgets hold. Cold readiness is not instant.
> Evidence: evidence/tower_collision_travel/. This checks production readiness,
> not actual player freeze/resume behaviour; that integration check remains open.

> 2026-10-15 shadow isolation: same-scene baseline/disabled/repeated-baseline
> comparison added. Model-shadow draw cost is real (833→502 draws), but GPU
> savings vary substantially between runs; window-only GPU benefit unproven.
> First baseline frame p95 still fails 20 ms; repeat passes. Evidence:
> evidence/tower_shadow_cost/. Keep production shadows; no stable hitch cause
> or thermal/headroom qualification established. Avoid a visual downgrade based
> on these short, variable samples.

> 2026-10-15 tower density diagnostic: 1/16/64 furnished towers tested at 1080p.
> Instrumented 64-tower run FAILS frame p95 diagnostic threshold: 25.818 ms,
> viewport GPU p95 8.518 ms, 833 draws; nearest complete tower collision is ready.
> Window collision reaches 256-body cap (837 deferred candidates at 64 towers).
> Evidence: evidence/tower_density/. No dense-city performance approval; next is
> a controlled cost comparison. No runtime settings changed to hide the failure.

> 2026-10-15 tower guards: reusable batched metal guardrails now protect upper
> shaft sides and the top rear edge. Full traversal and three deliberate fall
> approaches pass; main-world ascent/descent and exact guard snapshot restoration
> pass. `Review Tower.cmd` now opens tower_review_guarded, preserving the previous
> tower_review save. Evidence: evidence/tower_guards/. Human review still open.

> 2026-10-15 grounded tower: editor grading/placement, main-world native walking
> from entrance to third floor and back, plus fresh-process door/window restore
> pass. `Review Tower.cmd` opens separately published tower_review. Evidence:
> evidence/tower_review/. Exterior capture is foliage-obscured; human visual review,
> stairwell guards and scale qualification remain open. Cottage review unchanged.

> 2026-10-15 tower enclosure: closed roof/front façade, removed the unused top
> stair flight, and added hinged ground-floor entrance plus approach step.
> Twenty checks pass including entrance and full stair route; inspected rendered
> 1920x1080 assembly. Evidence: evidence/enclosed_tower/. Grounded tower placement,
> human review, and combined-world scale qualification remain pending.

> 2026-10-15 furnished tower: three-floor prefab now includes 60 attached
> furnishings, storage and windows. Full native capsule ascent/descent through
> both landings passes with all attachment collisions resident (14 checks).
> Evidence: evidence/furnished_tower/. This remains an open tower shell: roof,
> front façade/entry, ground placement and rendered review are still pending.

> 2026-10-15 grounded building review: `Review Buildings.cmd` opens a separately
> published building_review save. Normal editor survey, grading and supported
> placement passed, followed by capsule entrance and fresh disk reopen checks.
> Normalized the enclosed prefab foundation to local Y=0 so site preparation
> accepts it. Evidence: evidence/building_review/. Human review and furnished
> multi-storey tower remain open; no water changes.

> 2026-10-15 enclosed cottage: new prefab combines furniture, chest, fitted door
> and eight glazed windows. Capsule walks through the opened doorway; normal
> compound disk save and fresh process restore preserve hinge/door/window state.
> Restored door closes via E. Source world unchanged. Evidence:
> evidence/enclosed_cottage/. Elevated clone-only fixture isolates geometry;
> grounded human review and furnished multi-storey tower remain pending.

> 2026-10-15 doors: native hinged-door state now drives batched wooden doors from
> normal E interaction. Stable identity, local hinge, player swing protection,
> snapshot restore and 100 drift-free cycles pass; normal-world interaction and
> compound capture pass. Evidence: evidence/hinged_doors/. Actual disk restart,
> furnished building integration and visual review remain pending. No water changes.

> 2026-10-15 building components: added baked wood/glass window to the normal
> object palette and prefab recipes, using existing native batch persistence,
> collision and object destruction. Ten headless checks pass (evidence/window_component/).
> This is a component increment, not finished buildings: visual review, furnished
> tower integration, functional doors and independent glass breakage remain open.
> Water stays parked at the user's accepted state.

> 2026-10-15 tower coverage audit: prior3-floor fixture walked only1 flight.
> Extended native capsule route now reaches third floor and returns through
> both landings/flights;8 checks pass with unchanged runtime/prefab. First test
> settling failure retained. Evidence: evidence/tower_full_access/. This is
> headless access only; furnished main-world tower remains the next M2 gap.

> 2026-10-15 moving vehicle route invalidation: native pose changes publish
> old/new bounds; unchanged parked cars do not restart routes. Main-world wiring
> and bounded replanning pass; release fleet19 checks pass. Evidence:
> evidence/vehicle_route_invalidation/. Traffic AI/damage still open; water unchanged.

> 2026-10-15 actor/vehicle boundary: actor bodies and route checks now include
> vehicle collision; chassis/placement/exit queries include actors. Retained
> pass-through baseline now passes; route detour and main-world occupied-exit
> checks pass. Traffic AI/damage remain open. Evidence: evidence/actor_vehicle_collision/.
> Water unchanged.

> 2026-10-15 settlement actor review ready: HUD enable/place/select/send reaches
> a real street destination; normal compound save and fresh-process reopen retain
> exact actor/order snapshots. Review Settlement Actors.cmd opens a separate copy.
> Startup hitches remain; no performance claim. See SETTLEMENT_ACTORS.md and
> evidence/settlement_actor_authoring/. Water unchanged.

> 2026-10-15 actor development UI: dev slot9 now groups actor authoring controls
> in a persistent HUD. Selection/removal use exact native hit identity. Real-world
> button-signal regression passes with80 coincident dormant records. Visual1080p
> layout checked. Evidence: evidence/actor_authoring_ui/. Water unchanged.

> 2026-10-15 straight waypoint correction: bounded advancement prevents chasing
> passed intermediate samples. Continuous-physics crossing passes 16/16;
> separation >=0.786m, adapter p95/max 0.869/1.401ms, frame17.678/55.052ms.
> Cottage stairs/doorway all six checks pass. Evidence: evidence/actor_waypoint_progress/.
> One bounded result, not endurance or hitch-free qualification. Water unchanged.

> 2026-10-15 crowd timing correction: screenshot writing caused the largest
> prior interval. Independent frame sampling now records p95/max17.657/60.289ms;
> profiled adapter1.048/2.487ms still fails. Continuous physics finishes14/16,
> so arrival remains unqualified. Evidence: evidence/actor_crowd_timing/.
> No runtime optimization claim. Next inspect late waypoint progress and native
> movement/readiness cost; engine periodic maxima are not frame samples.

> 2026-10-15 sixteen-actor crossing exposed arrival drift. Stopped actors now
> hold position with higher avoidance priority; all16 complete, separation
> remains >=0.786m. Cost gates FAIL: frame p95 37.346ms, adapter p95/max
> 1.205/2.672ms. No performance qualification; next attribute adapter, deferred
> avoidance and full-world stalls before optimization. Evidence:
> evidence/actor_crowd_arrival/. Water unchanged.

> 2026-10-15 local actor avoidance is integrated: native active proxies now
> avoid each other and retain mutual collision. Opposing routes pass on the
> actual settlement street (minimum 0.800 m separation); cottage access and
> sleeping/reactivation checks pass. Evidence: evidence/actor_avoidance/.
> Dense crowds, narrow opposing doorways and runtime cost remain unqualified.
> Water unchanged; no entity-population completion claim.

> 2026-10-15 interacting-entity identity fix: attacks now resolve the actual
> hit native body directly, without a capped position lookup. An actual-world
> 80-coincident-record failure now passes; only the hit actor is destroyed.
> Debug/release checks reject foreign stores and stale/reused handles. Evidence:
> evidence/actor_attack_identity/. Crowd avoidance and population qualification
> remain open; water unchanged.

> 2026-10-15 settlement travel checkpoint: existing road authoring creates a
> 112 m extension; normal vehicle input drives 113.90 m including braking across
> seven terrain regions. Fresh reopen restores road entrances, vehicle and saved
> player pose. Review Settlement Road.cmd opens a separate retained copy.
> See SETTLEMENT_ROAD_TRIP.md; short coverage, not long-run qualification.
> Water remains deferred.

> 2026-10-15 general saved-world cache preparation added. Read-only normal
> world loading prepares saved spawn/ordinary terrain coverage; optional fresh
> graphical verification reports cache reuse and unchanged canonical hash.
> Isolated settlement run:584 cold writes; warm292 hits/0 misses/0 writes.
> Evidence: evidence/world_preparation/. Warm receive hitch128.7ms remains;
> no instant-loading, whole-world baking or performance qualification claim.

> 2026-10-15 pickup setup is transactional: late resource/provider failure
> leaves no pickup stores, scene nodes or partial save registrations. Native
> state stays staged until the full registration batch validates. Failure/retry
> checks, 92 bundled item checks and the copied settlement gather/build/store/
> travel/fresh-reopen regression pass. Source save unchanged. Evidence:
> evidence/pickup_initialization/. No steady-state simulation changes.

> 2026-10-15 dropped-item bundle follow-up fixed binary asset omissions:
> baked drop meshes referenced building textures and woodland shader outside
> declared bundles. Required assets are now included without whole runtime
> addons. Clean ZIP loads 54 resources; all 23 dropped types pass 92 native
> transfer/render/snapshot checks. Six packaging guards pass. Evidence:
> evidence/addon_pickup_exercise/. Main-world/export/scale gates remain open.

> 2026-10-15 packaging regression fixed: current dropped-item scripts made
> world_runtime depend on player_runtime/water assets, omitted by its ZIP.
> Explicit dependencies now include those and structures/player dependencies.
> Five package checks pass; clean world_runtime import/resource load and actual
> two-actor navigation pass from extracted ZIP using the documented import
> workaround. Evidence: evidence/addon_runtime_exercise/. Other runtime adapter
> contracts, export and scale qualification remain open.

> 2026-10-15 ore reach diagnosis: both collision and native density queries
> find the excavated face beyond 3.5m reach. Walking forward with normal
> collision restores targeting; mining, crafting, placement and fresh reload
> pass. Evidence: evidence/geology_crafting_route/reach_*. Gameplay reach
> unchanged. Continue content coverage; general mining/performance stays open.

> 2026-10-15 ore crafting follow-up remains open: two earned ores of each type
> can craft metal through UI, place a metal block and restore it/inventory in
> a fresh process. However a visual rerun loses the subsequent terrain target
> before acquiring enough ore. Evidence: evidence/geology_crafting_route/.
> Investigate ray reach and collision publication timing; do not call this
> route reliable or repeat unchanged. Water remains deferred.

> 2026-10-15 ore gameplay checkpoint: ordinary pickaxe attacks on the prepared
> iron and copper faces yield the correct items directly, with tool wear and
> no unclaimed rewards. Exact inventory survives fresh-process compound reload.
> Tested on a copy; source checkpoint unchanged. Evidence:
> evidence/geology_rewards_route/. This covers two strikes, not sustained mining
> or natural discovery; faceted ore visuals and startup hitches remain open.

> 2026-10-15 geology checkpoint portability: Prepare Geology Checkpoint.cmd
> authors iron/copper access tunnels in a staging save, verifies both walks
> after fresh-process reopening, then publishes only if gameplay is absent.
> Play Geology Checkpoint.cmd now supports that save; historical saves retain
> precedence. Evidence: evidence/geology_preparation/. Ore reward interaction,
> natural discovery and visual quality still need integrated qualification.

> 2026-10-15 cave human checkpoint: Review Natural Caves.cmd starts on foot
> outside generator6 cave0 in a disposable world. Startup visual check passes;
> normal walking to 60 metres inside and back passes six waypoints. Evidence:
> evidence/natural_cave_review/. Human review, broader cave coverage, discovery
> from settlement and visual polish remain open. Water stays deferred.

> 2026-10-15 cave entrance fix: opt-in generator 6 lifts the radius-7 mouth
> capsule while preserving generator 1-5 geometry. Four seed-1703 sampled mouths
> lose their steep lips; actual cave-0 walking in/out now passes. Debug/release
> legacy identity, new seed determinism, native snapshot roundtrip and cache
> separation pass. `evidence/cave_generator_v6/` records scope and remaining
> visual/streaming limitations. Default and saved worlds remain unchanged. Next
> make the cave checkpoint convenient for human review and cover deeper access;
> do not treat one entrance as full cave/discovery completion.

> 2026-10-15 natural cave access is now a reproduced content gap. Four seeded
> entrance centreline scans have steep lips; actual main-world walking enters
> cave 0 but cannot return to the exterior without jumping/edits. Retained failure:
> `evidence/natural_cave_access/`. Next implement a versioned new-world cave-mouth
> profile and rerun this exact route, preserving all existing saved generator
> geometry and player collision rules. No water work is part of this slice.

> 2026-10-15 connected local travel passes: after the earned-resource route, the
> player walks out of the furnished cottage, places/enters a car, drives 9 m and
> reverses back, exits, and walks back up stairs into the cottage. No pose
> correction during travel. Fresh-process resource/block restoration still passes;
> source gameplay save unchanged. `evidence/combined_travel_route/` retains the
> initial off-centre test-waypoint failure and corrected route. This is a local
> integration checkpoint ready for human review, not region/high-speed or M4/M5
> performance qualification. Resume missing content coverage rather than rerun
> this passing loop; natural cave discovery remains unverified.

> 2026-10-15 connected resource checkpoint: in a copy of the prepared settlement,
> normal E gathering, crafting UI, held-brick right-click placement and existing
> cottage chest deposit/withdraw now pass together. Fresh-process exact inventory,
> chest contents, natural removal identities and placed-block restoration pass;
> source gameplay save unchanged. Evidence: `evidence/combined_resource_route/`.
> Fixture positioning does not prove walking/driving. Next: continuous road
> departure/return with earned contents and movement-based building access.

> 2026-10-15 implementation checkpoint: `Prepare Combined Gameplay.cmd` now
> reproduces the furnished settlement from the existing editor/native generation
> path, verifies a fresh-process reopen, then publishes only if gameplay progress
> is absent. The generated-world catalog API regression is fixed. Gameplay-mode
> reopen and launcher resolution pass; see `evidence/combined_preparation/`.
> Early autosave rejections, cold preparation and startup hitches are retained.
> Next remains the connected gather/build/store/drive route; not full M2/M3 closure.

## Current priority - 2026-10-15: resume the combined gameplay world

The user accepts water as good enough for now and explicitly requests moving on.
This supersedes the active-water priority and next-work statements below. Retain
installed water behavior; no storage migration, flow, meshing, bucket, texture or
performance iteration is scheduled. Known limits remain documented in
WATER_GAMEPLAY.md and evidence/water_shoreline_visual. Acceptance is permission
to advance, not full correctness, scale or thermal certification. Return only
on explicit user request or a blocking regression in ordinary combined gameplay.

Next deliverable: a reproducible playable settlement checkpoint supporting the
existing gather/build/store loop, furnished buildings, roads, vehicles and actors.
Use existing addons and generation/editor paths. Do not add a second implementation.
The 2026-10-15 dry-run of Play Combined Gameplay.cmd failed because its historical
source checkpoint and combined_gameplay save are absent on this computer. First
remove this dependence on another computer's local save through explicit, safe
checkpoint preparation; preserve existing saves and never silently reset progress.
Then verify one short integrated route: gather, build/use a house and chest, drive
away and return, save/reopen. Retain failures and give the user a working launcher
for human review. Do not substitute isolated component checks for that route.

This advances M2/M3 integration toward M4; it does not close the original scope.
Natural cave discovery, detailed settlement scale, actor populations, loading,
mining continuity, multiplayer and sustained 60 FPS remain tracked below.

> Disk-save integration verified, 2026-10-13: the normal compound save/reopen preserves mined terrain, lake water, placed water and a full bucket together. The reloaded bucket pours and the saved placed unit can be scooped completely. Water restores with 52 cache hits and zero terrain samples. Evidence: `evidence/water_pool_recovery/compound_disk_pass.log`. Shared-storage migration remains open.

> Pool recovery correction, 2026-10-13: six adjacent/stacked full-bucket pours, cached reload and complete recovery now pass in the actual world without disconnected remaining surfaces. Shared terrain/water extraction handles disconnected cell corners; scoop planning checks stored and rendered connectivity. Static water and full-unit bucket scope remain unchanged. Full TerrainCore storage migration and broader visual/performance acceptance remain open. See `evidence/water_pool_recovery/status.txt`.

> Fixed-unit scope decision, 2026-10-13: bucket gameplay now transfers one complete 1 m³ unit or nothing. UI shows empty/full; older partial buckets retain their contents and can be refilled. No automatic flow or spillage. Native atomic-transfer checks and actual-world pour/recovery pass. This does not complete the TerrainCore storage migration or certify all water visuals. See `evidence/water_fixed_units/status.txt`. Earlier fractional/litre gameplay requirements below are superseded.

# TerraForest delivery plan and coverage register

Updated 2026-10-11. TerraForest is an integrated development world, not a completed game-ready world engine. The next objective is first-round coverage of the original scope, followed by combined scale and endurance qualification. A coherent playable area demonstrates integration; it does not replace missing systems or reduce the large-world goal.

This is the current delivery-order and coverage reference. [Delivery history](DELIVERY_STATUS.md) records evidence at the time of each change; older entries are not current status. [World systems design](WORLD_SYSTEMS_DESIGN.md) retains the broader architecture contract. A documentation update alone closes no implementation gate.

## Current water implementation and remaining gate - 2026-10-14

Building replacement integration follow-up: compound disk save/reopen with
stairs and spheres, normal bucket clicks beside stairs/slopes/spheres, post
undo/redo, unchanged region paging and resident region replacement now pass.
Solid-aware face connectivity fixes traversal through occupied slope faces and
ceilings. See `evidence/water_structure_replacement/` for current evidence.
Update latency, broader visuals and scale qualification remain open. This
supersedes the older open integration-gate statements below.


Building replacement integration, 2026-10-14: the actual construction path now
deletes water inside all six authored shapes while preserving their empty space.
Actual-world checks and debug/release cached-water reload pass. Full compound
building+water disk saving, reverse bucket interactions, edit history, partial
face connectivity and performance qualification remain open. Current evidence:
`evidence/water_structure_replacement/status.txt`. This supersedes the earlier
prerequisite-only notes below.

Building clipping prerequisite, 2026-10-14: exact convex subtraction is now
available from the terrain water profile, and building hull export shares the
picking planes. Debug/release geometry checks pass. Runtime occupancy, meshing
and save integration remain open; see `evidence/water_structure_clipping/`.

Building replacement decision: constructed solids must delete overlapping water,
matching terrain. The native shape-sampling prerequisite passes debug/release
checks for all six shapes and four rotations, transforms and unloaded regions.
It is not connected to water yet. Remaining work includes representing occupied
intervals around partial/curved shapes, both placement directions, invalidation,
history and compound reload. The current single-interval water profile cannot
represent every building intersection; do not substitute whole-cell deletion.

Terrain replacement policy, 2026-10-14: the user explicitly wants solid terrain
to delete water that it replaces. The former rejection rule is superseded.
Cubes and smooth deposition, pending water snapshot reload, no resurrection
after excavation, and the bucket-pool regression pass. See
`evidence/water_terrain_replacement/status.txt` for scope and limits. This does
not yet integrate separate structure-addon blocks.

Human refill acceptance, 2026-10-14: the user confirms that refilling the
troublesome hole with water collected elsewhere now works predictably. The
reported bucket-refill issue is closed; do not keep treating it as awaiting
review. Evidence: `evidence/water_bank_repair/status.txt`. This does not close
construction occupancy, broader visuals or performance qualification. The
reproduced construction overlap remains failing: see
`evidence/water_structure_occupancy/status.txt`.

The installed game has static water, whole-unit bucket interaction, and compound
save/reload. Actual-world checks cover adjacent/stacked placement, complete recovery,
mined ground, and use after disk reload. Evidence is in
`evidence/water_pool_recovery/` and `evidence/water_static_profiles/`.
The human-review entry point is `Review Water Buckets.cmd`.

The reported underwater bands are corrected by avoiding duplicate environment fog
on resolved water transmission (`evidence/water_underwater_fog/`). The captured
excavation topology defect is corrected in the shared extractor, with three actual
world excavations, repeated bucket recovery, bounded density cases and terrain
cache parity checks (`evidence/water_boundary_fix/`). These are specific verified
fixes, not blanket visual or world-scale acceptance.

Current visual/interaction acceptance still requires clear placed volumes, reliable
targeted whole-unit removal, no unwanted disconnected fragments or contact artifacts,
and persistence after repeated edits. Static water may expose its lower boundary
when supporting terrain is removed: filling the resulting air space would be flow,
which is outside the requested scope. That lower boundary must not acquire the
animated ripples of an upper water surface.


Storage is still NativeRegionalWater; terrain and water share density extraction,
not authoritative storage. Do not claim the storage migration is complete.
The proposed TerrainCore smooth-density replacement still fails all six existing
volume gates on the current build (`evidence/terrain_material_units/current_density_gate.log`).
A one-metre aligned density box produces no surface. Existing explicit TerrainCore
voxels do represent whole units, but switching them into water still needs shoreline,
contact, picking and saved-world conversion work. Do not install the failed density
primitive merely to label the storage unified, or start another volume-fitting solver.

Broader visual acceptance and world-scale/thermal qualification remain open.
No automatic flow, settling or spillage is part of this phase. Historical flow
requirements below are superseded. The earlier water checkpoints below record
prior states; use this section and the newer evidence for current status.

## Active water scope override - 2026-10-13

The user explicitly deferred all spillage and automatic flow for the foreseeable
future. Water stays where placed. Only explicit lake generation, bucket scoop/
pour, development edits and terrain-contact maintenance may change it. Retain
good visuals, low runtime cost, saving and cached loading. Idle water must not
run simulation. Earlier flow-back, drainage, local-settling and outlet-response
gates below are historical and no longer acceptance requirements for this phase.
Current unresolved visual/interaction gates are listed above; earlier failures
are historical unless reproduced on the installed build.

## Historical water checkpoint - 2026-10-13

The user supplied the older `gpu-marching-cubes` project. Its actual GPU brush and
marching-cubes shaders now have a repeatable read-only behavior check. Direct
density edits are the interaction reference; their unequal scoop/pour quantities
are not a conservation model. TerraForest's current density extractor remains
unfinished: closed captured topology, but missing thin layers and inaccurate
small-volume geometry. Do not resume cosmetic fitting/clipping patches or treat
this checkpoint as accepted. See `evidence/water_reference_review/status.txt`.

## Historical water direction correction - 2026-10-13

The user explicitly rejected continued patching of the independent water representation.
Retain the accepted visuals, but replace the interaction/material integration with
terrain-aligned volumetric water, simple local settling and sleeping inactive regions.
Do not describe shared helper calls as proof of a unified terrain/water boundary.
The same visible volume must leave/enter the targeted world area and survive reload.

Cubic-metre transfers and explicit inventory quantities are implemented (743a207).
They do not resolve geometric correctness. The native terrain now exports its own
full-detail boundary through command 32; a 144-triangle comparison passes, but water
does not consume it yet. This is a prerequisite, not a replacement runtime or finished
playable fix. See `evidence/terrain_material_boundary/status.txt`.

The command-32 boundary is now consumed for single-floor contact geometry, with exact triangle volume integration and version-6 caching. The mined-bowl contact gate passes. Multiple floors/walls/ceilings, rendered natural-ground contact, moving-surface scoop reliability and outlet response remain incomplete. See `evidence/water_exact_terrain_contact/status.txt`; the overall acceptance gate remains failing.

## Historical terrain/water correctness checkpoint (2026-10-13)

This section records an earlier implementation and includes superseded flow,
contact-face removal and sloping-reconstruction behavior. Use the current water
section above for implementation status and the no-flow scope.

User priority overrides the earlier feature sequence: resolve the visible and
interactive terrain/water defects before more feature work, texture polish or
performance-only tuning. Efficiency remains an implementation constraint.

Required acceptance in the normal 1920x1080 world:

- No reflective water/terrain-contact bands, floating-looking shards or shore gaps.
- A full bucket poured onto ordinary ground forms readable water that stays
  outside solid terrain; no strip-like or disappearing result accepted.
- Scooping changes the targeted visible area, then connected water flows back;
  a changed inventory number or a briefly recorded dip alone is insufficient.
- Unwanted small detached water/terrain fragments are handled coherently with
  bounded local work. Do not silently erase volume, bridge through solid terrain,
  or mistake a legitimate separate puddle, placed object or terrain island for
  an artifact. No global per-frame component scan.
- Repeated digging, pouring, scooping and cached reload preserve those results.

The underwater-band reproduction is corrected by excluding solid-contact faces
from the existing surface builder and bucket query geometry. Full stored-volume
topology is still audited with the same builder's diagnostic contact-face flag.
This is not a replacement water implementation. The captured gentle-ground pour now stays connected and above terrain using
volume-preserving sloping reconstruction. Its outline is still angular. Per-cell
flow timing now survives CPU-budget deferral, and the 55-check world test passes;
outlet response remains marginal (9.8 seconds from edit submission). General fragment handling and
arbitrary shore/contact accuracy remain incomplete. See
`evidence/water_sloping_pour/status.txt` and
`evidence/water_flow_scheduling/status.txt` for passing and failing evidence.

The volume-scale check now also measures the reconstructed mesh, not just stored
millilitres. The six controlled cases agree within 0.135 percent after correcting
boundary shrinkage; arbitrary terrain geometry remains unqualified. Larger,
useful cube-sized gameplay transfers are pending: replace the legacy eleven
bucket fill IDs with explicit fluid quantity and preserve old saved litres.
See `evidence/water_volume_scale/status.txt`. This is part of the blocking water
work, not a reason to resume unrelated features.

## What counts as first-round coverage

A system needs a usable main-world path, persistent state where appropriate, a small correctness check, a representative performance check, and explicit limits. An isolated addon, API test or visual showcase is supporting evidence, not integrated coverage. User-visible behavior also needs a human checkpoint. Production qualification additionally requires combined workloads, sustained operation and release checks.

Statuses below distinguish **integrated partial** (usable but coverage gates remain), **native partial** (infrastructure exists but gameplay integration remains), and **planned**. No row is certified complete by this register. Later networking implementation is a deliberate sequencing decision, not completion of the original multiplayer requirement.

## Original scope and remaining coverage

| Requirement | Current position | First-round completion gate |
| --- | --- | --- |
| New combined project and independently usable addons | Integrated partial: terrain, forest and companion addons; source projects preserved | Verify documented dependencies, addon isolation and supported Windows build/install paths; retain a full support matrix |
| Volumetric terrain, large caves and mountains | Integrated partial: editable terrain and seeded generation paths | Generate and traverse representative above/below-ground regions; mine nearby and after travel with visual and collision correctness, save and reload |
| Underground materials and veins | Integrated partial: seeded geology and excavation accounting | Demonstrate discoverable material variation, correct appearance/rewards and reproducibility after reload in the playable world |
| Volumetric water and lakes | Integrated partial: native static volumes, whole-unit buckets, mining contact, compound persistence and cached occupancy; see [water gameplay](WATER_GAMEPLAY.md) | Qualify regional paging, structure occupancy, shoreline quality and combined endurance; automatic flow/spillage are deferred; current 0.5 m / 4,096-resident-region limits are explicit |
| Asphalt roads | Integrated partial: native grading/paving and connected street authoring | Drive connected roads across loaded region boundaries, edit/save/reload them, and verify terrain, buildings and vegetation remain consistent |
| Block shapes, prefabs and static model objects | Integrated partial: cubes, slabs, stairs, slopes, posts, spheres, placement/transforms/history and persistence | Author a usable building with interior objects and access features; verify selection, collisions, undo where supported, and persistence through travel |
| Large buildings, towns and cities | Integrated partial: house/tower examples and native connected multi-street settlement authoring | Implement a reproducible settlement generation/authoring workflow with connected roads, supported buildings and usable interiors; measure representative detailed structures, not just empty shells |
| World generator and editor | Integrated partial: generation, terrain editing, construction and site preparation | One reproducible workflow creates, edits, revisits and reloads the combined world; rejected operations leave consistent state |
| Loading, baking and caching | Integrated partial for terrain/blocks and water occupancy; saved spawn preparation command; opt-in main-world model paging with lifecycle barriers | Automatic model region selection, safe save/checkpoint handover and lifetime handling; correct edit invalidation and warm reuse; demonstrate bounded residency and arrival behavior |
| Player, toolbelt, inventory and unified interaction | Integrated partial: movement, UI, pickups/resources and paid gameplay construction separate from free editor | Complete a coherent gather/build/use/save/reload loop across terrain, buildings and objects; verify input focus and unavailable-region behavior |
| Vegetation including stones, plants and grass | Integrated partial: trees plus interactive, persistent stones/plants/grass clumps; native picking and batched ground-cover rendering | Add representative small stones, plants and grass with density/LOD tiers; individual stones, plants and grass clumps must support removal and placement, survive travel/save/reload, and follow gameplay inventory rules while editor placement stays free; verify local mining/building disturbance and combined rendering costs |
| Efficient world representation and storage | Integrated partial: versioned compound snapshots, regional structures, checksums/recovery and derived caches | Demonstrate bounded memory/disk behavior under edit, travel, save and reload; distinguish authoritative records from disposable caches; retain unresolved terrain addressing/delta/compaction requirements |
| High amounts of entities | Integrated partial: persistent actor orders, editor selection, rendered gait, bounded native activation and local walking routes; settlement/crowd navigation unqualified | Integrate representative rendered, interacting entities with activation/sleeping and representative animation/collision work; measure actual work at stated populations |
| Vehicles and high-speed travel | Integrated partial: native driving, persistent fleet identities, opt-in four-body activation and bounded parked visual/static collision batches | Exercise drive/park/reload and repeated travel through combined content; establish bounded activation for multiple vehicles and safe collision arrival behavior |
| Large multiplayer world | Planned implementation; some storage/identity prerequisites exist | During coverage work, audit authority/identity/command boundaries and record violations. Later gate: server plus two clients, edits, late join, loss/reorder, bounded interest/traffic and measured scaling |
| Professional visuals, resilience and headroom | Partial: materials/LOD, lifecycle checks and short graphical evidence | Inspect combined terrain, buildings, vegetation and water; fix visible defects; then qualify frame tails, resource growth and long sessions at documented workloads |
| 60 FPS at 1920 by 1080 fullscreen | Configuration and new-host baseline exist; sustained target unproven | Enforce full-resolution graphical measurements, report frame tails and failures, separate CPU/GPU/power results; qualify sustained target on stated hardware |
| Native hot paths, Zig and prebuilt godot-cpp | Integrated partial: pinned toolchain and multiple native addons; script adapters remain | Profile remaining hot paths and migrate substantial runtime work; preserve native ABI/build reproducibility and mod/UI support boundaries |
| Git publication, licensing and distribution | Git repository published; project code 0BSD with separate dependency/asset notices | Preserve provenance, test clean installation/export and addon distribution; declare supported platforms and actual limits |

Current implementation sources include [project guide](../README.md), [player runtime](../addons/player_runtime/README.md), [vehicle runtime](../addons/vehicle_runtime/README.md), [vegetation runtime](../addons/vegetation_runtime/README.md), [structures](../addons/structures/README.md), and [model bootstrap](MODEL_WORLD_BOOTSTRAP.md). Historical README limitations can lag later delivery entries; current code and scoped evidence determine implementation status.

## Delivery sequence

Only one delivery milestone is active. Supporting work must name the coverage row and completion gate it enables. Work already implemented is reused rather than restarted to fit this sequence.

| Milestone | Deliverable | Exit decision |
| --- | --- | --- |
| M1 Current integration closure ā€” disposition recorded | Dependable human checkpoint and a concrete disposition for opt-in model streaming | Address checkpoint defects as found. Complete automatic model paging/save lifetime integration with targeted evidence, or explicitly retain the existing path and register its limitation and return trigger. Do not enable incomplete paging merely to claim integration |
| M2 World content coverage ā€” open, remaining work retained | Generation, water, roads, structures/static props, vegetation variety and settlement workflow in the same saved world | Close the applicable coverage gates above; report any remaining gap instead of silently moving it to qualification |
| M3 Gameplay and simulation coverage ā€” active actor-navigation slice | Gather/build/use loop, representative active entities and multiple-vehicle activation | Actual rendered behavior, persistence and bounded simulation are demonstrated; an entity count in a native store is insufficient |
| M4 Combined area qualification | Forested settlement, interiors/props, underground terrain, lake, roads, entities and driving | Human checkpoint plus short automated mixed-workload tests; declared scene counts, travel route and frame/resource budgets precede performance runs |
| M5 Scale and release qualification | Increased density/distance, endurance, recovery and distributable build | Stated workloads sustain target behavior; memory/VRAM/disk growth and failures are measured; clean-machine release checks pass |
| M6 Multiplayer implementation and qualification | Authoritative session with interest-managed world/entity state | Server plus two clients and network fault tests first, then measured scaling. Architectural readiness remains a requirement throughout M1ā€“M5 |

M6 is not authorization to market earlier milestones as completing the large-multiplayer goal. Reassess its placement after M4 before release scope is finalized. Likewise, a successful M4 scene does not prove an arbitrary city size.

## Deferred work and return triggers

These items remain open. Deferral is a scheduling choice, never a passing result.

| Open item | Why it is separated | Required return point and closure evidence |
| --- | --- | --- |
| Mining latency after travel and sustained edits | Earlier changes did not establish consistent behavior; avoid another unbounded research detour | M1 short post-flight check retains a continuity failure (328/281 ms maximum gaps); long-distance/endurance behavior remains unqualified. Return at M4, on relevant loading/interaction changes, or earlier ordinary-play blockers. Close only with repeatable response and terrain/collision agreement, including continued edits |
| Automatic model paging and checkpoint handover | Latest native infrastructure is opt-in; default world still requests block metadata only | M1 retains opt-in integration with correctness and modest rendered-route evidence. Reassess activation with M2 detailed content and M4 combined travel, before claiming detailed settlement scaling; preserve focus/save/reload/cancellation/teardown guarantees |
| Model transfer timing and arrival latency | Correctness passes do not close timing failures; the 200,000-record fixture exceeded its 2 ms gate | Before claiming detailed-world streaming capacity in M4, measure frame tails and time to usable collision/visuals at the declared travel workload; preserve failing runs |
| Terrain cache ownership, storage growth and large-world representation | Native ownership and idle eviction now address the full-cache write cutoff; free-space reserve, directory cleanup, hostile/external writers and endurance remain open | M2 loading design and M5 endurance: stale-data rejection, quotas/eviction, disk reserve, recoverability and measured resident/disk growth |
| Dense building rendering, interiors and distant edited representation | Isolated geometry/API checks omit mixed content and actual detail | M2 representative content, M4/M5 scaling. Distant mined terrain and placed structures must remain correct; lower detail cannot silently restore the unedited world |
| Vegetation diversity and disturbance | Tree integration does not cover small plants, grass and stones | M2. Demonstrate density/LOD and local disturbance without broad unrelated disappearance; measure mixed-scene render cost |
| Entity animation, AI, collision and vehicle populations | Storage/kinematic throughput omits much of game simulation | M3 representative behavior; M4/M5 stated populations with activation/sleeping and measured CPU/GPU costs |
| Older-laptop thermal sustainability | New hardware utilization is not comparable, and short runs cannot prove sustained thermals | M5 with target hardware available or explicitly unqualified support. Keep the 60 FPS target; measure watts, temperatures, clocks and frame times where available, not utilization alone |
| Multiplayer authority and multi-world ownership | User prefers later networking implementation | Review boundaries in every relevant milestone. M6 requires real session/fault/scale tests; current single-world scene/cache ownership remains a recorded constraint |
| Fluid flow, drainage and cross-region exchange | Finite connected-basin equilibrium and bucket/save integration playable | Velocity/pressure flow, arbitrary pouring and safe terrain-edit displacement remain open; no whole-fluid or performance completion claim |
| Visual refinement and release support | Working geometry and local binaries are insufficient for a supported release | Visual feedback at each checkpoint; M5 clean-machine packaging, license notices, platform matrix and final visual regression review |

## Rules against indefinite detours

Before an investigation, record the failing behavior, smallest representative reproducer, expected result and the implementation decision it will inform. Begin with a short check; use a long run only for a question that requires duration, such as leakage or thermals.

After one investigation/implementation/verification cycle, either close the gate with evidence or state the remaining cause, next bounded experiment and effect on the active milestone. After two cycles that do not improve the gate, stop extending the approach automatically: reassess the design, retain the current working path with explicit limits, or explain the tradeoff to the user. Do not silently narrow requirements to make a test pass.

Every milestone report lists coverage gates closed, playable changes, evidence and its limits, remaining failures, deferred items whose triggers were reached, and the next deliverable. Keep the launch command and save slot available for human checks. Do not infer human acceptance from successful automated startup.

Hardware changes establish new baselines. Measurements must record build/binary identity, hardware and presentation settings; headless correctness, rendered performance and sustained thermals remain separate evidence. Preserve the 0BSD project license and dependency notices. Do not replace a working build or retag a checkpoint as good without matching evidence.

## Next concrete work

2026-10-11 human vegetation disposition: v3 textured grass is accepted as the
first-pass default, not final realism. Stop texture iterations. Keep F7 available
for comparison. Revisit mesh curvature, smooth leaf shading, blade asymmetry and
terrain contact at the next representative art checkpoint or when ordinary play
exposes a visual blocker. Compare one replacement mesh against the accepted asset
with the same population and measured rendering budget; no vegetation-system rewrite
is implied. Neither art acceptance nor this default change closes performance gates.

2026-10-11 user disposition: the current item/UI/interaction work is good enough
for now; move toward less-developed systems. Pause optional inventory, grass,
hand-model and tool-art refinement. Fix ordinary-play blockers when reported.
This is permission to move development forward, not a declaration that the
combined gameplay or performance gates have all passed.

## Next development slice: actors navigating the existing settlement

The current actor path already has saved identities/orders, native movement,
bounded physics activation, batched visuals and basic limb gait. Reuse these.
The coverage gap is navigating actual settlement geometry; more population
counters or another empty-ground movement demo would not close it.

The next implementation slice supports the original high-entity-count requirement
and M3 simulation coverage while outstanding M2 content gates remain open:

- Give actors a usable destination command through the development UI.
- Navigate a representative existing settlement route around walls and through
  usable openings on supported terrain. Report unreachable targets explicitly.
- Invalidate affected route data after terrain/building edits; stop safely when
  collision or navigation coverage is unavailable. Derived routes must not become
  authoritative saved world state.
- Keep route planning, scheduling and repeated simulation work native, with explicit
  per-update budgets, bounded queues and activation limits. Do not give every stored
  actor permanent active physics or rebuild navigation for the whole world.
- Retain persistent actor identity and destination through travel/save/reload;
  recompute disposable route data as required. Keep commands suitable for later
  server validation without claiming that networking is implemented.

First evidence: a short obstacle route, sealed destination, mid-route edit and
leave/return test in representative world geometry. Record planning latency,
per-frame work, active versus stored actor counts and queue bounds before expanding
population. Include a visible human checkpoint. Stop and reassess after two failed
bounded design cycles rather than reopening an unbounded terrain research detour.
The first wall-route failure is now resolved by bounded native local A* walking
routes. The original [failing baseline](evidence/actor_navigation/README.md) remains
retained. Wall detours, sealed areas, edit invalidation, unavailable collision,
leave/return and world signal wiring have targeted checks; see
[local route evidence and limits](evidence/actor_local_routes/README.md).

The unchanged brick cottage now has passing native actor traversal through its
entrance stairs and one-metre doorway, plus player walking/running checks at 60 and
120 physics ticks and rejection of tall obstacles/low ceilings. A one-tick support
handover fixes the player/actor capsule-corner stall. See
[cottage and player stair evidence](evidence/actor_cottage_navigation/README.md).
This is an authored-building route, not the full settlement navigation slice.

Sixteen simultaneous clear routes now become usable in 0.267ā€“0.283 seconds,
versus the retained 2.22ā€“2.23 second failure, with the same shared work cap.
Actor-component disk reload preserves destinations and replans after recreation.
See [latency and reload evidence](evidence/actor_planning_latency/README.md).

One real furnished-settlement approach now passes normal save/reload and arrival
inside its cottage. The check exposed a stair-origin-dependent planner failure;
matching clearance to the existing 30 cm movement limit fixes it. Three starting
phases and obstacle/work-budget regressions pass. See
[settlement route evidence](evidence/actor_settlement_navigation/README.md).

This closes the bounded route/reload slice, not the entity coverage row. Crowd
avoidance, regional routes, shared routing data, arbitrary furniture layouts,
multistorey connectivity and combined population performance remain open. Human
actor usability feedback remains separate. Do not expand populations based on
these checks alone.

Water coverage review confirmed cache/occupancy/swimming paths already exist.
Development now has a unified Water page for lifecycle status, retry and water-only
removal. Functional checks pass, but both cold generated-world checks had only two
of four lakes ready at 30 seconds. See [lake editor evidence](evidence/lake_editor/README.md).

Cold-start attribution found 28.1 s queued versus 227 ms of lake worker time.
Adding the existing bounded lake service before each default worker job brings all
four lakes ready at 5.889 s in the declared cold case. Mutation barriers and actual
edit/rebake/removal regressions pass. See
[loading evidence](evidence/lake_startup_scheduling/README.md). Other seeds, maximum
sizes and total frame/thermal behavior remain unqualified.

Actual generated-world cave integration now passes17 checks: disconnected pocket
dry, connected pocket flooded after real excavation, immediate invalidation,
player/camera immersion, vegetation mask and normal save/reload. A fresh process
passes3 more checks with retained6m depth and terrain roof. See
[cave water evidence](evidence/lake_cave_world/README.md). Rendered vegetation,
full underwater traversal and startup hitches remain separate.

Shoreline measurement now confirms a runtime mismatch: in an analytic curved basin,
36 of84 free-space samples beneath visible water report dry at1.1m depth, and14 of62
at2m. These are sample counts, not area percentages. Cold/restored bakes agree.
The failing test and cross-section are retained in
[shoreline evidence](evidence/water_shoreline_queries/README.md).

Native connected partial-cell water queries now resolve that measured mismatch.
Smooth mesh, immersion and root queries use the same tetrahedral connectivity;
version2 caches preserve it and old derived bakes rebuild. Analytic, topology,
codec (debug/release), vegetation and generated cave/save/reopen checks pass.
Cold four-lake gate passes at5.368s. See
[boundary correction evidence](evidence/water_boundary_queries/README.md).
Cost:64-cubed volume retains1.55MiB plus surface/index; measured bake96.102ms,
maximum cold worker slice39.132ms. Finalization is not time-sliced; a66.82ms terrain
receive hitch during restore remains. This closes the measured query mismatch,
not whole-water performance or static-fluid limits.

User requirement now explicitly includes finite manipulable volumetric water and
bucket interaction. Static fixed-height lakes do not satisfy it. Follow
[finite water requirements](FINITE_WATER.md) before returning to the deferred
geology/road coverage. Native finite-quantity transfers and persistence now pass
focused debug/release checks. Bounded geometric quantity measurement also passes49
debug/release checks, including exact capacity, cache restore and budget independence.
These are not integrated gameplay or a spatial solver. Shallow-source admission now
passes:2cm-deep533ml water, no wholly empty cells required, with solid/open-boundary
rejection and exact cache/quantity restoration. See
[shallow-source evidence](evidence/water_shallow_source/README.md). The obsolete
whole-cell flood and its queue were removed. A native supplied-profile settling hierarchy now passes73 debug/release checks:
fill/spill/merge, withdrawal/split, independent unequal-basin oracle and4096-leaf
bounded processing. See [settling evidence](evidence/water_settling/README.md).
This does not close terrain-derived redistribution. The regional3D graph stage now
passes42 debug/release checks plus actual native-terrain excavation integration;
see [topology evidence](evidence/water_topology/README.md). Native basin reduction
now passes58 debug/release checks plus actual terrain integration, compacting
flat connected geometry while preserving outgoing ports. See
[basin evidence](evidence/water_basins/README.md). Terrain storage profiles now feed
finite settling, with44 debug/release checks plus actual native-terrain integration;
see [profile evidence](evidence/water_profiles/README.md). Coarse interpolation is
not adequate; adaptive accuracy and larger-domain support remain open. Same-snapshot regional joins now pass36
debug/release checks with identical whole-area storage and settling; see
[join evidence](evidence/water_join/README.md). Exchange involving unloaded world regions
remains open. Raw density admission and world-addressed ports now pass36 debug/
release checks plus11 actual-terrain sampling/cancellation checks; see
[raw-field evidence](evidence/water_field/README.md). Native region ownership now passes38
debug/release checks, including stale-job rejection, exact boundary samples, vertical
neighbours and endpoint pressure/recovery; see [region evidence](evidence/water_regions/README.md).
NativeWaterNetwork now adds finite equilibrium across independently sampled regions,
with67 debug/release checks and actual two-region excavation. A nested-ridge test
found and fixed incorrect receiving-catchment routing; see [network evidence](evidence/water_network/README.md).
Next implement quantity-preserving edit remapping, unloaded-boundary summaries and
controlled profile accuracy, then worker/rendering integration and bucket/save transactions. Transient flow and pressure/velocity fields are not
implemented, and current playable lakes still use static fill levels. Mining-driven
redistribution, transient presentation, item ownership and saves remain open.
Retain the previous finalization/hitch failures; do not increase water caps or claim
sustained60FPS from these checks.

Current combined gameplay launcher: [Play Combined Gameplay.cmd](../Play%20Combined%20Gameplay.cmd)
uses the separate gameplay copy of the furnished editor world. The existing
[Play Combined World.cmd](../Play%20Combined%20World.cmd) remains the editor-world
checkpoint and shares the Play Actors save. Recent gathering, drops, empty-hand
attacks and controls are documented in [the UI guide](PLAYER_UI.md) and
[gameplay item evidence](evidence/gameplay_items/README.md). Full combined-route
human acceptance remains distinct from acceptance of the recent feature slice.

Actor collision investigation retains its recorded failed budgets. Navigation
work must account for those limits, without treating them as authorization for a
wholesale terrain rewrite. Parked fleet activation is not autonomous traffic.

### Earlier checkpoint and integration disposition

The current checkpoint is [Play Human Checkpoint.cmd](../Play%20Human%20Checkpoint.cmd), with [route and save-slot instructions](HUMAN_PLAYTEST_20261009.md). The launcher fix is commit `4ec4a08`; the older `playtest/human-20261009` tag does not include that fix.

M1 progress: [native saved-checkpoint handover](MODEL_CHECKPOINT_HANDOVER.md) now passes scene-adapter correctness checks, including dirty saves and exact edited-region retirement/readmission. Default automatic model paging remains inactive.

Native focus selection and the structures scene adapter now pass a 24-check
travel/edit/save/reload lifecycle in debug and release, including history pins and
new asset registration. [Contract and limits](MODEL_TRANSFER_SCHEDULER.md). The
fixture explicitly drains transfers; the subsequent normal-world integration
described below now supplies that barrier. The subsequent [discovery check](MODEL_FOCUS_DISCOVERY.md)
found and corrected a linear scan: 4,096 regions across 32 assets now reach the
first nearby request in one selection call instead of 2,048. Debug/release pass
50 focused checks. Full arrival, overlapping layouts and runtime performance
remain separate qualification requirements.

Normal manual saves, autosaves, reload/reset and shutdown now invoke those barriers through an opt-in main-world coordinator. Debug/release each pass 23 actual-worker lifecycle checks; the main scene passes automated 1080p startup/shutdown. [Contract, evidence and remaining decision](MODEL_PAGING_LIFECYCLE.md).

M1 disposition is recorded in [integration results](M1_INTEGRATION_DISPOSITION.md): the modest populated route passes 27 checks, including exact physics identity and distant record eviction; model paging stays opt-in because dense-content qualification remains incomplete. The existing short post-flight mining check still fails the 150 ms visible-change-gap gate (328/281 ms). Preserve this failure while advancing to M2 under the earlier decision to resume planned world work; new ordinary-play blockers take priority. Re-run continuity at M4, on relevant loading/interaction changes, or earlier human-reported regression.

M2 progress: [connected settlement authoring](CONNECTED_SETTLEMENTS.md) now generates and prepares multiple streets through the actual editor, with native layout and retained road connections. Debug/release correctness passes; a 2.002 s graphical outlier is retained. The subsequent [combined world checkpoint](CONNECTED_WORLD_CHECKPOINT.md) passes 14 fresh-process checks for exact buildings, model, roads, lakes and edited terrain, and provides a launcher for human feedback. No whole coverage row closes from this change.

M2 ground-cover work: native bounded candidate generation and renderer packing pass 17 checks in both debug and release, including all 248,982 candidate positions and restoring an individual removal into fresh native state. This is a data primitive only: visible rendering, unified interaction, authored placement, inventory transactions and actual world-save integration remain required before vegetation coverage closes. Natural identities belong to a world seed and generator version; a changed generation profile must not reuse old removals accidentally. Evidence: `docs/evidence/ground_cover_native`.

M2 ground-cover rendering checkpoint: the scene coordinator now uses three native batched collections, at most 49 nearby 32 m cells and one outstanding terrain support request. A 64-check controlled streaming test covers bounded residency, local disturbance, obsolete replies, removal retention on return and teardown. The actual-world graphical fixture passes at fullscreen 1920x1080 with a 60 FPS cap; `docs/evidence/ground_cover_stream/world.png` shows the initial simple meshes. This is test-fixture integration, not default-world activation or performance qualification. Shared surface request IDs now prevent cross-client token reuse. Next: seed/version-safe save ownership, authored placements, native picking and unified editor/gameplay inventory transactions, followed by fresh-process persistence and human checks. Do not close the vegetation coverage row yet.

M2 ground-cover edit storage: `NativeGroundCoverState` now owns seed/version-bound natural removals and distinct, monotonically allocated authored placement IDs. Native cell queries cap authored placements at 256 per cell and 100,000 stored overall. Debug/release each pass 17 storage checks; 66 streaming checks include authored placement eviction/readmission. A real terrain archive manual save is reopened by a separate process and restores exact state and the next ID. Evidence: `docs/evidence/ground_cover_state`. The persistence fixture deliberately disables shutdown writes (the retained save-blocked messages are expected) so shutdown cannot manufacture the tested archive. The initial malformed-input fixture incorrectly treated an exhausted-but-valid next-ID counter as invalid; the corrected case and initial log are retained. Player-facing picking, placement constraints, collection/inventory transactions, default-world lifecycle integration and fresh-process graphical interaction remain open; no vegetation coverage row closes.

M2 ground-cover picking: `NativeGroundCoverPicker` supplies bounded local queries against oriented clump bounds, with no per-instance physics bodies. Debug/release each pass 19 checks, including 15,680 resident records and a local query that tests only 320; 69 streaming checks include interaction identity publication, retirement and return. Queries accept segments up to 8 m and inspect at most four owner cells with padding for supported transforms. These are semantic clump proxies, not triangle-exact selection; terrain/object occlusion and gameplay range must be applied by the interaction coordinator before accepting an action. Evidence: `docs/evidence/ground_cover_picker`. Player commands, inventory transactions and default-world activation remain open.

M2 playable ground-cover interaction: the main world now registers ground-cover edit persistence even when rendering is disabled, preserving edits across launches without the option. `--ground-cover` enables rendering and H selects its tool; 1/2/3 select stone/plant/grass, LMB or E removes/collects, RMB places. Native scene rays bound reach and occlusion; gameplay grants/consumes matching inventory resources, while editor actions are free. Plant and grass inventory/drop catalogs are registered. `Play Ground Cover.cmd` launches a separate `ground_cover_playtest` slot with generator 4, seed 1703, fullscreen 1080p and 60 FPS cap; its dry-run succeeds. Add `--gameplay-construction --slot ground_cover_gameplay` for a separate gameplay slot. Both actual-world input fixtures pass in editor and gameplay modes. The fixtures caught an 8 m floating-point reach rejection; a sub-millimetre tolerance fixes it and the failure is retained. Debug/release picker checks now pass 20; controlled interaction/stream checks pass 79; existing inventory-drop/loadout checks pass 17/13. Evidence: `docs/evidence/ground_cover_interaction`. Visuals are provisional. Remaining gates: combined main-world inventory/edit save/reopen and reload, terrain/building/water disturbance including authored-item support behavior, representative frame-time/GPU impact, toolbelt polish and human feedback. Ground-cover rendering is still opt-in; no whole original-scope coverage row closes.

M2 ground-cover combined lifecycle gate now passes: gameplay collection and replacement in the main generator-4 world are manually saved with non-default plant/grass inventory. A separate process opens with ground-cover rendering disabled, verifies exact edit and inventory snapshots, performs normal F9 reload and saves again (13 checks). A third process reopens with rendering enabled, verifies the same exact snapshots, absence of the removed natural object and rendering of the authored replacement under its original ID, then performs F9 and another save (15 checks). All runs use fullscreen 1920x1080, 100% scale and a 60 FPS cap. Evidence and the exact test slot are in `docs/evidence/ground_cover_world_reopen/manifest.json`. Reproduce creation with `ground_cover_interaction_world.gd -- --persist-ground --ground-cover --gameplay-construction --world-generator=4 --world-seed=1703 --world-slot=<new ground_world_test_ identifier>`; then run `ground_cover_world_reopen.gd` in two separate processes against that slot, first without and then with `--ground-cover`. Do not overwrite the recorded test slot to regenerate evidence. This closes combined ground-edit/inventory save/reopen/reload coverage, not disturbance or runtime-cost qualification. Next: authored support behavior under terrain/building/water changes and a short paired runtime-cost check; visual/toolbelt refinement and human feedback remain open.

M2 authored ground-cover exclusion fix: authored placements previously bypassed structure/water masks. Native species-ordered transform sampling and filtering now apply those masks before render/picker publication while retaining saved records. Exclusion removal restores the same authored IDs. Change detection uses an 8 m footprint margin for supported scaled/sheared placements, rather than missing neighbouring-owner geometry. Debug/release storage checks pass 21; streaming/interaction checks pass 79; existing water/vegetation checks pass. The fullscreen 1080p normal-world fixture with `--ground-cover --disturb-ground` places and removes an actual block over an authored clump, then publishes/removes a controlled native baked water volume. Both remove the affected rendered item, restore its original ID afterwards, preserve the exact durable snapshot and leave a distant resident owner unchanged; building exclusion also verifies picking removal. The water fixture supplies a synthetic basin density field to the real volume/catalog/publication path; it does not prove terrain-generated lake support. Evidence: `docs/evidence/ground_cover_exclusion`. Unsupported/buried authored items after terrain edits remain unresolved; authored placements are not yet dynamic falling entities. Keep that support gate open before qualifying disturbance or enabling rendering by default.

M2 authored ground-cover support now uses one asynchronous density reservation after its natural surface batch, capped at two probes per authored record (512 probes / 256 records per cell). Native evaluation checks root contact within a 0.35 m vertical tolerance, rejects buried/unsupported/nonfinite samples and accepts a supporting structure beneath the root. The scene holds one support request, refuses stale epoch/density/exclusion replies and retries without clearing unrelated owners. Foundation checks now share request-token allocation so they cannot mistake a ground-cover reply for their own. Debug/release native checks pass 25; controlled stream/interaction checks pass 83 including one-request admission and stale-density rejection/retry; prefab foundation regressions pass. The fullscreen 1080p `ground_cover_interaction_world.gd -- --ground-cover --disturb-ground --mine-ground` fixture passes real block exclusion/restoration, controlled native water exclusion/restoration, and actual terrain excavation beneath an authored clump. Mining removes its rendered/pickable proxy while preserving the exact stored authored record and a distant owner. Evidence: `docs/evidence/ground_cover_support`. Policy: unsupported static placements become inactive; their saved identity remains for later support restoration. This is root-contact validation with tolerance, not full mesh contact, falling objects or automatic inventory recovery. Remaining qualification: short paired runtime-cost/arrival test, dense authored support scheduling, support restoration/reopen after mining, visual/toolbelt refinement and human feedback. Rendering remains opt-in.

M2 support restoration/reopen gate now passes in the main generator-4 world. Gameplay collection/placement followed by mining is saved; a fresh process and normal F9 reload keep the unsupported authored item inactive while restoring exact ground edit and inventory snapshots (17 checks). An editor process fills terrain beneath the stored root, reactivating the original authored ID and its picker, with unchanged ground/inventory state (27 checks). Another gameplay process and F9 reload preserve the restored support state (17 checks). All runs use fullscreen 1080p at 100% render scale and a 60 FPS cap. The first restoration attempt correctly rejected filling because the fixture was launched in gameplay mode; that failed fixture log is retained and the successful retry uses the editor. No product relaxation was made. Exact slot, ordered scripts/arguments, hashes and results: `docs/evidence/ground_cover_support_restore/manifest.json`. Use a new `ground_world_test_` slot to reproduce this sequence. This verifies static support reactivation and persistence, not falling-object behavior, thin/complex support geometry in general, dense support throughput or long-run performance. Next: short paired runtime-cost and arrival measurement, followed by visuals/toolbelt refinement and human feedback; rendering remains opt-in.

M2 ground-cover rendering cost check: a stationary fullscreen 1080p ABBA comparison exposed redundant grass/plant shadow passes. The native batch renderer now supports a casting policy for current and newly streamed pages; stones and default model/building batches retain casting, while plants/grass still receive scene shadows. Shadow-policy checks pass 7 in debug and clean release; interaction/streaming regressions pass 83. Enabled total draw calls fell from 806 to 640 against a 487-call disabled workload (ground-cover increment 319 to 153, about 52% fewer). The same 2724 trees and 49 ground owners remain. The final capture has no active/queued terrain work, but disabled_a and enabled_b still fail the unchanged frame-time gates; noisy CPU/GPU timings do not establish thermal or sustained-60-FPS gains. Two preceding failed measurements are retained, including their idle-detection limitations. Evidence, screenshot, hashes and command: `docs/evidence/ground_cover_cost/manifest.json`. First enabled resident-ready time was about 847 ms; this is not a high-speed arrival or first-visible guarantee. Stop repeating unchanged stationary tests: retain opt-in rendering, proceed to visual/toolbelt refinement and human feedback, and revisit mixed-scene performance at M4. Dense authored support scheduling and travel remain open.

M2 ground-cover controls now keep species selection, gameplay inventory count/cost (or free editor placement), removal/collection and placement keys visible above the toolbelt. The context hides during inventory and on tool exit; refresh is event-driven with no per-frame inventory polling. Rendered generator-4 editor and gameplay checks both pass, including real collection/placement, menu visibility and mode exit; 1080p screenshots inspected. Evidence: `docs/evidence/ground_cover_hud`. Ground-cover art, placement preview and human acceptance remain open; this presentation change does not close the recorded frame-time gates.

M2 ground-cover placement feedback uses one amber wireframe box and a contextual rejection reason. Preview and click share the same surface/slope, residency, structure/water exclusion, occupancy and inventory checks; click probes again before mutation. The marker is advisory because native admission limits and asynchronous density support still determine the final result. Preview work is capped at 10 Hz while the ground tool is active; it hides during inventory, driving, inactive input and unavailable editing, with no collision body or shadow casting. Controlled stream checks pass 83; rendered editor/gameplay checks verify preview non-mutation, inventory suppression, occupied-position rejection and collection/placement. Screenshot review changed the initial flat outline to a wire box because sloping terrain obscured one edge. Evidence: `docs/evidence/ground_cover_preview`. Art refinement, human acceptance, dense support/travel and existing frame-time qualification remain open.

M2 interior content now includes baked wooden table, chair and shelf meshes (60/72/84 triangles, one material each) in the normal object catalog with gameplay wood recipes and native compound collision. Runtime model focus now covers every registered collection, replacing a hard-coded beam/doorway list that prevented new assets from rendering or gaining collision near the player. The graphical main-world fixture places furniture through the paid object tool on a real editable block platform; a separate process restores the exact combined structures snapshot and verifies native residency, collision and the open table-leg gap. This is an isolated furnishing fixture, not a furnished settlement or complete world-archive/inventory round trip. Wood texture mipmaps and anisotropic filtering address distance noise found during screenshot review. Evidence: `docs/evidence/furniture`. Next: place interior content in the connected settlement, verify whole-world saving/travel and measure the combined workload; sitting, containers and dynamic furniture are not implemented by these static props.

M2 furnished connected checkpoint now has four tables, four chairs and four shelves inside the existing four cottages, alongside roads, terrain/lakes, forest and enabled ground cover. The source checkpoint and its region/model sidecars were copied to a unique save slot; original human edits were not overwritten. Native editor history admits furniture, and the old floating test beam is removed from this new checkpoint because it blocked the first aisle. All four floor/contact and central player-capsule sweep checks pass; fresh-process whole-world loading preserves exact blocks, furniture, road anchors, water definitions and inventory, then saves normally. Initial self-hit fixture checks and the real beam obstruction failures are retained. `Play Furnished Settlement.cmd` opens the separate local slot on foot inside the first cottage. Evidence: `docs/evidence/furnished_world/manifest.json`. This closes this bounded furnishing/save integration check; entrance traversal, wider navigation, travel, lake-bake readiness and combined frame/resource qualification remain open. No dense-city or sustained-performance claim.

M2 furnished-world short rendering check retains four failed gates: the interior did not reach 60 consecutive idle frames within 12 seconds and still had four queued terrain tasks during its sample; entrance/overview were idle but frame p95 was 18.825/19.185 ms against the unchanged 18.5 ms gate. Their p99 was 19.902/20.207 ms and maximum 20.679/21.186 ms; viewport GPU medians 4.153/4.382 ms, render CPU medians 1.357/1.599 ms, draw calls 529/667. The scene contains 1872 blocks, 12 furniture objects, roughly 2506-2608 trees and about 2100 resident ground-cover instances. Each view captures 180 post-draw intervals at native fullscreen1080p cap60. Original human checkpoint unchanged: a disposable full save/sidecar copy was used. Logs, raw rows and screenshots: `docs/evidence/furnished_cost`. This is not a passing combined qualification, city-scale, travel or thermal test. Preserve the failures; do not repeat unchanged. Next investigate startup work ownership and reusable lake bakes, while keeping frame-pacing attribution separate from GPU timer headroom. The settled views establish a small mixed-content reference only.

M2 startup attribution resolves a misleading aggregate: all four lakes rebake after restore (220932 density samples), but measured processing across 145 slices totals 291.216 ms, maximum 2.705 ms; maximum queue wait is 1891.765 ms. The world becomes playable at 9102.676 ms and the final lake publishes at 28585.195 ms. The first status-only trace could not apportion work because lake slices are serviced inside jobs still labeled mesh; a diagnostic facade signal now exposes already-measured worker/queue times without changing scheduling. Evidence: `docs/evidence/lake_startup`. Therefore do not claim water baking explains the full post-startup workload. Next inspect mesh/cache stages and scheduling; lake bake reuse remains worthwhile for readiness and independent M2 coverage, but is not a proven complete startup fix. Both traces used disposable full checkpoint copies; no runtime performance claim follows from this diagnostic change.

M2 cache accounting failure is fixed: the bounded startup scan previously left the cache permanently read-only after timing out, although the on-disk cache held about 160 MiB below its 512 MiB quota. Baseline: 292 uncached mesh jobs, zero writes, 25115 ms aggregate mesh-worker time. Accounting now retains its cursor and continues in 32-entry/2ms-target worker slices, including idle periods; queued work/input/stop interrupt between slices. Writes remain prohibited until complete accounting. Two intermediate job-only continuation failures are retained. Final cache-fill and fresh-process runs complete accounting; warm run records 292 hits and no write failures/corruption, 367880352 accounted bytes, 5873 ms mesh-worker time, playable startup 4279 ms and final lake 7112 ms. These timings are observations, not a controlled speedup claim (short headless checks overlapped final orchestration); cache-counter outcomes directly verify reuse. Three focused scan/disabled/idle-preemption checks pass. Evidence: `docs/evidence/mesh_startup`. This closes permanent session read-only behavior caused by scan timeout, not quota eviction, cold startup, full storage policy or the existing frame/thermal gates. Keep the human checkpoint and resume broader M2 coverage; no unchanged startup reruns.

M2 continues with a reproducible saved-world content route: generated terrain/geology/lake, a connected road and authored building with interior props, followed by vegetation variety and settlement generation coverage. Each change must identify which original-scope gate it closes and include a short check and a human checkpoint. M3 adds representative entity behavior and bounded vehicle populations. Review stable identity, command authority and persistence boundaries throughout; networking implementation stays later.

This task is bounded by the M1 disposition rule above. It must not indefinitely delay M2 or erase the remaining original coverage rows. No first-round completion, release date or percentage complete is claimed.

M2 entrance coverage: a short on-foot check exposed a one-metre gap below the first stair in all four furnished cottages; every route initially failed. The prefab now includes three lower stairs and three upper-stair supports. A separate copy of the existing furnished save receives the corresponding 24 blocks, preserving both previous checkpoints. All four approach-to-interior routes pass without jumping; a fresh process verifies exact repaired block restoration and repeats all four passes at fullscreen1080p cap60. The furnished launcher selects this repaired copy. Evidence retains failures and screenshots in `docs/evidence/settlement_walk`. No frame-time, arbitrary-terrain navigation, city-scale or full building coverage claim.

M2 current-prefab generation compatibility passes after the entrance change: fixed historical cell counts in four generation/scale fixtures now derive from their source assets. Native scale/async/site/network checks pass, including 128 cottages; these are CPU/correctness checks, not rendered scale proof. Actual editor generation, grading, paving, support validation, vegetation exclusion and save pass for four new 474-cell cottages. A fresh process passes 14 exact terrain/addon/road/lake checks. Creation sample: 88 frames, p95 21.906 ms, maximum 31.230 ms; not a 60 FPS qualification. Two other edited fixtures receive parse-only checks. Evidence: `docs/evidence/cottage_generation`. Existing human launchers and saves unchanged. Current-layout walking and integrated generated furnishings remain distinct from the repaired legacy furnished checkpoint.

M2 furnished-generation prerequisite: NativeBlockPrefab now retains bounded model attachments (stable catalog keys and transforms) through native rotation, frontage and nested settlement composition, saved resources and immutable worker snapshots. Debug and clean-release each pass 27 checks, including 4096 attachments, cell-centred rotations, malformed/count/coordinate rejection without partial mutation, and exact resource reload. Existing async-generation and network-layout regressions pass. Both DLLs use Zig and the pinned prebuilt godot-cpp; no godot-cpp sources rebuilt. Evidence: `docs/evidence/prefab_attachments`. This does not enable automatic furnishings yet: world block placement/capture still handles blocks only, and model bounds are not in site envelopes. Next implement joint block/model admission, protection, inventory and rollback before enabling attached assets in the player catalog; then verify generated furnished interiors, save/reload and travel. No coverage row closes on authoring data alone.

M2 furnished generation is now a main-world editor path: select Furnished cottage as a prefab or settlement source. Native combined admission checks blocks/models, registered identities, capacity/residency, protection, block overlap and interior containment; new-model overlap uses a bounded spatial grid. Gameplay charges blocks plus 17 furniture wood per cottage; editor placement is free. Rejections preserve stores and refund inventory contents. Block-only placement refuses attached assets. Debug and clean-release each pass 23 focused checks; construction inventory passes 22. Actual editor generation creates four furnished cottages (1896 blocks, 12 objects), grades/paves/validates/places and saves; fresh-process exact terrain/addon and count checks pass. A separate Play Generated Furnished Settlement.cmd opens this on-foot checkpoint. Creation p95 20.754 ms, maximum 52.725 ms and relocation screenshot HUD 22 FPS remain recorded limitations, not performance qualification. Initial fixture revision-expectation and clean-project missing-import failures are retained. Combined placement is a history barrier, not grouped undo; unsupported frames, exterior props and conservative validation budgets remain limits. Evidence: docs/evidence/generated_furnished. Next: current generated-layout walking/travel and placement cost at representative furnished populations; wider M2 water/geology/world coverage remains active.

M2 furnished-placement scale check immediately exposes synchronous admission limits: one native call at 4/16/64/128 cottages takes 0.715/2.673/10.421/26.813 ms against a declared 4 ms placement budget. The validator unnecessarily rebuilt a per-block search tree. It now probes the prefab's already-sorted cells through the inverse lattice transform, removing 60672 temporary tree nodes at 128 cottages. Same single-sample check after the change: 0.445/1.254/7.217/9.895 ms. Exact populations and all rotations remain correct; debug/release transaction suites pass 26 checks. Both large cases STILL FAIL the unchanged budget. Model probes/comparisons grow linearly (40/30 per cottage); this identifies synchronous validation/commit work, not a demonstrated meshing bottleneck. Single observations are not sustained-performance or statistical speedup claims. Evidence: docs/evidence/furnished_placement_scale. Before claiming large interactive settlement authoring, split costly preparation from publication, revalidate revisions and retain transactional block/model/inventory semantics; identify and bound the publication work. Stop unchanged reruns. M2 and broader frame/thermal gates remain open.

M2 large-placement attribution: native admission now reports five disjoint timing stages. At 128 furnished cottages, a single diagnostic call spends 4009 us on block validation, 6005 us on model validation, 5482 us on block commit, 119 us on model commit and 303 us on publication; total external call 15987 us. The 64-cottage call is 4844 us. Both still fail the 4 ms budget. These observations vary from earlier runs; no statistical comparison or improvement claim follows. Moving only validation off-frame would still leave an over-budget block commit. The needed structural change is bounded preparation of touched block chunks/model records, revision/ownership revalidation, and atomic publication of prepared state, preserving material/refund and callback guarantees. Debug/release correctness passes 26 each. Stage sums match external intervals; updated scale script parses without an unchanged rerun. Evidence: docs/evidence/placement_stages. This is diagnostic progress, not a fix or closure of large interactive placement; stop attribution-only reruns and implement the identified preparation/publication boundary when continuing this gate.


M2 furnished settlement placement now prepares touched block chunks and attached model records incrementally in native code, then publishes the prepared state without another per-cell validation/copy pass. The actual furnished-frontage editor path advances at most 2048 cells or 16 models per frame, targeting 1 ms; source/world/model revisions and actor protection are rechecked, and gameplay inventory is debited only at commit. Debug and clean-release staged suites each pass 25 checks (including deleted owners, last-cell deletion, source edits, cancellation and preservation of existing chunk cells). Debug transaction/inventory suites pass 26/22. Latest single headless 128-cottage sample: debug maximum step 193 us, commit 495 us; release maximum step 198 us, commit 470 us. All 4/16/64/128 call-level cases pass the 4 ms gate. This closes the measured synchronous large-furnished-placement call failure for this bounded fixture, not general city performance. Actual editor cancellation during native preparation, retry, exact 1896-block/12-object placement, save and fresh-process restoration pass. An initial self-notification status failure is preserved and fixed by detaching the active request during publication. Graphical creation still records p95 20.597 ms and maximum 38.498 ms; the mixed frame gate remains open. Evidence: docs/evidence/staged_placement. Limitations: time budgets are cooperative (one model is indivisible); dense existing collections and maximum publication populations remain unqualified; global revisions conservatively cancel unrelated edits; combined undo remains unavailable. Block-only frontage and direct small-prefab placement retain synchronous compatibility paths. Existing human checkpoints/launchers remain unchanged. Continue current-layout walking/travel and broader M2 water/geology coverage rather than repeating this passing fixture.


M2 current generated-layout walking now passes all four cottage approach-to-interior routes without jumping, in a fresh process using the disposable staged-placement checkpoint. Exact saved blocks match before walking; screenshots show the generated interior furniture. The existing route fixture now supports the current 14.5 m frontage offset and keeps legacy repaired-layout evidence separate. Evidence: docs/evidence/generated_settlement_walk. This closes the current-layout entrance check only: routes start near each entrance, so cross-region departure/return, vehicle road traversal and mixed performance remain open. Human checkpoints and launchers unchanged. Next complete a short combined departure/return correctness route, then resume versioned lake bake reuse and geology coverage under M2; do not rerun unchanged entrance tests.


M2 generated settlement departure/return passes 19 graphical checks at fullscreen1080p cap60. An 800 m focus relocation evicts two block regions, all 12 building meshes and the 12 furniture render/collision instances. Return readmits block regions without read errors, restores furniture residency and building collision, and preserves exact block/model/road/lake snapshots and the existing ground-cover edit state. Normal save succeeds. Evidence: docs/evidence/generated_settlement_return. This short relocation check closes the bounded saved-settlement eviction/readmission integration question; it is not continuous walking/driving, terrain arrival latency, nonempty vegetation-edit coverage, large populations or frame-time qualification. Per-phase waits include ten mandatory process ticks and must not be described as minimum load latency. Previous human checkpoints remain unchanged. Next M2 implementation: versioned lake bake reuse, retaining static-water limits and invalidation correctness; continuous road travel and geology coverage remain open.


M2 lake bake reuse prerequisite: NativeLakeVolume has a bounded versioned codec for occupancy and smooth shoreline geometry, with a caller-supplied 256-bit content identity, corruption checksum and validated native reconstruction. Debug/release each pass 29 checks covering exact queries/geometry, immutable publication, stale identity, corruption, truncation and malformed mesh data; existing water regression passes 45 checks. Evidence: docs/evidence/water_bake_codec, including the initial missing script binding failure. No runtime reuse or startup improvement is claimed: worker-side terrain/lake identity derivation, cache read/write policy and scene publication remain unconnected. Next implement those together and prove cold bake, fresh-process hit, local edit invalidation and corrupt-cache fallback in the main world. This prerequisite closes no water first-round coverage row.


M2 lake bake reuse is connected on the terrain worker for supported Windows binaries. Native local content keys, full lake definitions and terrain/water binary fingerprints select versioned occupancy/shoreline payloads. Reads validate identity and checksums; misses/corruption bake normally. Writes share the existing 512 MiB derived quota and atomic rename, with a 16-entry/16-MiB deferred queue while accounting completes. Initial first-lake write-skipping failure is retained; bounded deferred storage fixes that startup ordering issue. Actual saved-world cold run samples 220932 nodes and stores four bakes; fresh-process warm run has four hits and zero sampled nodes; one corrupted entry produces three hits plus one 55233-node rebake. All three runs preserve exact baked occupancy/shoreline hashes. Native local-edit invalidation, remote-edit reuse and binary fingerprint checks pass; water suite now passes 50 debug/release checks, codec 29 each, storage six, cache scan/idle regressions pass. Graphical water integration passes swimming, immediate invalidation, rebake and removal lifecycle at fullscreen1080p cap60. Evidence: docs/evidence/lake_cache_runtime. This closes bounded persisted bake reuse, not water first-round coverage, dynamic fluids, startup/frame/thermal qualification or runtime eviction. Identity hashing and up-to-6-MiB file/codec operations are worker-owned but indivisible; maximum-lake latency remains unqualified. Unsupported/missing binary fingerprints fall back to baking. Next return to M2 geology discovery/material rewards and continuous road traversal coverage; retain existing performance failures.


M2 geology gameplay integration now has a two-process actual-world check for both seeded ores in generator 4, seed 1703. The fixture locates solid buried veins in an independent native probe, mines them through the real gameplay terrain worker, and verifies exact reward mapping: 33 iron samples, then 21 copper plus 12 stone. Both ore types can be claimed and crafted into metal. Pending rewards and inventory restore exactly in a fresh process; repeating both saved excavations grants no duplicate rewards. Evidence: docs/evidence/geology_gameplay. This closes the bounded two-material worker/reward/crafting/persistence connection; direct fixture relocation does not prove natural discovery, a traversable underground access route, ore visual readability, mining continuity or frame performance. Existing human saves unchanged; a separate test slot was created. Next provide an accessible underground geology checkpoint and verify actual ore-face visuals before marking that original-scope coverage row complete.


M2 underground checkpoint now exposes shallow seeded iron/copper via two authored sloping access tunnels. Both on-foot entrance-to-face routes pass without jumping in creation and fresh-process reopen. Added optional F-key headlamp as one off-by-default 14 m shadowed engine spotlight, with modal/focus guards and no script processing; fixed a controls/toolbelt overlap discovered in screenshot review. Ore tint now retains variation from the existing filtered rock sample without extra texture fetches. Initial short-approach and flat-ore screenshots are retained. Play Geology Checkpoint.cmd selects a separate local saved slot in gameplay mode; existing checkpoints remain unchanged. Guide: docs/GEOLOGY_CHECKPOINT.md; evidence: docs/evidence/geology_access. Natural cave discovery, route between entrances, headlamp GPU cost, ore-face mesh faceting, mining continuity and sustained performance remain open. This is a usable human checkpoint, not completion of the full terrain/geology row. Next M2 coverage resumes continuous driving on authored roads before broader entity work.


M2 actual-road driving check passes: vehicle placement now follows player heading, with the obstruction box rotated identically. The first implementation used the wrong forward axis and drove backward along the test route; retained failure evidence led to the explicit player -Z / vehicle +Z conversion. Final short furnished-settlement drive travels 15.09 m, reaches 49.50 km/h, has zero lateral drift and zero collision-readiness holds, with supported chassis and attached driver/camera. Vehicle admission/entry/exit/persistence regression passes including rotated spawn. Evidence: docs/evidence/settlement_driving. The input save is deliberately preserved by disabling fixture teardown writes; its logged save-blocked message is expected. This closes short loaded-road integration, not continuous streamed-region crossings, turns, braking/exit on this route, high-speed arrival or performance. Those remain separate original-scope coverage gates; no road or vehicle row is certified complete.


M2 loaded-road braking/exit coverage passes in the saved furnished settlement: accelerate to 33.19 km/h, brake over 3.00 m within 81 vehicle physics ticks, then exit onto clear ground and walk on the road. Total forward travel 9.03 m, zero lateral drift and zero collision-readiness holds. Actual walking is verified after toolbelt/collision restoration. Evidence: docs/evidence/settlement_braking; source save preserved through explicit teardown write inhibition. This closes the bounded stop/exit/walk connection, not turns, continuous region crossings, high-speed arrival, fleet density or frame/thermal qualification. Next road coverage must cross a streamed boundary or exercise a turn; do not repeat the now-passing straight loaded-road loop.


M2 loaded-road junction coverage passes seven checks: keyboard steering reaches all five right-turn waypoints at up to 15.23 km/h, with zero collision-readiness holds. Maximum chassis-center deviation from the nearest road centerline is 2.91 m; final height and heading agree with the connecting street. Screenshot reviewed. Evidence: docs/evidence/settlement_junction. This checks a short already-loaded route, not continuous wheel contact, swept body containment, streamed-region arrival or sustained performance. Source save preserved through explicit teardown write inhibition. Loaded straight driving, braking, exit/walking and turning now have evidence; stop repeating these routes. Next road gate is continuous travel across initially nonresident regions with readiness/hold telemetry, followed by broader gameplay/entity coverage.


M2 short streamed driving probe exposes a continuity failure: isolated generator-2 terrain and vehicle traverse about 245 m on five connected graded sections into initially unready collision coverage. The car reaches 131.04 km/h and the destination, but the guard holds it for 44 consecutive physics ticks (0.367 simulation seconds). Evidence: docs/evidence/vehicle_streamed_crossing. No falling observed; frozen wheel counters are not independent contact evidence. This is deliberately failing the zero-hold gate, excludes forest/buildings/main-world lifecycle, and does not qualify performance. Next bounded investigation: hold-transition bounds and planner/publication state near z=512. Do not repeat unchanged or weaken the continuity gate.


M2 driving hold traced to activation: unchanged instrumented runs produce one pass and one 53-tick hold (about 434 ms wall time). At the z=512 boundary, both required 16 m tiles and their ancestors are present and clean, but fine tiles remain hidden beneath a visible 256 m parent. Evidence: docs/evidence/vehicle_streamed_crossing/trace_hold.json; passing trace also retained. The next implementation targets ahead-of-travel activation dependencies, preserving complete coverage replacement and current-position priority; add a synthetic planner regression before the short driving rerun. No production fix or continuity closure yet.


M2 native travel planner now prioritizes ahead-of-travel activation dependencies after current-position dependencies, preserving complete replacement and the existing request set. Debug/release planner checks pass 182. Three short rendered crossing runs all clear the former z=512 hold; two pass zero-hold overall, while the third fails with five held ticks at the starting position before acceleration. Evidence: docs/evidence/vehicle_travel_activation. Do not close continuity: next inspect current-position coverage regression during startup refinement; no main-world mixed travel or performance qualification is established. Original intermittent 44/53-tick failures remain preserved.


M2 startup collision regression fixed: during requested refinement, a late hidden coarse parent no longer replaces already published descendants when child coverage remains incomplete. A deterministic late-parent test fails on the previous binary; debug/release now pass 184 checks including shuffled arrivals preserving fine coverage without overlapping surfaces. Three separate rendered 245 m crossings into initially unready terrain pass the unchanged zero-hold gate at up to 131.04 km/h. Evidence: docs/evidence/terrain_late_parent. This closes the reproduced isolated startup/boundary stalls, not mixed-world or sustained travel. Tradeoff: incomplete regions can retain partial coverage while surrounding pieces finish instead of exposing a new coarse fallback. Next: combined main-world travel with vegetation/building readiness; do not repeat the passing isolated route without new cause.


M2 main-world streamed drive passes seven bounded checks with forest, ground cover, buildings and lakes active: 245.017 m into initially unready combined coverage, zero holds, wheel support on all 1244 ticks, peak 131.038 km/h. Evidence: docs/evidence/settlement_streamed. Visual review reveals fixed-height road extension becomes a dark tunnel under rising terrain; this is not a readable open-surface vegetation route. Source checkpoint preserved by write inhibition before temporary road edits. Next use terrain-following road elevations for a visible surface route before closing mixed-world travel coverage; frame/thermal, city/fleet scale and human acceptance remain open.


M2 surface-route driving exposes a separate support failure: sampled terrain requires bounded cut/fill to meet the unchanged 25% grade limit. A level entrance allows existing vehicle placement; steep entrance rejection retained. Main-world drive reaches 245.136 m with zero loading holds and peak 92.427 km/h, but >=3 wheel contact is observed in only 883/1574 ticks (56.1%), failing the unchanged 95% gate. Screenshot shows sky over an open cutting and a visibly stepped road. Evidence: docs/evidence/settlement_surface. Next sample actual graded collision heights/normals and correlate wheel losses before choosing road-mesh or suspension correction. Sloped spawn and road visuals remain open; this is not surface-route acceptance or performance qualification. Source save preserved.


M2 graded-road join defect fixed: rounded footprint caps previously clamped top elevation, creating nearly 1 m ledges between collinear graded sections. Grade now extends through caps; native edit and scene invalidation bounds include cap rise. Direct collision regression improves maximum height error from 0.963 m to 0.0000594 m with zero measured normal/step error; debug/release pass and walking traversal remains passing. Final mixed-world uphill drive has zero holds, reaches 245.2 m and 128.51 km/h, but wheel support is 1152/1328 ticks (86.7%), below unchanged 95% gate (previously 56.1%). Evidence: docs/evidence/road_grade_caps. Existing saved terrain is not migrated; regrading is required for old ledges. Next correlate residual losses with grade transitions and suspension; sharp turns, polished cut-wall visuals and overall route acceptance remain open.


M2 residual wheel-loss trace localizes every <3-load observation to the first six 16 m road sections. The later constant 25% climb retains >=3 loaded wheels throughout. At the sharp crest near x=746.75 the chassis is 2.026 m above the intended road at 73.275 km/h, with zero wheel ray hits; no streaming holds occur. Evidence: docs/evidence/road_grade_transitions. This supports abrupt vertical-profile launch, not another loading failure. Next implement bounded native road-profile smoothing with grade/curvature and cut/fill constraints, rejecting infeasible routes, and integrate authoring preview/construction. Preserve the 95% support gate; do not compensate by forcing vehicle adhesion. Initial two-wheel load redistribution is separately observable and is not itself proof of airborne travel.


M2 native road-profile primitive now fits bounded C1 cubic vertical profiles to 3..65 uniform straight XZ samples, with grade/curvature and cut/fill constraints, flat entrance tangent and 2048-iteration cap. Continuous analytic extrema validation rejects uncertified output; an initial between-sample grade overshoot is retained and resolved through tighter internal solver margin. Eight debug/release checks pass including the actual uphill terrain and independent dense validation. Evidence: docs/evidence/road_profile. Single-fit times around 4.9/3.8 ms are not a worst-case bound. This is not yet terrain/editor integration or driving closure. Next consume the cubic field in native construction and preview through background authoring; preserve epoch/revision and save ownership, then rerun collision and the unchanged 95% support gate. Budget failure does not prove infeasibility.


M2 smooth road construction now evaluates shared cubic profiles natively across section overlaps, retaining straight command compatibility and validating finite coefficients, counts, C1 joins, endpoint agreement and analytic grade/height bounds before mutation. Debug/release direct curved collision passes (<0.824 mm height error); malformed packets leave geometry unchanged. Straight-road and walking regressions pass. Actual mixed-world 245.051 m drive passes unchanged support and readiness gates: >=3 loaded wheels on all 1261 ticks, zero holds, peak 131.74 km/h, initially unready destination, unchanged suspension. Evidence: docs/evidence/curved_road. This closes the reproduced uphill support failure for the short route, not broad vehicle/road qualification. Editor preview/UI and curved-road save/reopen remain open; current route submission is sequential section edits, not atomic whole-route authoring. Next integrate authoring lifecycle and persistence; deep cut-wall visuals remain provisional.


M2 curved-road terrain persistence passes in two separate headless processes: four curved sections publish through the real worker, manual save verifies, fresh process reloads normally and saves again. After worker shutdown, all 24 collision mesh packet hashes and asphalt/air density probes match exactly. Evidence: docs/evidence/curved_road_persistence. Disposable unique slot retained; shutdown writes disabled only after manual save verification, so expected save-blocked teardown cannot manufacture the archive. This verifies terrain results, not persistence of editable curve control data. Next integrate editor preview, background fit, stale-source guards and multi-section authoring lifecycle; parametric controls/resumption remain open.

M2 smooth-road editor integration: the road palette now samples terrain, runs the existing native profile fitter on a background thread, previews the route visibly through terrain/vegetation and constructs curved sections through the guarded terrain API. Actual-world checks pass 11; existing continuation/editor regressions pass 16/28. Preview is non-mutating, selection/terrain changes invalidate it, and player overlap rejects before mutation. Evidence: `docs/evidence/smooth_road_editor`. Mark start/end, choose asphalt and clearance >=1 m, use Preview smooth terrain road then Build smooth road; supported length is 8-128 m. Completed entrances are available through street-end controls. This is sequential construction with no terrain undo; interrupted sections remain and editable fit controls are not saved. Immediate built screenshot reports 14 FPS while terrain updates and is not a settled visual/performance pass. Mid-operation reload/cancellation, settled vegetation readiness and construction frame-cost attribution remain open. Next: short targeted lifecycle and construction-cost checks before claiming this authoring workflow qualified; retain M3 entity/vehicle population work in the grand plan.

M2 smooth-road cancellation lifecycle: a targeted coordinator test using real native fitting and deterministic terrain stubs reproduced retained finished worker/solver after cancellation. Idle processing now joins only once the canceled worker has finished and releases both objects without publishing results. All 10 checks pass, including old-token rejection, sampling epoch rejection, pending-section reload cancellation, no next-section submission from late completion, restarting preview and teardown joining the native fit. Before/after evidence: `docs/evidence/road_authoring_lifecycle`. These are controlled lifecycle checks, not full-world F9 or frame-time qualification. Construction cost and settled vegetation readiness remain the next short measurement.

M2 road construction measurement retains four failed gates: baseline never reached 60 idle frames within 15 seconds (4 queued mesh tasks during capture), and baseline/build/after frame p95 were 18.880/19.666/18.974 ms against 18.5 ms. Seven-section construction took 324.683 ms over 20 frames, max20.687 ms; no 14 FPS interval reproduced. Recovery took 4130.375 ms including 60 idle confirmation frames; all120 after frames were settled, queue0, max19.622 ms. After GPU median4.348 ms, render CPU1.251 ms. Evidence/raw rows/settled1080p screenshot: `docs/evidence/road_construction_cost`. The busy baseline prevents isolating incremental construction cost; aggregate trees2372 to2366 does not prove instance-level disturbance correctness. Source save protected. Next diagnostic should attribute remaining baseline mesh work and frame pacing, not repeat unchanged measurements or replace meshing based on a HUD reading. Broader M3 entity/vehicle coverage remains pending.

M2 road baseline queue attribution: optional --trace-loading records existing worker queue diagnostics at 250 ms intervals during warmup and measured phases. The bounded run samples 63 distinct kind/tile jobs with no repeated start for the same kind/tile; warmup/baseline advance through distant 256 m tiles, then relighting and idle. This supports unfinished world coverage generation rather than an observed stuck/repeated mesh job. Sparse sampling cannot exclude short repeats or establish worst-case publication cost. Four unchanged gates still fail; after p95=18.792 ms. Evidence: `docs/evidence/road_loading_trace`. Do not infer a meshing redesign from this busy baseline or describe the frame gate as passed. A clean incremental-cost comparison requires known loaded coverage; frame-pacing root cause remains unproven.

Entity gameplay prerequisite: NativeEntityStore.set_position now applies finite collision/authority position corrections while preserving velocity, handles and persistent identity and updating spatial membership. Debug and clean release pass 10 correction checks and 13 existing sleeping checks. Evidence: `docs/evidence/entity_position`. Release fixture initially omitted explicit extension preload and timed out; fixed fixture preloads extension and emits required JSON. Native SDK reused without rebuild. This does not implement collision simulation, character behavior, animation or population activation; those remain open before M3 coverage. Next integration must use this correction API with actual bounded collision/behavior work, not claim entity counts as gameplay proof. M2 recorded performance gaps remain open.

Entity collision integration prerequisite: NativeEntityActor now binds a world-coordinate store record to one near-field CharacterBody3D capsule, seeks a target with native gravity/velocity policy, uses Godot move_and_slide and returns corrected positions to the store. Eight debug/release checks exercise real floor/wall collision, unready-coverage freeze, invalid input, external correction and stale-handle rejection, alongside 100000 stationary records. Evidence: `docs/evidence/entity_actor`. This is headless correctness, not rendered crowd or main-world qualification. Activation pool, streamed-world readiness, persistence owner, animation and actual behavior remain next integration work. No navigation/stair or entity population performance claim. Existing player stair routine is unchanged; only the engine collision solver is shared.

Entity saved-world integration fixture passes 15 checks: four native character proxies walk about7.5 m along an existing settlement street over180 physics ticks, with zero readiness holds, using terrain/building/forest collision coverage. Native batched rendering selects four nearby actors from100004 records; corrected records round-trip exactly in memory. Fullscreen1080p screenshot inspected; source saved slot protected. Evidence: `docs/evidence/entity_actor_world`. This fixture is not a persistent playable entity addon yet: activation ownership, actor world-save component, animation, navigation/avoidance and measured populations remain open. Capsule art is temporary and actor masks intentionally exclude each other. Next implementation: bounded reusable activation ownership and lifecycle/persistence in the main world, retaining native simulation paths.

Entity bounded activation: NativeEntityActivation owns an immutable1-64 collision-proxy pool, selects nearest store records with existing bounded native query, retires unused bodies by disabling collision, reuses bodies on travel/restore and batches native ticks with all-input validation. Thirteen checks pass in debug/release against100006 stored records and3 bodies. Evidence: `docs/evidence/entity_activation`. Capacity truncation is explicit; exhausted candidate scans suspend all activation instead of presenting a partial nearest result. No hysteresis, distant catch-up, actor mutual collision or crowd performance qualification is claimed. Pool children are internal resources, coordinates are world-space, and target/readiness arrays follow active_handles. Next: connect pool to saved-world actor ownership and readiness, then add representative behavior/animation.

Entity world ownership: actor_world scene adapter is now registered by the main world as world_actors in the compound archive, independently of activation. Default capacity1024; explicit enable creates a bounded native pool and batched renderer. Snapshot restore validates before retiring proxies/instances, then restores native identities; no actor nodes are allocated while disabled. Main-world create/manual-save/reload passes9 checks; fresh-process disabled reopen and active-pool reload pass8 with exact bytes and old-handle rejection. Evidence: `docs/evidence/actor_world_persistence`. New disposable slot only. Automatic simulation, authoring controls, persisted behavior targets, animation and capacity scaling remain open; this closes record ownership/reload integration only.

Entity automatic lifecycle: --actors enables the saved-world adapter with16 preallocated proxies,48m nearest activation at5Hz, native per-physics-tick idle grounding with swept terrain/building/forest readiness, and64m batched rendering at10Hz. Nine actual-world checks pass: terrain grounding, rendering,800m relocation retirement, frozen distant record, return identity and fixed body allocation, plus world-unavailable suspension. Native readiness/activation checks pass15 in debug/release. Evidence: `docs/evidence/actor_world_activation`. Automatic behavior is idle grounding only; steering, persisted orders, navigation, animation, interpolation and population cost remain open. Existing saves are preserved when the option is absent. Next: player/editor actor placement and persisted behavior commands rather than more isolated count tests.

Entity editor interaction: with --actors, J places a capsule actor on aimed static supported ground within12m and Shift+J removes the directly aimed active actor; HUD lists controls. Free editor only, with focus/loading/edit/driving/inventory guards, native scene ray/shape queries, actor occupancy, slope, dry-ground and combined collision-readiness checks. Seven actual-world input checks pass;1080p screenshot inspected. Initial actor-on-actor stacking bug fixed by rejecting dynamic support; fixture recapture-aim failures retained. Evidence: `docs/evidence/actor_editor`. Actor edits use the existing verified world_actors save component; this test protects source save and does not claim another persistence round-trip. No undo, inactive actor selection, navigation or animation yet. Next: persisted behavior orders and bounded native execution, retaining original entity population qualification.

Entity persistent movement orders: native identity-keyed target store now serializes a versioned bounded canonical payload; worker validator inspects bytes only, restore rejects orphan identities after world_actors restoration. Activation executes targets natively with speed-aware readiness envelopes; clear stops horizontal travel, editor removal clears order. Native debug/release pass10 checks each; real world create/save/reload11 and fresh-process reopen/reload10 pass. Evidence: `docs/evidence/actor_orders`. This is direct target seeking with collision stopping, not navigation or avoidance. Target remains until changed/cleared; editor order controls are next. No animation or population performance gate closes.

Entity movement editor controls: K selects a directly aimed active actor by persistent identity, then K on loaded dry static ground assigns a destination; Shift+K clears/stops. Same free-editor/focus/loading guards as placement; outdated epoch selections discarded. Fourteen actual-world input/movement checks pass, including >2m native travel and stopped horizontal position;1080p screenshot inspected. Evidence: `docs/evidence/actor_editor_orders`. Play Actors.cmd opens the existing generated furnished checkpoint with --actors, fullscreen1920x1080 cap60; dry-run verified, no automatic human launch. Direct movement may stop at obstacles; selection highlighting, smooth rendering/animation and representative crowd costs remain open.

Entity render cadence: native renderer now caches selected generation-checked handles and updates their positions without spatial reselection. Actor adapter publishes positions each physics tick while retaining10Hz selection; unchanged positions issue no transform upload, stale handles hide cached instances until reselection. Graphical debug/release each pass24 checks; saved-world editor/movement passes15 including visual/store equality on60 movement ticks. Evidence: `docs/evidence/actor_render_motion`. Initial headless transform readback failures retained and corrected to graphical1080p tests. This removes deliberate10Hz motion stepping, not a proof of interpolation, animation or crowd frame budget. Changed actor buffer remains12288 bytes per tick at256 capacity.

Entity first mixed-population cost check exposes failures before animation: settled terrain queue0/idle throughout120-frame phases. Empty/16moving/64nearby frame p95=18.581/19.074/19.120 ms, all above18.5 gate. Actor update16moving p95=2.460/max10.835 ms;64nearby p95=2.784/max3.719 ms, fail1ms p95/2ms max gates. Fixed16-body cap and zero collision-readiness holds pass.64nearby produces106 activation entries and38 distinct simulated identities in2 seconds, exposing nearest-set churn and unsimulated population. Evidence/raw rows/1080p screenshot: `docs/evidence/actor_population_cost`. No crowd scalability claim. Next bounded fixes: retention/hysteresis for active set, native readiness-versus-collision attribution; avoid adding animation cost until these results receive a disposition. Existing global frame pacing failures remain separate.

Entity activation retention: active identities receive a2m distance advantage during bounded native selection, still retiring outside the hard radius.18 debug/release checks pass, including small-distance retention, sufficiently nearer replacement and radius eviction. Same64-nearby workload falls from106 activation entries to34, all34 distinct; no repeated admission observed in2 seconds, but30 actors remained unsimulated and fairness is not proven. Opt-in profiling attributes moving16 p95 collision1.691ms versus readiness0.490ms, total2.277ms; collision max10.167ms. Nearby64 total p95=2.877ms. All five timing failures remain. Evidence: `docs/evidence/actor_retention`. Next bounded investigation targets collision movement (including redundant transforms and store publication); do not relax simulation/readiness or declare scalability from churn improvement.

Entity collision substage attribution: skip redundant global-position assignment while preserving external corrections (8 debug/release collision checks pass). Same mixed workload still fails populated frame/actor gates: moving16 actor p95=2.388ms max9.891ms; engine set_velocity/move_and_slide p95=1.619ms max9.311ms. Nearby64 actor p95=2.885ms, engine2.163ms. Transform correction and store publication p95=.009ms each. Empty frame p95=18.269ms passes this run, not a global qualification. Evidence: `docs/evidence/actor_motion_cost`. No robust speedup claim. Two wrapper/activation cycles have not closed timing gates: stop extending wrapper tweaks; next bounded comparison must isolate simple versus terrain collision geometry to guide representation/design. Preserve readiness, fixed timestep and full actor workload.

Entity contact comparison: identical restored16 movers run terrain_a / simple box / terrain_b for120 ticks each. Engine motion p95=1.686/.682/2.125ms; total actor p95=2.310/1.335/2.738ms. All three total actor and frame gates still fail (6 failures); movement, height, cap and readiness checks pass. All360 rows have idle terrain and no readiness holds. Evidence: `docs/evidence/actor_collision_comparison`, including raw rows and inspected1080p screenshot. Different contact masks exclude other world shapes during the box phase, so this does not isolate terrain triangle count or justify replacing volumetric collision. Simpler contact helps this fixture but is insufficient for the unchanged1ms actor budget. Stop wrapper tuning and unchanged timing reruns. Next collision design work must first inspect resident/overlapping shapes and concave partitioning along this route; preserve caves, local edits, slopes and obstruction correctness. Entity scalability, animation, fairness and mixed-frame qualification remain open.

Entity collision layout census: settled saved route intersects four active terrain concave pieces (614/626/640/684 triangles), among105 active and15 inactive terrain bodies. No exact ordered world-space triangle duplicates in those candidates;2 fixture checks pass. Evidence: `docs/evidence/actor_collision_layout`. This read-only scene-node census excludes other systems/server-only shapes; bounds are conservative and duplicate detection does not establish absence of geometric overlap. Current route does not support excessive terrain piece count as the primary cause, so wholesale repartitioning is not justified. Preserve existing timing failures; any further collision comparison should hold triangle geometry constant to distinguish representation/contact behavior before production changes.

Entity selection feedback: K selection now shows one shared unshadowed cyan marker above the actor, followed in native renderer publication without per-entity nodes or a script tracking loop. Marker hides on render retirement, stale identities, suspension, removal and epoch-invalid commands; deleted marker references fail safely. Debug/release renderer suites each pass30 checks and actual saved-world editor passes17;1080p screenshot inspected. Evidence: `docs/evidence/actor_selection`. This closes selection visibility only. Geometry can occlude the marker; actor navigation, animation, fairness and all previous populated timing failures remain open.

Vehicle/entity scheduling prerequisite: entering a car globally selects120Hz physics, doubling actor movement calls. A tested60Hz actor accumulator was rejected because CharacterBody move_and_slide still uses engine delta: travel slowed and parity failed. Production retains engine-aligned updates. Nine saved-world checks now verify matching one-second travel within1cm at60/120Hz, expected call counts and immediate unavailable suspension. Evidence: `docs/evidence/actor_cadence`, including rejected-change results. This prevents an incorrect decimation optimization; it is not a performance fix. Multiple-vehicle ownership/storage/activation remains unimplemented. Future independent actor cadence requires deliberate solver integration preserving elapsed motion and collision correctness; account for shared120Hz cost before fleet qualification.

Vehicle fleet storage prerequisite: native v2 codec stores sorted persistent IDs, parked poses and a nonreuse counter, bounded to65536 records /4194328 bytes. Legacy absent/single-car data migrates; malformed IDs, counters, pose types, quaternions and lengths reject before decoded publication.18 debug/release checks and10 legacy regressions pass. Evidence: `docs/evidence/vehicle_fleet_storage`. Existing single-car validator remains separate, preventing accidental fleet truncation; main-world ownership is not yet migrated. Max encode took72.918ms debug /67.899ms release and must not run as unbudgeted frame work. Next implement native record ownership/spatial activation and safe world integration; codec alone closes no fleet coverage gate. Damage/velocity/type state and large-world coordinate limits remain explicit gaps.

Vehicle fleet native ownership: NativeVehicleFleet now holds monotonic persistent IDs and parked poses separately from scene bodies, indexed in32m cells. Bounded nearest queries expose result truncation; candidate-budget exhaustion returns no misleading nearest subset. Spatial pose correction, deletion, legacy migration and atomic invalid-restore rejection pass16 checks each in debug/release; legacy storage passes10.10001-record fixture visits only1 local record with10000 distant. Evidence: `docs/evidence/vehicle_fleet`. No live fleet is enabled: world persistence ownership, bounded body activation/driver pinning and presentation are next. Snapshot capture/restore remains indivisible bulk work; timing, distant rendering and fleet driving qualification remain open.

Vehicle fleet world persistence: vehicles component now uses native fleet validation/ownership, captures the live car pose into its identity and retains every other parked record. Legacy single-car archives migrate on load. Actual new-world save/reload passes9 checks; fresh-process reopen/reload passes7 with exact two-record archive and one reused frozen body.23 existing interaction/storage lifecycle checks pass. Evidence: `docs/evidence/vehicle_fleet_world`. Live scene still selects the lowest saved identity and exposes one car; bounded multiple-body activation/driver pinning remains next. Bulk capture/restore remains synchronous and large populations are not qualified. v2 vehicle saves require this updated owner; older single-car builds reject them. Only a new disposable slot was written during verification.

Vehicle fleet activation is opt-in via --vehicle-fleet: native64m nearest selection feeds a four-body reused scene pool at5Hz, admitting at most one per selection tick and pinning the driven identity. Parked retirement hides meshes and disables collision/physics; entry selects nearest resident; capture syncs all resident poses. Native-backed saved occupancy blocks duplicate placement and conservative edit overlap.12 graphical lifecycle checks pass with five records/four bodies, return reuse, identity2 entry, pinning and reload;23 legacy interaction checks pass.1080p screenshot inspected. Evidence: `docs/evidence/vehicle_fleet_activation`. Play Actors.cmd --vehicle-fleet dry-run forwards option. Not a completed fleet: unadmitted/distant records lack visual/collision representation; autonomous driving, damage state, real driving amongst parked cars, setup/frame cost and fairness remain open. Keep opt-in until those gaps are addressed.

Vehicle fleet loaded-road contact gate: normal-world activation admits two cars; keyboard-driven approach travels8.53m to contact at up to38.90km/h without passing through the frozen parked chassis. Space handbrake stops below0.15m/s, safe exit succeeds, capture preserves both poses, and readiness holds remain0.10 graphical checks pass;1080p screenshot inspected. Evidence: `docs/evidence/vehicle_fleet_driving`. Initial S-held stop fixture reversed after impact; failure retained and final test uses documented handbrake without changing production controls or thresholds. This closes bounded driven-vs-parked contact/exit integration only. Active-active dynamics, fleet frame cost, high-speed arrival, persistent damage and distant/overflow representation remain open; keep opt-in.

Vehicle fleet first cost check: empty/one/four stationary parked phases have120 frames each with terrain/cover settled throughout. Admission max2.328ms passes4ms budget; four-car steady adapter p95.114ms/max.203ms passes1/2ms budgets. All three framep95 gates fail18.5ms (19.184/18.723/18.724). Draw calls541/637/749 and primitives1.432/1.521/1.838million.13 checks pass,3 fail. Evidence: `docs/evidence/vehicle_fleet_cost`. Main-world process disabled, adapter manually advanced, fixed camera/occlusion and short sequential run: no complete-gameplay or thermal claim. Keep four detailed bodies and opt-in; do not tune tiny parked update cost or raise full-detail capacity. Next vehicle work addresses missing distant/overflow visual and collision representation; global frame pacing remains open.

Parked vehicle representation prerequisite: NativeParkedVehicleRenderer batches shared visual parts with preserved local transforms/material overrides and native fleet selection, excluding active identities. Fixed capacity1..256 vehicles and1..64 parts, no per-vehicle scene nodes; unchanged poses avoid transform uploads.10 graphical debug/release checks pass using two prototype parts, including rotated/scaled readback, incomplete-query hiding, identity removal and external-buffer rejection. Evidence: `docs/evidence/vehicle_parked_renderer`. Main-world extraction of actual car meshes, parked collision and active/static handoff remain next; this primitive alone does not close invisible overflow. It retains full source geometry, uses aggregate part culling and is not a lower-detail or GPU performance claim.

Parked vehicle world representation now connects actual32 vehicle mesh parts and exact static chassis box/offset to native batches. Up to64 selected records within128m, excluding four full-body residents, have bounded visuals/static collision; parked entry can promote by reusing a full slot and removing duplicate static representation. Distant-only initialization works without driving-body admission.17 actual-world checks plus14 native debug/release checks pass; five-car1080p screenshot inspected. Explicit null-material rejection was caught/fixed and failure retained. Evidence: `docs/evidence/vehicle_parked_world`. This closes the tested fifth-car disappearance/collision gap only. Beyond128m/64 selected records, aggregate culling, full-geometry GPU cost, prototype setup spikes and high-speed proxy encounters remain open. No reduced-detail geometry or fleet performance claim; keep opt-in and measure the changed path before extending capacity.

M3 parked-fleet cold setup now yields between creating the hidden vehicle template and configuring native parked batches/colliders. The world activation regression passes 18 checks. A short fullscreen1080p cap60 fixture covers 0/1/4/16/64 stored vehicles, at most four detailed bodies, and retained static representation. Initial first admission failed at 5.474 ms; after staging it measured 3.402 ms, with maximum across all phases 3.533 ms against the unchanged 4 ms gate. Steady adapter updates remain below 1 ms p95 / 2 ms max (64 records: .412/.632 ms). All five frame gates still fail: p95 18.772/18.759/19.146/18.780/19.004 ms against 18.5 ms. Evidence: docs/evidence/vehicle_parked_cost, including the original failure and raw rows. This fixture disables normal world processing and manually drives fleet updates; its fixed camera occludes much of the larger layout, and equal 16/64 draw/primitive counts do not prove dense rendering headroom. Cold readiness costs one extra activation tick (normally .2 s); individual setup stages remain synchronous. This closes the observed combined cold-call spike in this bounded sample only. Next fleet gate: representative visible populations and reduced-detail parked geometry; mixed frame pacing, bulk saves, continuous travel, thermal endurance and human acceptance remain open.

M3 parked visual population check: an isolated native batch using the actual 32-part car prototype renders 0/1/16/64 vehicles on an unobstructed plane. Fullscreen1080p cap60, 120 frames per phase after 30 warm-up frames; projection-bound checks and reviewed screenshots show all 64 vehicles. All frame-p95 gates pass: 17.212/18.021/18.325/18.173 ms against 18.5 ms; 64 GPU p95 3.729 ms on RTX4050. Evidence: docs/evidence/vehicle_parked_visible_cost. No terrain/vegetation/buildings, driving or activation workload participates; this isolates parked rendering and does not close the mixed-world failures, older-laptop thermal target or large-city qualification. Aggregate primitive monitor values do not scale with instance count in this fixture and must not be used to infer total submitted geometry. No new LOD optimization was justified or claimed by this sample. Next: retain this isolated reference and investigate mixed-world frame attribution before adding renderer complexity; continue original content coverage and human acceptance.

M3 cold-entry regression: requesting entry before parked-view initialization bypassed staged creation and synchronously admitted a body plus batches. The new world regression fails on the previous code. Entry selection now defers while the parked view is uninitialized and schedules an activation tick; both before-template and between-stage entry leave ownership/body state dormant. All 20 activation checks pass, including subsequent normal entry, parked promotion, collider replacement, driver pinning and reload. Evidence: docs/evidence/vehicle_cold_entry. This preserves the staged lifecycle across player input; no new frame-time or thermal claim.

M2 road editor persistence: width, depth, clearance, foundation shoulder and surface choice now survive compound world save/reload via a separate 48-byte versioned native road_editor section. Missing legacy sections restore defaults; malformed values reject before UI mutation. Recreated-world disk integration passes 36 checks (including existing anchor/paving checks); clean release codec passes 26 checks for exact bounds, headers, lengths and nonfinite rejection. Evidence: docs/evidence/road_editor_settings. Zig/prebuilt SDK debug and release builds succeeded without rebuilding godot-cpp. Endpoints, previews and in-progress construction remain transient; selected built streets still use road_anchors. This closes settings restoration only, not road authoring undo, performance or human acceptance.

Addon delivery coverage: packaging previously omitted player/vehicle runtimes and shipped one-folder archives despite external resource dependencies. The tool now supports all ten addons, explicit transitive dependency bundles, vehicle asset/provenance inclusion and a correct per-archive hash manifest. --addon permits targeted packaging without building the full source archive. Four Python contract checks pass, including existing literal-resource coverage across all bundles. The actual vehicle ZIP passes cache-free Godot import and separate-process native car instantiation (32 visible parts) plus fleet record creation. Evidence: docs/evidence/addon_packaging. This closes the identified packaging omissions only; dynamically constructed paths, host contracts, other addons clean-install testing, exported gameplay and non-Windows support remain unqualified.

Addon clean-install matrix now has an executable verifier and retained failures. Presentation, structures, world_ecosystem and vehicle_runtime pass cache-free import/resource loading; player_runtime, world_runtime, vegetation_runtime, volumetric_water, volumetric_terrain and vegetation fail headless editor import with 0xC0000005 on Godot4.7.2 Windows. All archives pass exact membership/hash verification. A bounded world_runtime follow-up reproduces the import crash but loads its four scripts successfully in a subsequent runtime process. Evidence: docs/evidence/addon_bundle_matrix. This is an open distribution blocker, not proof of runtime failure or an attributed engine bug. Next distribution investigation: isolate minimal extension import/shutdown lifecycle and capture a native stack before changing addon ownership or toolchain; avoid repeating the full matrix unchanged. Main-world first-round coverage and human checkpoint remain available.

Addon import isolation/mitigation: empty-project import exits0; the native-only vegetation bundle crashes with ordinary import and with 30 editor frames. Confirmed upstream issue111048 describes a matching deferred documentation cleanup race and an import frame-delay workaround. An explicit 1000ms import-only delay now passes all six previously failing bundles, with separate subsequent runtime resource loads and GDExtension-loaded checks. The verifier retains default behavior and separates workaround reports. Evidence: docs/evidence/addon_import_workaround. No game frame pacing, runtime binaries, SDK or host settings changed. Exact local attribution lacks a symbolized stack; immediate import remains failed and fixed delay is not a timing-independent repair. Distribution automation has a tested mitigation; retain engine compatibility limit and revisit on engine upgrade. End this bounded investigation rather than rebuilding the engine; resume original world-content/gameplay coverage.

Player/vegetation integration: stones, plants and grass clump resource stacks can now equip their placement mode from any of the six toolbelt slots. Shared eligibility controls both keyboard and button paths; H and number-key selection update the same visible active item. Equipping is non-consuming and rejects when ground cover is unavailable; existing native gameplay payment/free-editor behavior is unchanged. Temporary actual-world checks pass (editor 36, gameplay 33); screenshot reviewed. Evidence: docs/evidence/ground_cover_toolbelt. The final editor run additionally checks enabled belt buttons after review caught their old tool-only restriction. This closes the resource-equipping gap, not visual-art, density/performance or human acceptance gates.

Player pose regression after ground-toolbelt integration: resource IDs 201/204/205 exceeded the v1 pose tool range 0..4, potentially retaining a stale position on capture. Capture now maps transient resource placement to neutral tool0, preserving format compatibility; successful pose restore clears ground mode/context controls. The temporary graphical gameplay fixture passes 40 checks, including exact current-position capture for every species, non-consuming equip, enabled belt buttons, restore reset and collection/placement. Evidence: docs/evidence/ground_tool_pose. This checks capture/restore integration, not a new disk-save or performance qualification. Ground selection itself remains transient; inventory contents and vegetation edits retain their existing persistence.

Ground resource pose disk verification: a unique test world manually saves with grass placement active and a deliberately changed flying position, then inhibits shutdown writes. A separate process restores exact player pose bytes, actual spawn position, ground edits and non-default plant/grass inventory; normal F9 repeats the checks and clears transient placement selection. Producer passes 44 checks; consumer passes 23. Evidence: docs/evidence/ground_pose_disk. This closes disk/fresh-process verification for the recent pose mapping fix, at fullscreen1080p cap60; no user save was reused and no frame-time or endurance claim is made.

Road authoring lifecycle: loading, shutdown and driving previously gated only new section submission, allowing sampling/fit work to continue. A short regression reproduces three failed cancellations. The coordinator now rejects new preparation, rejects late results and cancels every active phase at these boundaries. All 16 controlled lifecycle checks pass with real native fitting and terrain submission stubs. Evidence: docs/evidence/road_mode_lifecycle. Already accepted terrain sections may finish; cancellation prevents further submission and does not roll back terrain. This is lifecycle correctness, not full-world driving/reload or performance qualification.

Furniture interaction coverage: extended actual-world block-floor fixture verifies paid placement, object-tool selection/removal, identity and selection invalidation, and absence of each removed furniture collider for table/chair/shelf. All 31 checks pass at fullscreen1080p cap60; no performance claim. Inventory stays unchanged on removal (no refund policy added). Initial collision assertion incorrectly demanded an empty ray despite the supporting floor; corrected to reject the removed furniture collider and retained initial log. Evidence: docs/evidence/furniture_interaction. This closes bounded furniture manipulation coverage; cottage-interior occlusion, deletion persistence and human acceptance remain distinct.

Furnished cottage interaction check passes 11 checks in the existing generated layout: each of four tables is selectable through an unobstructed interior ray; an exterior ray that hits its cottage wall cannot select or remove it. The complete structures snapshot remains byte-identical, and snapshot writes are inhibited. Evidence: docs/evidence/furniture_interior_selection. Fullscreen1080p cap60 configuration only, no frame-time qualification. This closes bounded table/interior occlusion coverage for these cottages; arbitrary layouts, chair/shelf interior viewpoints and deletion persistence remain separate.


Basic actor locomotion presentation now uses one shared 72-triangle articulated mannequin, native displacement-driven facing/phase/stride and a vertex shader, with no per-actor animation nodes. Animation history is bounded to the current render selection. A strengthened regression exposed retained state on readmission and an unchanged walking image; both failures are retained and corrected. Debug and clean release pass 22 checks each, including actual walking/idle image differences, idle zero-upload and selection churn among 1024 stored identities. Actual-world placement/selection/move/stop passes 19 checks; existing renderer release regression passes 30 and packaging contracts pass four. Short release native-renderer-only CPU p95 for 256 selected actors with 0/16/256 moving is .106/.139/.130 ms (max .223/.356/.175), below the predeclared 1/2 ms gates. Evidence: docs/evidence/actor_gait. Fullscreen1080p cap60, RTX4050; these exclude physics, selection, GPU execution and full frame cost. The initial population fixture incorrectly tried to reconfigure a live store; its error log is retained and setup now checks a separate store. This closes basic visible gait integration, not existing active-physics/mixed-frame failures, authored character animation, navigation, crowd scaling or human acceptance. Gait/facing are transient and reset on reload/readmission; original save format and actor caps are unchanged.


Vegetation transaction rejection coverage: actual main-world input now checks full-inventory collection, inventory removal after a successful placement preview, and repeated placement while publication is pending. Exact inventory revisions and ground state remain unchanged on rejection; the natural identity remains rendered and pickable. Combined with existing block/water exclusion and restoration checks, 66 checks pass in a new temporary world at fullscreen1080p cap60. Evidence: docs/evidence/ground_cover_rejection. The selected natural object was a grass clump; all three resource toolbelt mappings are checked, but this is not per-species collection qualification or a new performance/persistence result. Initial two fixture assertions read preview feedback instead of the action-notification field; original failure retained, runtime unchanged. Test JSON now includes all late assertions. Visual/density, sustained performance and human acceptance remain open.


Ground-cover appearance: shared procedural startup assets replace the sphere/flat-fan placeholders with an irregular 54-triangle stone, 28-triangle folded-leaf plant and 15-triangle bent grass clump. Opaque vertex colours, existing native batches, identities, picking envelopes and shadow policy remain. Asset geometry stays inside semantic interaction bounds. Actual-world gameplay/toolbelt/rejection/block-water exclusion regression passes66; packaging contracts pass4. Evidence: docs/evidence/ground_mesh. Isolated3072-instance ABBA at fullscreen1080p cap60 passes all four frame-p95 gates (17.521/17.642/17.544/17.360ms), but the conservative GPU difference fails: worst new p95 4.139ms minus best old1.600ms =2.539ms against0.5ms. Baseline itself drifts1.600 to3.261ms, preventing a causal optimization claim; retain failure rather than rerunning unchanged. Initial pale colour version and its weaker max-baseline comparison are retained as superseded evidence. This improves provisional appearance only; it does not close density/LOD, mixed GPU cost, thermal, art-direction or human-acceptance gates. Next vegetation qualification needs controlled GPU timing and representative mixed density before claiming headroom.


Runtime terrain/lake cache now has a native exclusive Windows owner, bounded recency index and checked one-file eviction on existing idle worker slices. Full accounting can complete above quota, allowing old caches to recover instead of remaining permanently write-disabled. Default quota stays512MiB; canonical/unknown files are not candidates and hidden/unknown bytes count. Contending updated processes are read-only; temporary reader locks defer rather than permanently invalidate caching. Debug/release each pass23 parent assertions plus3 separate-process checks; bounded scan, idle preemption and disabled-cache regressions pass; four junction/corrupt-cleanup checks preserve the outside fixture. Actual-world final test passes9 checks at fullscreen1080p cap60:183 writes,169 evictions,2,055,368 bytes within a2MiB quota, no write failures. Evidence: docs/evidence/cache_eviction. This closes the reproduced capacity cutoff for recognized rebuildable packets, not mining continuity, hard I/O deadlines, disk reserve, directory growth, full cross-version coordination or endurance.

Cache test incident retained: the first world fixture assigned backend.cache_path before the facade replaced it with user://terrain_cache. The2MiB test budget consequently evicted535,330,268 bytes of rebuildable normal-cache data. The temporary world skipped canonical saving; cold cache regeneration may affect later loading cost. The original report's path was the intended path, not the actual one, and is explicitly superseded. The fixture now requires an explicit fresh --derived-cache=user://cache_eviction_world_UNIQUE before creating the scene, seeds two real obsolete-signature packets there, checks the actual worker path, and reports it from the cache owner. No attempt was made to hide the incident or claim a warm performance baseline afterward.

Ground-cover mesh LOD now uses native ArrayMesh index tiers: stone54->12, plant28->14, grass15->5 triangles. Shared startup assets retain identities, density, native picking and saved edits; no per-instance script or LOD loop. The28-check graphical fixture proves exact near-image equivalence, expected native per-page near/far counts and unchanged placement snapshots. Actual-world interaction/exclusion passes66 checks using an isolated cache. Initial engine counter mismatch and focus-cap failures are retained and explained in docs/evidence/ground_mesh_lod. This closes the missing mesh-LOD path only; artwork remains provisional, representative final-asset density/GPU/thermal qualification and earlier GPU failure remain open. Automation now keeps its foreground/background cap60 throughout the world fixture, without changing normal gameplay policy.

User-directed vegetation art pass: natural temperate woodland sample now replaces the simple main-world stone/plant/grass assets. Original0BSD mesh authoring, reproducible stone colour/normal maps, folded leaflets/stems, curved green/dry blades and restrained shader wind provide a more representative visual workload. Near triangles360/1512/504, distant48/392/72; this is higher detail, not an optimization claim. Visual14, native LOD28, actual-world interaction/exclusion66 and packaging4 checks pass. Evidence: docs/evidence/woodland_art. World screenshot HUD51FPS retained; sustained60FPS remains unqualified. One shape per category, fine-blade aliasing, sparse distribution, art refinement and human acceptance remain open. Next prioritize user visual review and representative species/shape variants before further vegetation performance tuning.

Dense woodland review responds to sparse-art feedback: Play Woodland Preview.cmd creates a disposable14.4m-square authored patch (858grass,66plants,21stones), with normal interaction and no saved-world writes. Player-height screenshots and handoff check retained in docs/evidence/woodland_patch; guide docs/WOODLAND_PREVIEW.md. It exposed authored support rounding:945accepted/170published before,945published after a native interpolated density query plus validated worker handoff. Existing integer/depth probe semantics remain. Native debug/release10each, streaming83 and actual-world interaction/exclusion/mined-support checks pass. The120-frame combined sample still fails18.5ms p95 at18.774ms (max20.949, GPU p95 5.811ms), not sustained60FPS or vegetation-only attribution. Fine-blade aliasing, repeated forms, global density/biome design, final art acceptance and sustained headroom remain open. No global density increase or saved-world migration.

### 2026-10-11: sparse woodland accents

Added three collectible flower colours, low bushes and dry wood-yielding twigs to
the native ground-cover pipeline and disposable dense preview. Existing save
versions migrate on write; removal identities remain stable. See
`evidence/woodland_accents/README.md`. This is content coverage, not closure of
the open frame-time/thermal gates or final vegetation art acceptance.

### 2026-10-11: human vegetation shape feedback

Reworked grass fans into broader leafy clumps, crossed dry sticks into standing
woody scrub, and enlarged bush crowns. See `evidence/woodland_shape_review`.
Same population and interaction bounds; native LOD checks pass, grass retains
its 72-triangle distant budget. Terrain integration and final art acceptance
remain open; short GPU time increased and the frame-time gate remains open.

### 2026-10-11: optional generated grass texture

Added an image-generated leaf surface as a grass-only, default-off F7 toggle.
Short off/on/off review and evidence are in `evidence/grass_texture`. Shapes and
density unchanged. User acceptance pending; no sustained-performance claim.

### 2026-10-11: grass texture readability feedback

Generated a stronger texture and corrected uniform dimming, but human review
rejected it as cartoonish/unrealistic. Archived at `evidence/grass_texture_v2`,
including its implementation and measurements. Live material restored to v1,
untextured by default. Numeric checks do not constitute visual acceptance.

### 2026-10-11: grain-based grass art review

Added optional v3 generated leaf grain and matte shading after rejection of
strong vein bands. Corrected narrow-blade UV proportions. Same texture and
geometry budgets; human visual/motion acceptance pending. Evidence at
`evidence/grass_texture_v3`; broader performance gates stay open.

### 2026-10-11: connected earned-resource persistence evidence

The new `tools/check_gather_build_loop.py` uses a fresh isolated main-world save:
three natural stones -> UI crafting -> paid brick -> rejected unaffordable second
block -> normal save -> exact fresh-process restore.32 checks pass, including
collision at the placed block and normal headlamp use input. Evidence:
`evidence/gather_build_loop`. No runtime defect found; this closes only the tested
resource/persistence path, not full combined-settlement or gameplay coverage.

Next audit and implementation target: usable building access and interiors,
including the originally requested ladders. Static furniture, shell generation
and this single-block check do not satisfy that requirement. Retain M2 as active;
no additional grass-polish iteration is scheduled.


### 2026-10-11: usable ladder access

A shared 168-triangle wooden ladder is available as object 7. Six wood in gameplay,
free in the editor; stable native placement identities use existing history, storage
and streaming. Native climbing uses at most two short physics rays per tick, W/S
ascent/descent, idle hold and Space jump-off with recapture cooldown. Standard
capsule collision resolves ceiling, wall and top landing; no teleport. Nearby
collision residency is capped at 128 one-shape ladder proxies. Upright unit-scale
ladders only; resizing/tilting creates an ordinary non-climbable prop.

Nineteen traversal checks pass in debug and clean release; existing walking/swim
and tower-stair checks pass. Normal main-world paid placement, controller ascent
onto a three-metre block landing, save and fresh-process reload pass 21 checks total
at fullscreen 1080p with cap60. Evidence: evidence/ladder_access. Test inventory
setup errors and an editor-import process failure are documented there. These
checks do not qualify sustained performance, arbitrary-height access, multiplayer,
or a complete playable settlement. M2 remains active.


### 2026-10-11: storage transaction prerequisite

NativePlayerInventory now provides atomic transfer_to between two inventories,
with expected revisions for both sides. Full destinations, unsupported items,
invalid amounts and stale commands leave contents and revisions unchanged;
success advances each side once. Destination work is bounded by 32 slots.
Twenty-nine checks pass against debug and release DLLs, including 1000 deposit/
withdraw cycles, mixed stack limits and post-transfer binary roundtrips. Existing
player inventory checks pass. Evidence: evidence/inventory_transfer.

This is a storage prerequisite, not a usable-container deliverable. Next wire
container contents to stable model identity and normal world persistence, enforce
nonempty removal/undo protection at the native placement boundary, then add the
reachable interaction and transfer UI. Explicitly test deletion, undo, ID reuse,
region unload/reload and fresh-process restore of both sides before calling the
container usable. Avoid one script or active physics body per stored item, and
keep container residency/save growth explicit; large-world storage qualification
remains open. The broader M2-M6 plan is unchanged.


### 2026-10-11: model ownership deletion interlock

NativeStaticBatch now supports explicit per-ID removal protection for contents
owners. Protected IDs reject normal deletion, undo deletion, mixed bulk deletion
and whole replacement. Transform changes retain identity. Synchronous and
incremental streaming retirement/admission preserve protection while releasing
placement residency; reserved IDs cannot be stolen. Whole-world restore preflights
all collections before changing blocks, including native bootstrap. Protection is
runtime-only, not a substitute for saved contents. Existing worlds enable none.

Thirty-six checks pass against debug and release DLLs; existing static-model-region
regression passes. Evidence: evidence/model_removal_protection (including a failed
cold-retirement fixture corrected to release rendering residency). No performance
or usable-container claim. Next implement contents ownership/persistence and UI
using the verified transfer and removal interlocks, with explicit handoff on reload;
then test the complete place/deposit/withdraw/save/reopen route. M2 remains active.

### 2026-10-11: usable wooden chest storage

Object 8 is a dedicated wooden chest: eight wood in gameplay, free in the editor.
E on foot opens its 32-slot inventory; bounded native atomic transfers, stable
placement ownership and normal compound saves connect it to the player inventory.
Filled chests reject removal; emptying releases ownership. Shelves are furniture,
not containers. Salvage rewards and independent book/item pickup remain unfinished.

Nonempty contents are sparse and capped at 4,096 chests, sharing one immutable
item catalog; geometry uses normal native static batching and nearby box collision.
There is no per-chest script or idle inventory tick. Cold contents remain resident.
Twenty-three native checks pass in debug/release, including full-capacity encoding;
36 actual-world create/reopen checks pass with 1080p fullscreen and cap60. Retained
screenshots and logs: [chest storage evidence](evidence/chest_storage/README.md).
This is one usable interior interaction, not dense performance or complete M2
coverage. Combined human feedback is the next checkpoint, not more isolated polish.

### 2026-10-11: chest/vehicle interaction priority

Combined-route review found E attempted proximity-based vehicle entry before
opening an aimed chest. Input now opens a reachable aimed chest first; if none
is targeted, normal nearby vehicle entry remains available. Object-mode selection
and ground-cover mode still own their advertised E actions. The test offers a
vehicle-entry probe through the actual world input dispatcher and chest physics
picking, rather than spawning another vehicle simulation. Retained before/after
results live in evidence/chest_interaction_priority. This is input arbitration
coverage, not vehicle driving or combined performance qualification.

### 2026-10-11: furnished storage integration

New main-world furnished cottages include an independent wooden chest alongside
the existing shelf. Both paid prefab routes now use chest/ladder recipes shared
with individual placement. Thirty-two native-backed prefab checks and eight real
world checks pass; legacy furniture-only placement still passes. Evidence:
[evidence/storage_interior](evidence/storage_interior/README.md). Existing saved
houses are unchanged. Full-scene model capture, salvage, human acceptance and
performance qualification remain open; the short screenshot HUD reads 56 FPS.

### 2026-10-11: furniture dismantling yields wood

Gameplay object removal now dismantles shelves/tables/chairs for provisional
4/3/1 wood, provided the complete reward fits. Three-metre reach and native removal
protection apply. Successful salvage clears history to prevent undo duplication;
free-editor removal yields nothing. Eight native-backed checks and the actual
1080p object-tool route pass. [Evidence](evidence/furniture_salvage/README.md).
Loose books, whole-furniture pickup, damage/break animation and human acceptance
remain open. This adds a usable gather/build interaction without a per-object tick.

### 2026-10-11: accessible combined gameplay checkpoint

Play Combined Gameplay.cmd now creates a one-time separate copy of the furnished
editor world and enables gameplay construction alongside ground cover, actors and
fleet. Later launches preserve gameplay progress; the editor slot is untouched.
A 40-file real-copy/startup check passes with unchanged source hashes, alongside
copy refusal/no-overwrite checks. Evidence: evidence/combined_gameplay_launcher.
Human feedback remains the next coverage gate; no performance gate is closed.


2026-10-11: User-requested UI integration supporting the player/toolbelt/inventory
coverage row and the combined human checkpoint: Escape action menu, explicit local
development mode, ten belt slots, native exact-slot chest transactions and real
GUI drag-and-drop. The keyboard instruction wall is hidden. Gameplay/editor
accounting remains distinct and chest persistence regressions pass. See
[UI guide](PLAYER_UI.md) and [scoped evidence](evidence/player_ui/README.md).
Human usability acceptance and sustained performance remain open; M2 stays active.


2026-10-11: Follow-up to human UI confusion: Actions now docks the complete
building/object/road palettes, with explicit development-only authoring. The
old four selector IDs become pickaxe, hatchet, building hammer and assembly
tool items with local gameplay actions and held meshes. Empty belt slots and
material stacks cannot retain an editor; E interaction is independent of
placement tools; tilde+F no longer reaches the headlamp. Existing inventory
formats/slots are preserved. See [updated controls](PLAYER_UI.md) and
[functional evidence](evidence/unified_tools/README.md). This supports the
player/inventory coverage row and human checkpoint; M2 remains active. Tool
art/balancing and sustained combined performance are not claimed complete.


Regional water replaces the fixed-basin gameplay dependency: native 0.5 m finite-volume cells in 4 m regions now support mining while wet, bucket creation of water outside lake definitions, recoverable one-litre puddles, local developer removal, compound saving and cached occupancy restoration. The normal loading screen publishes cached water before gameplay and holds restored flow until admission. Prepare Water World.cmd prepares the saved spawn area; Play Water Gameplay.cmd uses a fresh water_gameplay_v2 slot while preserving the older slot. The 34-assertion actual-world test passes in 28.21 s at fullscreen1080p cap60. A separate cold-preparation / fresh-graphical-process pair restores 48 cached regions with zero samples and zero fluid steps. Native flow slice max 1.187 ms; whole-frame p95 17.709 ms and max 49.620 ms on RTX4050 show this is not a hitch-free or thermal qualification. Evidence and retained failures: docs/evidence/regional_water. Structure occupancy, shoreline refinement, wet-region paging, large-body behavior and combined endurance remain open. The fixed-basin restrictions in older log entries are historical, not the current runtime contract.

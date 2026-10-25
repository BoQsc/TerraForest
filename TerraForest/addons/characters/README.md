# Character integration

The original Human R11 and Zombie Lab deliveries are preserved in this folder.
Their `.gdignore` files keep independent demos, Blender sources, old import
identities and historical evidence out of TerraForest's resource scan. Open the
original `project.godot` directly to use either independent viewer.

`runtime/` contains the TerraForest adapters and byte-identical copies of the
active Human R11 and Zombie R4 GLBs. Git shares identical asset blobs with the
original packages. Only these two models are imported by TerraForest. Import at
60 Hz, retain embedded textures and disable tangent generation for the source
surfaces that have no UVs. See Godot's [embedded image modes](https://docs.godotengine.org/en/stable/classes/class_gltfstate.html).

## Try it

Run `Character Preview.cmd` from this checkout's TerraForest folder, or:

```text
python tools/run.py --temporary --gameplay-construction --zombies
```

This launches a disposable world. Normal gameplay construction launches enable
zombies too. `--zombies` enables encounters in an editor launch; switch off
Development mode to use gameplay melee. `--no-zombies` overrides either mode.
The free editor has no encounters unless requested. Existing saves remain valid.

Standing zombies now use the Blender-authored `Zombie_Walk_Drag_Right`: a slow
two-second limp with the right toe dragging and the left leg bearing weight.
Revision 2 adds a longer planted stance, weak-side compression, a forward hunch
and uneven hanging arms with delayed follow-through. The default body speed is
0.45 m/s; playback follows measured body travel and holds when collision stops it.
The original walk is preserved and selectable with `dragging_walk=false`.
See the [editable source and rebuild steps](authoring/Zombie.drag_walk.README.md)
and [current gait verification](../../docs/evidence/zombie_weighted_limp/README.md).

The R11 first-person rig replaces the former box hands, pickaxe and axe. Belt
selection drives equipment visibility; native motor velocity drives fixed-grip
pickaxe and axe walk/run/jump
presentation. Empty hands use a low relaxed neutral pose
between actions, including while moving. Head, mouth, eyes and hair are hidden in first-person view. The
source full body remains available for later third-person presentation. Existing
hammer/shovel animations and the assembly tool remain available. The water bucket
now uses a Blender-authored PBR pail and an actual right-hand carry grip, with
walk/run and cosmetic scoop/pour actions. Its interior reflects the inventory's
water amount. Pickup and icon use the same model. See
[bucket authoring](authoring/Human.bucket.README.md).

Empty toolbelt slots now use `FP_Unarmed_Idle` and a separate
`FP_Unarmed_Punch`. The right fist closes before extension, contacts at 0.467 s and
returns to neutral over a 1.133 s cycle. The resting hands turn inward with
loosely curved fingers. Empty-hand reach is 1.65 m as a gameplay allowance;
equipped tools retain their existing 3.5 m reach. Both hands use repaired finger skin weights
while empty; equipping a tool restores the original mesh and grip weights. The
first two punches were rejected for broken deformation and then an instant,
flat-screen feel. The current revision is accepted for now. Left mouse keeps the existing bare-hand
damage/target rules and consumes no tool wear. Placement remains a separate
gesture. Original third-person body locomotion is retained while moving.
See [unarmed authoring](authoring/Human.unarmed.README.md) for rebuild and review.

## World zombie population

Zombies are world inhabitants, not an elapsed-play-time encounter refill. Native
seeded placement assigns stable identities to 2,500 jittered candidate locations
across the 2 km world. Unsuitable slopes, water and the 40 m initial-arrival
sanctuary are excluded. Terrain support is resolved on the terrain worker as
regions become relevant; there is no world-sized physics or scene-node allocation.
Nearby residents are instantiated behind the loading screen before input opens,
including on reload and teleport. The loading panel exposes candidate checks,
active count and pending terrain sampling under `Loading world inhabitants`.

The native spatial index queries at most 32 candidates within 88 m when focus moves
16 m. At most six controllers are active; outside 96 m their scene bodies retire
but their identities, positions, yaw, shared health and individual limb damage/
detachment persist. Dormant residents do not simulate. During ordinary travel,
activation skips candidates in the camera frustum or within 40 m; it does not
invent a replacement, relocate a zombie or refill merely because time passes.
Admission still requires ready terrain/structure/tree collision, a supported
capsule and dry ground. Simulation pauses during loading, edits, menus, inventory,
driving and focus loss; temporarily missing collision freezes living residents.

`zombie_population_v1` is a validated 210,032-byte native binary section in the
existing compound world save. Old saves without the section initialize the seeded
population on first load, without altering their terrain or construction. Death
marks its identity permanently dead; the existing separate corpse inventory/pose
store owns the lootable corpse. No automatic respawn timer exists. Reload restores
survivors' injuries and missing limbs, including a crawler's prone capsule/pose.
Fixtures can disable population admission with `population_enabled=false` while
retaining explicit `spawn_at` for combat tests. `--no-zombies` still disables the
gameplay feature. Population tests cover native binary state and integrated world
loading/travel; this does not qualify whole-world navigation or population balance.

`NativeZombieAwareness` owns bounded session intent and randomized roaming goals.
Unaware zombies wander between short pauses. They notice an unobstructed player
within a 120-degree forward cone and 24 metres; close awareness within 3.5 metres
still requires clear sight. Engaged sight extends to 36 metres. Losing sight
sends them to the last seen position, without tracking hidden player movement;
arrival starts a six-second local search. Eighteen seconds without sight or a
blocked pursuit ends interest and resumes roaming. Striking a zombie provokes
investigation. Unreachable visible targets also receive a retry cooldown.

Perception is staggered at four updates per second per resident, with at most two
sight eligibility probes per physics tick. Physics supplies actual occlusion and
support; existing native navigation and guarded movement execute all destinations.
Wander/search positions are not attack recipients. Combat still requires the
authored live contact checks. Intent, goals and perception counts are available
in behavior/manager snapshots. See [behavior evidence](../../docs/evidence/zombie_awareness/README.md).

Pursuing zombies now use the same native `ActorRoute` core as settlement actors,
through `NativeActorNavigator`, while retaining their own animated body and combat
controller. They route around static obstacles, use bounded native stair movement,
and apply dry-ground admission. The shared [navigation standard](../../docs/NAVIGATION_STANDARD.md)
defines profiles, limits, failures, permissions and remaining world-scale gates.

Zombies collide with other zombies, existing actors, vehicles and the player. A bounded neighbour
steering pass lets following zombies move around a blocked peer; a native motion
guard checks the resulting direction against route geometry. Availability refreshes preserve attacks and
traversal until the mode actually changes. Learned approach distances respect
solid player clearance, including the prone bite proxy.

R4 retains authored pursuit, attack contact checks, hit reactions, living crawl
after leg loss, severing and ragdolls. Player melee picks fitted limb areas with
solid-world occlusion, applies damage, and charges the existing equipped tool's
wear once, at the held tool's contact marker and with its full recovery.

Zombie hits now subtract full weapon damage from one shared 180 HP total,
regardless of the attached region hit. The combat bar always shows that total;
the struck limb's separate health appears underneath as a smaller readout and
thin secondary bar. The user wants that information visible for now, with possible
debug-only presentation later. Native limb integrity remains separate:
`unarmed` impacts cause no sever trauma, ordinary `melee` applies
30%, light `cutting` applies 50%, and `heavy`/`firearm` applies 100%. The current
hatchet uses cutting; the other carried tools use melee. Existing direct sever
debug actions remain available. New weapon/projectile adapters can pass the
named impact profile through `zombie_world.apply_hit`; this does not add guns.
Head detachment is still fatal, and lost chains still constrain attacks/crawling.
See [shared-health evidence](../../docs/evidence/zombie_shared_health/README.md).

Source jump/ladder request APIs
remain available but have no automatic jump or ladder-link selection.

Closed wooden doors blocking pursuit become explicit approach/attack targets.
Only validated authored contacts damage the existing native durability store.
Destruction removes the actual placement and hinge state, invalidates routes and
marks the world dirty. It grants no player salvage and consumes no player tool.
Zombies do not open doors. Other protected/unbreakable obstacles remain blocked.

Standing and crawling profiles are conservative; the latter does not yet support
low tunnels or stairs. The local search remains bounded to +/-16 m with at most
2,048 nodes. A derived regional graph handles farther targets and different
storeys using the same physical edge evaluator, retaining height and discovered
cross-tile connections. It requests bounded collision interests within the existing
archive paging domain. See [regional contract](../../docs/REGIONAL_NAVIGATION.md)
for cache/query limits and acceptance evidence. Unknown or failed routes stop.
External planning has twelve local or up to 48 regional quanta per tick under a
cooperative 750 us deadline; the legacy actor pool has another twelve. Motion
guards and perception add work outside those planning counts.

Collision bits: world `1`, player `2`, zombie body `1 << 16`, fitted hit areas
`1 << 17`, ragdolls `1 << 18`. The runtime copy of `zombie.gd` differs from its
preserved CC0 source in default model path, collision bits, R4 revision, walk
reference speed, idempotent behavior refreshes, crowd steering, and player/prone
approach clearance, native route following, collision masks and guarded native
grounded movement. New adapters use 0BSD.

## Remaining work

This is the first integration milestone. Zombie contacts emit damage feedback and
record session damage; player health, death/respawn, balancing, loot and encounter
persistence remain unimplemented. Local routing around obstacles and wooden-door
attacks and regional walking are implemented. Actual saved tower/cave round trips
pass; arbitrary buildings, full-domain pressure and continuous moving-target
endurance remain unqualified. See the [regional evidence](../../docs/evidence/regional_navigation/README.md).
Automatic traversal, full-body third-person view, outfit slots, authored empty-hand
punches, construction grips, draw/stow transitions and camera/tool wall clipping
need follow-up work. Six actors is a bounded prototype, not a measured scalability
claim. Do not treat this as a complete survival system.

`tests/character_runtime.gd` checks the two imported rigs, equipment, contact and
damage, collision gates, lifecycle and bounds. `tests/character_world.gd` checks the
actual world, belt, melee, wear, restore and save-schema integration.
`tests/zombie_encounters.gd` runs six pursuing zombies against a solid player with
the manager refreshed every physics tick; `tests/zombie_world_combat.gd` leaves
the actual host physics running and checks attack contacts and Escape-menu
suspend/resume. See the [follow-up evidence](../../docs/evidence/zombie_encounters/README.md)
and retained evidence in `docs/evidence/character_integration/` and the linked requirement in
`docs/WORLD_FOUNDATION_STATUS.md`.

`tests/zombie_navigation.gd` verifies routed wall/stair arrival, moving goals,
deep-water avoidance, sealed rooms, edit invalidation and missing coverage.
`tests/zombie_door_interaction.gd` uses the actual host wooden-door collection,
durability, removal, hinge cleanup and provider snapshot; a full fresh-process
door-destruction save/reopen gate is still required.

## Pickaxe presentation and alternates

The selected pickaxe action is the fresh downward stroke accepted in a live
playtest on 2026-10-24 (`FP_Pickaxe_Fresh_Swing`). Both hands keep fixed transforms
on the shaft through its 1.7-second cycle. Contact occurs at frame 50 of 60 FPS
(0.833 seconds), and recovery returns to `FP_Pickaxe_Fresh_Idle`. Separate
`Human.pickaxe_locomotion.res` clips now add walking/running/jumping while keeping
both hands at the accepted shaft stations. Movement appearance awaits playtest.
Empty hands continue to rest between
deliberate actions. The original model, 71 source clips, axe and placement remain.

`pickaxe_swing="pullback"` selects the former default;
`pickaxe_swing="diagonal"` selects the earlier forward strike for comparison;
`diagonal_pickaxe=false` selects the original pickaxe presentation. The side-strike
and latest five-degree-right arc-swing libraries are retained as optional review
alternates, with Blender sources, videos and test tools. The arc swing has not
received user visual acceptance and is not the default.

The user explicitly approved the fixed-grip version as better and requested
default selection and a commit on 2026-10-24. Earlier evidence files saying
“uncommitted” or “do not commit” describe historical review states. See
[fixed-grip evidence](../../docs/evidence/pickaxe_fresh/README.md) for the current
decision and [previous release evidence](../../docs/evidence/pickaxe_integration/README.md).

## Relaxed placement animation

Blender-authored `FP_Place_Relaxed` adds a 0.9-second empty-hand gesture for
accepted block placements and terrain-fill submissions. The whole hand is held
low; the wrist stays aligned with the forearm. The index is softly extended,
the remaining fingers loosely curled and the thumb naturally opposed. Equipment
returns afterward, and held placement cannot restart an unfinished gesture.
The empty hand automatically returns to its neutral hold when the one-shot
ends and stays there until another action; movement does not play the placement
pose or generic full-body arm swings.
The original 71 clips and runtime GLB are unchanged; a compact AnimationLibrary
supplies the additional clip. See the [editable Blender source and rebuild steps](authoring/README.md)
and [review evidence](../../docs/evidence/human_placement/README.md).

## Provenance

The Human viewer README records Human R11 as CC0-1.0, derived from a user-provided
character with repaired geometry, textures, rig and equipment. Zombie Lab includes
the CC0 dedication copied into `LICENSE.txt`. Preserve the original packages for
source and historical provenance; their prior validation claims are not evidence
for this new integration. The optional AK-47 is not loaded into TerraForest.

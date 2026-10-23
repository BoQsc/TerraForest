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
The default body speed is 0.45 m/s, with playback matched to movement speed.
The original walk is preserved and selectable with `dragging_walk=false`.
See the [editable source and rebuild steps](authoring/Zombie.drag_walk.README.md)
and [gait verification](../../docs/evidence/zombie_drag_walk/README.md).

The R11 first-person rig replaces the former box hands, pickaxe and axe. Belt
selection drives equipment visibility; native motor velocity drives authored
pickaxe/axe walk/run/jump presentation. Empty hands keep the original idle pose
between actions, including while moving. Head, mouth, eyes and hair are hidden in first-person view. The
source full body remains available for later third-person presentation. Existing
hammer, assembly tool and water bucket previews remain available.

## Zombie encounters

The manager admits at most six live/corpse controllers combined, one per four
seconds, 12–24 metres from the player. Four candidate probes per interval reject
missing collision, unsupported/steep ground, water and occupied capsules. Admission
and movement use the host's terrain/structure/vegetation collision-readiness gate.
Controllers suspend during loading, edits, menus, inventory, driving or focus loss.
Unknown collision holds living actors until coverage returns; distance over 96
metres retires them. Corpses retire after 20 seconds or on suspension/unready
collision. Detached bodies freeze during suspension and are removed
with their owner. Encounters clear on world pose restore and are not persisted.

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
wear once. Pickaxe/axe zombie strikes use the source 1.2-second action duration;
terrain/tool behavior retains its existing cadence. Source jump/ladder request APIs
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

## Relaxed placement animation

Blender-authored `FP_Place_Relaxed` adds a 0.9-second empty-hand gesture for
accepted block placements and terrain-fill submissions. The whole hand is held
low; the wrist stays aligned with the forearm. The index is softly extended,
the remaining fingers loosely curled and the thumb naturally opposed. Equipment
returns afterward, and held placement cannot restart an unfinished gesture.
The empty hand automatically lowers into its original idle when the one-shot
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

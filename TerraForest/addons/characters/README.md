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

The R11 first-person rig replaces the former box hands, pickaxe and axe. Belt
selection drives equipment visibility; native motor velocity drives walk/run/jump
presentation. Head, mouth, eyes and hair are hidden in first-person view. The
source full body remains available for later third-person presentation. Existing
hammer, assembly tool and water bucket previews remain available.

## Zombie encounters

The manager admits at most six live/corpse controllers combined, one per four
seconds, 12–24 metres from the player. Four candidate probes per interval reject
missing collision, unsupported/steep ground, water and occupied capsules. Admission
and movement use the host's terrain/structure/vegetation collision-readiness gate.
Controllers suspend during loading, edits, menus, inventory, driving or focus loss.
Lost collision or distance over 64 metres retires them; corpses retire after 20
seconds or on suspension. Detached bodies freeze during suspension and are removed
with their owner. Encounters clear on world pose restore and are not persisted.

Pursuing zombies collide with other zombies and the player. A bounded neighbour
steering pass lets following zombies move around a blocked peer; it does not
provide navigation around buildings. Availability refreshes preserve attacks and
traversal until the mode actually changes. Learned approach distances respect
solid player clearance, including the prone bite proxy.

R4 retains authored pursuit, attack contact checks, hit reactions, living crawl
after leg loss, severing and ragdolls. Player melee picks fitted limb areas with
solid-world occlusion, applies damage, and charges the existing equipped tool's
wear once. Pickaxe/axe zombie strikes use the source 1.2-second action duration;
terrain/tool behavior retains its existing cadence. Source jump/ladder request APIs
remain available but have no automatic world obstacle or ladder selection.

Collision bits: world `1`, player `2`, zombie body `1 << 16`, fitted hit areas
`1 << 17`, ragdolls `1 << 18`. The runtime copy of `zombie.gd` differs from its
preserved CC0 source in default model path, collision bits, R4 revision, walk
reference speed, idempotent behavior refreshes, crowd steering, and player/prone
approach clearance. New adapters use 0BSD.

## Remaining work

This is the first integration milestone. Zombie contacts emit damage feedback and
record session damage; player health, death/respawn, balancing, loot and encounter
persistence remain unimplemented. Direct pursuit does not route around buildings.
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

## Provenance

The Human viewer README records Human R11 as CC0-1.0, derived from a user-provided
character with repaired geometry, textures, rig and equipment. Zombie Lab includes
the CC0 dedication copied into `LICENSE.txt`. Preserve the original packages for
source and historical provenance; their prior validation claims are not evidence
for this new integration. The optional AK-47 is not loaded into TerraForest.

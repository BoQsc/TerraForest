# Zombie crowd and autonomous attack correction — 2026-10-23

User playtesting exposed zombies overlapping each other and staring at the player
without completing attacks. The initial integration fixture did not reproduce the
host's repeated encounter-manager updates: it enabled behavior once and then let
the controller run on its own. That earlier passing contact check was insufficient.

## Reproduction and correction

`set_behavior(true)` cancelled the current action even when behavior was already
enabled. The host calls it every physics tick, so attack windups restarted before
their authored contact marker. Reapplying the existing mode now preserves the
active action; a real mode transition still cancels it and restores playback.

Zombie movement capsules previously collided only with the world. They now also
collide with the player and other zombies; the host player uses the matching
zombie layer. A local steering pass over at most six actors moves followers past
a nearby peer rather than leaving them queued behind one blocker. It performs at
most 30 ordered neighbour checks per host tick and does not scan world contents.

Learned approach distances cannot require entering the solid player capsule.
The prone proxy sits behind its animated mouth so a living crawler can still
approach far enough to bite. Contacts retain animated surface, range, facing and
solid-world obstruction checks; this change does not apply damage by proximity.

The pre-fix crowd reproduction failed six of its 14 checks with the manager
running every physics tick. Its failing log/manifest remain here. The final crowd
fixture adds three living-crawl checks and passes all 17. The fixture includes a
visible cyan capsule for the stationary player and six zombies approaching from
one side, including queued followers.

## Final verification

Godot 4.7.2 Steam, Windows x86-64. Rendered checks use Forward+ on the RTX 4050 at
1920 × 1080, capped at 60 FPS. All **75 focused checks** pass:

| Suite | Checks | Scope |
| --- | ---: | --- |
| `zombie_encounters` | 17 | Per-tick manager, six-actor spacing, completed attacks, multiple attackers, pause/resume and living crawl against a solid player |
| `zombie_world_combat` | 9 | Actual world physics left active, real player contact/damage adapter, real Escape-menu suspend/resume |
| `character_runtime` | 31 | Existing rig, presentation, hit, severing, lifecycle and bounded-spawn checks |
| `character_world` | 18 | Existing belt, melee, wear, block damage/destruction, restore and save-schema integration |

The crowd check records minimum centre spacing **0.48078 m**, greater than the
combined 0.48 m capsule diameter, four zombies making contact during its crowd
phase, and four confirmed crawler bites in the later phase. The live forest-world
check records 73.8 damage at the player contact adapter and successful attacks
after closing the Escape menu. Damage remains the existing session counter and
feedback; survival health/death is still pending.

The final `crowd.png`, `crawl.png` and `attack.png` were inspected. They show
separate torso positions around the player capsule, a live crawler facing the
capsule, and an attacking zombie in the actual forest world. This is sampled
visual verification, not certification of every animation frame or limb clearance.
The colliders prevent locomotion-body interpenetration; extended animated arms
can still cross another character's animation.

`checks.json`, individual logs/manifests, sampled behavior reports and
`implementation.sha256.json` retain the runs and exact tested file identities.
The preserved source deliveries are unchanged. General obstacle navigation,
survival state, persistence, long-run cost and the earlier baseline legacy-suite
failures remain open in [the character contract](../../../addons/characters/README.md)
and [foundation status register](../../WORLD_FOUNDATION_STATUS.md).

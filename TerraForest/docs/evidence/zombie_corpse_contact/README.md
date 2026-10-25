# Zombie corpse contact repair

Scope: intact dead zombies vibrating or violently stretching during player contact
or interaction. Health, severing thresholds and world saves are unchanged.

## Faults and changes

- The player queried living-zombie collision but not ragdolls, while ragdolls still
  collided with the player. Player/corpse contact is now reciprocal, including
  restored corpses when living encounters are disabled.
- Rest previously deleted all anatomical joints, forced bodies back to sleep on
  every tick and recreated joints on explicit wake. Native rest now preserves
  joint frames and limits, detects physical impulses/moving contacts and wakes the
  connected body together. Verified supported rest temporarily parks gravity and
  CCD, restoring their original settings on wake or support loss. Active CCD remains enabled.
- Native stair assistance must not teleport a capsule onto or across articulated
  limbs. Existing contacts and up to four swept contacts reject corpse stair
  assistance; normal collision remains active. Limbs are not moving platforms.
- Six-axis angular recovery changes from 0.5 to 0.15 for intact and severed chains.
  Translation remains locked with its original 0.5 recovery. Motors and springs
  remain disabled after death.
- The bounded 10 Hz settle check also recognizes supported, stationary poses
  (all bodies within 1.5 cm and approximately 0.1 radians of their reference for
  0.9 seconds), followed by the existing 0.9-second quiet interval. Moving external
  contact rejects this path. This distinguishes small solver chatter from real
  travel without an unconditional corpse timeout, deleted joints or velocity caps.
- Loot pause captures velocities from the physics server, not potentially stale
  PhysicalBone scene properties, before changing body mode.
- Ragdoll bodies use `DISABLE_MODE_KEEP_ACTIVE`: disabling the zombie subtree no
  longer removes/reinserts its physics bodies while the loot/readiness adapter
  already freezes them explicitly. Pausing preserves the connected physics space
  and original joint anchors. This applies to detached segments too.
- Restored corpses now apply their saved pose to the skeleton before death-pose
  capture and native collision fitting. Previously only the script pose changed:
  native picking/collision still used the standing pose, offsetting collision from
  the rendered corpse and letting the body sink. Unsaved intermediate/finger bones
  retain their relative pose; missing limbs remain missing. This is bounded,
  one-time residency work, not another per-frame skeleton pass or save migration.

## Reproducer and retained failures

`tests/zombie_ragdoll_reactivation.gd` uses the production rig, native player
movement, real capsule dimensions, repeated walking/landing, external impulses,
explicit wake cycles and joint-anchor measurements. `--forest` uses a temporary
generated world, its actual player and loot-freeze adapter. `--pose=Zombie_Attack_Both`
tests a different death pose. `--one-way-contact` reproduces the old player mask.

The original packaged runtime, native hash `92a853f2b0b1614d4731b60ca0232eb0aecd5fdce4954f0de966f7b71353d0dc`,
failed joint retention and physical response. A standing capsule overlapping its
unconnected sleeping corpse produced enormous solver velocities; scene transforms
were still being forced back to rest. This is not evidence of anatomical severing.
The unchanged old package is tested through an external driver, not by replacing
the working DLL or altering a player's save.

Early diagnostic trials also teleported the fixture capsule without clearing its
contacts, creating unrealistic kinematic impulses. The final fixture disables its
collision for two ticks when relocating between trials; ordinary tested contact
remains enabled throughout each walk and landing. Those early failures are not
accepted gameplay reproductions. Disabling active CCD was investigated and rejected;
it is not the shipped solution.

Keeping joints alone did not solve contact instability. Reducing linear recovery
to 0.2 produced excessive hand-anchor stretch and was rejected. The first complete
forest run retained bounded movement but failed final rest after a shin impulse;
its low-motion settling failure remains in the diagnostic history rather than
being replaced by a flat-floor pass.

The first loot-resume trial passed a loose 25 cm joint-anchor limit but retained
approximately 24 cm of anchor drift. It was rejected on inspection. The final
fixture uses an 8 cm limit and measures about 5 mm in the forest interaction run;
physics-space retention fixes the drift rather than accepting the looser limit.

The original lifecycle test passed 18 build / 6 reopen checks, but its screenshot
showed no corpse. Those checks verified bytes/residency, not visible physics.
The strengthened read-only reopen probe found the torso roughly 1.09 m below
terrain and no selectable corpse. Applying a coherent saved skeleton pose before
fitting restores visible, targetable support. New lifecycle gates also require
all fifteen bodies to settle and an external push to move the restored corpse
without stretching/exploding before settling again. The failing probe is retained.

Two early graphical packaged combat runs failed 6 and 11 animated-hit assertions
while their corpse-rest checks passed. They lacked cancellation diagnostics, so
their cause is not assigned. Swing cancellation/focus/readiness diagnostics were
added; the subsequent graphical 41-check run passed without a combat balance
change. A headless attempt is invalid for this captured-input/animation fixture;
the test now explicitly rejects that mode. Expanded 43-check runs additionally
restore a severed corpse in the real world and require twelve remaining bodies
to settle without resurrecting removed fragments. Earlier failures are not erased
by later passes; recurrent animated-hit failures require a separate traced repro.

## Verification

Hardware: Godot 4.7.2 / GodotPhysics, RTX 4050 Laptop GPU, generated seed 1703,
1080p60 graphical checks. Test worlds are temporary or unique owned
`gather_lifecycle_*` slots. Player saves are not altered.

Source verification:
- Forest contact/landing/loot-resume/explicit and physical wake cycles: all pass,
  all 15 bodies return to sleep and all 14 joints remain; maximum anchor error
  5.082 mm (`source_forest*`). The final packaged driver also checks registration
  remains in the same physics space through pause.
- Alternate attacking death pose passes (`attack_result.json`); anatomical,
  severing, airborne and support-removal suite: 39/39 (`regions_result.json`).
- Native anatomy: 50 checks in release (`anatomy_release.log`); debug/release
  native builds succeed. Release ladder: 19/19 (`ladder_release.log`), plus
  source cottage stairs and zombie stair-guard checks pass.
- Expanded graphical world combat: 43/43; intact corpse lifecycle: 18 build /
  9 reopen checks, including actual loot interaction and fresh-process push/rest.
- The earlier source world-combat suite printed 41/41 but its runner expected an
  obsolete 38-check marker. That runner failure is retained as recorded, not
  relabeled a successful launch (`combat_world_source_run.json`).

Final packaged verification:
- Contact test: 15 phases, zero failures, 14 joints retained and 15 bodies asleep
  at completion; peak linear speed 0.916 m/s, angular speed 6.427 rad/s, joint-anchor
  error 5.409 mm (`pack_contact_*`).
- Expanded graphical world combat: 43/43 (`pack_combat_*`).
- Actual loot/save/fresh-process reopen: 18/18 and 9/9, including restored-body
  targeting, settling and physical push (`lifecycle_pack_*`).
- Export/startup passes. All four changed debug/release DLLs are byte-identical
  between source and package (`package_hashes.json`). No game process is left
  running by these completed checks.

Screenshot inspection
checks connected anatomy and the restored corpse being above terrain, not a new
character-art approval. The held tool partly obscures the body in these captures.
`corpse_restored.png` is the inspected final packaged reopen capture.

Visual/player acceptance is separate from engineering tests. No claim covers
every terrain configuration, extreme vehicle impacts, multi-hour endurance or
other hardware. Wider corpse-pile/varied-terrain qualification remains open.

Reproduce from the project directory:

```powershell
python tools/run_godot_check.py zombie_ragdoll_reactivation --timeout 180 --require "ZOMBIE_RAGDOLL_REACTIVATION failures=0" -- --forest --gameplay-construction --no-zombies --reactivation-evidence=res://reports/zombie_corpse_contact
python tools/run_godot_check.py zombie_combat_world --timeout 150 --require "ZOMBIE_COMBAT_WORLD checks=43 failures=0" -- --gameplay-construction
python tools/check_gathering_lifecycle.py --pack
```

Use `--headless` without `--forest` only for the isolated reactivation fixture,
not the world combat or lifecycle tests. Each retained manifest lists its exact
command, test/native hashes and pre-commit worktree provenance.

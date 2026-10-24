# Weighted zombie limp, revision 2 — 2026-10-24

The user rejected the first dragging walk as stiff and floaty. This revision
rebuilds `Zombie_Walk_Drag_Right` in Blender on the original R4 rig.
It keeps the two-second loop and 0.45 m/s reference speed while adding:

- A 68% left stance with heel loading, flat support, toe roll and a lifted return.
- A delayed right-toe scrape followed by weak-leg support during the left return.
- About 10.2 cm of lateral pelvis transfer and 6.3 cm of uneven compression,
  plus a small fore/aft lurch. The legs solve to the boot contacts separately.
- A hunch distributed through the spine, chest counter-rotation, delayed head
  response and uneven hanging arms with soft elbows and lagging wrists.
- Recovery curves whose endpoint velocities match the adjacent support motion.

Runtime playback now follows the previous physics tick's measured horizontal
body displacement. Collision-stopped bodies hold the gait instead of marching
against a wall; clearing the collision resumes matched travel. The existing
native route/body integration remains the only movement owner.

The original R4 GLB is unchanged, SHA-256
`6b6021c6ab97191c5a438807998845cf05a645ba693798060b73c5d963d58fbf`.
All 15 original clips remain beside the revised library, with 177 bone tracks
and seven neutral morph resets. All 59 rest transforms still match within
0.000000148. Root translation, attacks, injuries, navigation permissions and
world persistence retain their existing contracts.

## Verification

`gait/` passes **24 checks** on the real encounter/controller rig. Fixed identities
of sole vertices within the lowest 3 mm hold their world position through the
measured flat support intervals: maximum drift is **0.0047 mm left** and
**0.0018 mm right**. These are deterministic sampled flat-floor skin results.
The right boot stays **2.0–3.5 mm** above the floor; the left foot lifts to
**97.0 mm**. At least one boot remains near contact throughout the cycle.
Maximum first/last bone-pose difference is 0.000000170. The suite also covers
real native pursuit, suspension, attack transition, severed-leg crawling and
collision stop/hold/resume behavior. `result.json` retains detailed samples.

`encounters/` passes all **17** existing encounter checks. `world_combat/` passes
all **nine** rendered actual-world combat/menu checks with `--zombies
--gameplay-construction`. `slopes/` passes both existing cases: standing arrival
and contact on a 32-degree slope, rejection of a 46-degree route. This verifies
movement compatibility, not foot placement on the slope. Python compilation and
`git diff --check` also pass. No native library rebuild was required.

`initial_contact_check_failure/` retains the first two test failures: the
initial new assertion treated every boot vertex, including the deforming shin
cuff, as a rigid planted surface. The final assertion measures fixed sole-contact
vertex identities instead, retaining the 2 mm drift threshold. The first run
already passed all 16 original gait checks. `initial_world_launch_failure/`
retains the actual-world launch without encounter/gameplay flags; that disabled
encounters and failed collision/admission checks. The explicitly enabled rerun
passes. Neither failed run is used as passing evidence.

## Visual review and limits

`Zombie.weighted_limp.mp4` is a twelve-second studio preview: two normal-speed
cycles from a three-quarter view, two from the side, then one side cycle at half
speed. Its 360 Godot frames are encoded at 30 FPS. Translation is studio-only,
matched to the authored reference speed; this is not autonomous physics or a
frame-rate measurement. Representative three-quarter, weak-load, recovery and
side poses, Blender side/three-quarter images, and the actual-world attack image
were inspected. The current source is
`../../../addons/characters/authoring/Zombie.drag_walk.blend`; rebuild steps are
in its adjacent README. `asset_hashes.json` identifies the delivered assets.

**User visual acceptance remains open.** Review the normal-speed and half-speed
preview for remaining stiffness or floating; revise the same gait if rejected.
Terrain/stair foot IK remains deferred: this clip uses a flat-floor contact
model, so uneven ground still requires per-foot surface sampling and compatible
leg adjustment. Return to that work when adapting locomotion to actual terrain;
close it with inspected moving slope/stair evidence and contact measurements.
Larger populations, navigation latency and broader terrain/world-quality gates
remain tracked in `../../WORLD_FOUNDATION_STATUS.md`. The previous saved-tower
journey was not repeated for this presentation revision.

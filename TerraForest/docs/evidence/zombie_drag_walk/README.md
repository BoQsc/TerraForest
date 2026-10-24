# Slow limping zombie walk — 2026-10-23

Historical revision 1 evidence. On 2026-10-24 the user rejected this gait as stiff
and floaty. The [weighted revision 2](../zombie_weighted_limp/README.md) supersedes
its animation and playback presentation. The measurements and journeys below
describe the original revision, not acceptance of the revised visual result.

`Zombie_Walk_Drag_Right` is authored in Steam Blender 5.2.3 LTS on the unchanged
R4 skeleton. The left leg carries weight and takes a lifted recovery step; the
right leg trails with its heel raised and toe scraping forward. A small uneven
hip drop and restrained arm/head sway support the limp. The clip is a continuous
two-second loop, frames 0–120 at 60 FPS, in place.

Runtime standing pursuit selects it by default at **0.45 m/s** (previous default
0.72 m/s). Playback scales with actual requested walking speed, including the
existing damage multiplier. This is a deliberate slower gait, not an AI search
or movement-collision rewrite. `dragging_walk=false` selects the preserved
original walk and its 0.72-m/s reference calibration. Crawling, attacks and
limb-loss rules retain their own animations and timing.

The original R4 GLB remains byte-identical, SHA-256
`6b6021c6ab97191c5a438807998845cf05a645ba693798060b73c5d963d58fbf`.
Its 15 clips are retained beside the new compact AnimationLibrary. All 59 rest
transforms match within 0.000000148. The library retains 177 bone tracks plus
seven neutral morph resets from the original walk, so attack mouth/clothing/knee
shapes do not remain on the locomotion pose. It has no method/audio/gameplay
tracks or animated root translation. Editable source and rebuild commands are
in `../../../addons/characters/authoring/Zombie.drag_walk.README.md`.

## Functional evidence

- `gait/`: **16 checks pass** using the real encounter controller and shared native
  navigator/motor. Tests cover the original actions, slow-speed calibration,
  all-bone loop seam, unchanged root, evaluated boot surfaces, planted support
  stance, native pursuit, suspension, attack contact and crawling after right-shin
  severing. The existing native work maximum remains 48 in this observation.
- Evaluated right boot's lowest surface stays at **3.0–4.5 mm** above the flat
  floor. The left foot rises to **118 mm** and returns to about 3 mm. During the
  measured support stance, world foot drift at 0.45 m/s is about **0.97 mm**.
  Maximum first/last bone-pose difference is below 0.000000134. This is sampled
  flat-floor geometry, not terrain foot IK or universal contact accuracy.
- `encounters/`: all 17 existing crowd/windup/crawl checks pass.
- `slopes/`: the existing standing 32-degree arrival/attack case and rejected
  46-degree route both pass with the slow gait.
- `character_runtime/`: the existing rig/equipment/combat/lifecycle check passes.
- `doors/`: all 14 actual-host wooden-door interaction checks pass.
- `world_combat/`: all nine actual running-world attack and menu suspend/resume
  checks pass. The retained attack image was inspected.
- Scoped character packaging passes, including the new resource. Blender tools
  pass Python syntax checks. No native library rebuild is needed for this change.

After merging terrain paging checkpoint `9b451125` with animation checkpoint
`92ac6795`, the 16 gait checks and nine rendered actual-world combat checks pass
again. `combined_gait/` and `combined_world_combat/` retain those fresh runs,
including native DLL hashes. This confirms the selected controller and host
integration with the new terrain library; it does not repeat or expand the
saved-tower traversal or qualify the terrain checkpoint's open performance work.

## Actual generated-world traversal

`tower/` passes all 13 existing saved-world journey checks at the new 0.45-m/s
default. The zombie autonomously breaks the real generated door, climbs to the
second upper floor, attacks the player, and returns outside. All **210** canonical
and sidecar files retain their hashes. Intact-door clearance stays above 0.88 m.

The reachability fixture's bounded travel allowance scales from its previous
150 seconds at 0.72 m/s to 240 seconds at 0.45 m/s. This accounts for deliberately
slower physical travel; planning work/domain limits and movement ownership are
unchanged. Actual outbound contact occurs at 159.9 seconds; return contact at
132.5 seconds. The new gait does not add reachability or traversal permissions.

Cold navigation remains unfinished: the first complete outbound/return paths in
this uncontrolled diagnostic run take 20.3/40.2 seconds, with a 19.8 ms cooperative
planning overrun. Other authoring/world work was active during this run. These
are retained observations, not a controlled regression/performance comparison;
no latency or frame-cost improvement is claimed. The existing navigation
performance, broader seeds/mine/domain pressure and world-quality gates remain
open in `../../WORLD_FOUNDATION_STATUS.md` and `../../REGIONAL_NAVIGATION.md`.

## Visual review

The Blender three-quarter/side images and Godot three-quarter, recovery and side
poses were inspected. `Zombie.drag_walk.mp4` is an eight-second preview of four
cycles, with studio-only translation at 0.45 m/s over a marked flat floor.
Blender encodes 240 deterministic Godot frames at 30 FPS. This is animation review,
not a capture of autonomous physics or sustained runtime FPS. Live movement is
verified separately by the gait and actual-world checks above.

Terrain foot planting, stair-specific foot adjustment, large populations and
broader anatomy/terrain visual acceptance remain unqualified. The standing
capsule and existing supported-step/slope permissions remain authoritative.

`initial_test_parse_failure/` retains the first test-script type-inference error.
The test explicitly declares its skeleton bone index, and subsequent checks pass.

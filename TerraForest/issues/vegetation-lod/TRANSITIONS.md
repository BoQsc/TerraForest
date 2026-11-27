<!-- SPDX-License-Identifier: CC0-1.0 -->
# Distant stone pop-ins and subtle transitions — 2026-11-28

Status: causal, full-frame and physical gameplay checks pass. On 2026-11-28,
after the source playtest, the user requested committing and pushing this result
for now. Accepted as the stone/distance-fade checkpoint, not universal visual
closure. Near-to-next-LOD transitions and distracting rectangular vegetation
patches remain a separate investigation. Tag: `playtest/stone-transitions-2026-11-28`.
Shared native DLLs remain excluded; restoring this source requires a native rebuild.

## Reproduction and causal separation

The user sees small stones pop in farther away while approaching. The resident
lab holds 16 stones, terrain, lighting and population fixed and moves a 1080p
camera toward them. It records lossless raw-hash-verified field strips, plus a
no-cover background at every pose. The field strip is a diagnostic for these
stones, not full-frame or normal-gameplay qualification.

`20261127T212603559729Z` compares native surface optimization on/off, distance
fade on/off, fixed low geometry, fixed far geometry, historical opaque geometry
and tagged surfaces over 140–16 m. Disabling native surface optimization produces
identical pixels at all 63 poses. Disabling distance fade changes only the outer
visibility band; the opaque/proxy transition remains. The exact baseline repeats
after all interventions, with unchanged resident page count. Streaming and spawn
are absent, so they are not necessary to reproduce this fault.

`20261127T213627904715Z` refines the switch to 0.1 m steps. Between 32.4 and
32.3 m, the old rendering's summed stone/background RGB contrast rises from
24,402 to 119,251 (4.887×). With both corrections below it rises from 116,771 to
119,251 (1.021×); the fixed opaque control rises 1.015× over the same movement.
The remaining contrast step beyond ordinary approach is approximately 0.65%.
These are fixture measurements, not a universal no-pop claim.

## Two concrete faults

1. **Lost individual instance transform in the fragment stage.** The original
   proxy projected each stone correctly in `vertex()`, but reconstructed depth,
   light position, normals and tangents using fragment-stage `MODEL_MATRIX` and
   `MODEL_NORMAL_MATRIX`. In the inspected Forward+ renderer, those fragment
   matrices describe the draw batch; the individual MultiMesh transform is added
   in the vertex stage. Stones were therefore tested against terrain at the wrong
   depth. Many remained partly hidden until the opaque LOD appeared.
2. **Rear hemisphere selected by projection orientation.** The cross product of
   projected axes depends on projection Y orientation. Once instance transforms
   were corrected, selecting the rear hemisphere still made the proxy too dark.
   Selecting the camera-facing hemisphere brings its contrast close to the
   authored opaque stone without tinting or changing lighting.

Depth-only, full-transform and hemisphere-only controls distinguish these effects
in `20261127T212907779782Z`, `20261127T213355455733Z` and the final refined run.
Hemisphere-only correction does not resolve the incorrect terrain clipping.
Removing depth reconstruction exposes the missing stones, but loses correct
terrain intersection and was not selected as a production fix.

The independently inspected engine source supports the stage distinction:
[vertex instance transform](https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl)
and the same file's `fragment_shader` reconstruction of `read_model_matrix`.
The moving counterfactuals establish the behavior on this project's actual
Godot 4.7.2 runtime; the linked development source is supporting context, not a
claim that an unpinned upstream file is identical to the installed executable.

## Correction and fade scope

The far stone shader carries its instance basis from the vertex stage and uses
the already-transformed fragment `VERTEX` as the instance centre. It explicitly
selects the front hemisphere. Moving the screen centre out of the varying list
keeps the shader below the device's varying limit. The nearby opaque stone and
vegetation shaders, meshes, textures, lighting and colour parameters are retained.

The outer coverage fade is being tested over 32 m instead of 24 m, with the same
124 m visibility endpoint at ordinary FOV. Far grass now reads the same fade
uniforms as other species instead of hardcoding 100/124 m. The fade reveals the
existing terrain gradually; it does not brighten plant colours. No extra mesh
pass, texture, temporal history, native build or per-instance CPU update is added.
The LOD pop is addressed by correcting the representations, not by introducing
another transparent mesh over nearby vegetation. There is no alpha crossfade
between every opaque LOD: the corrected proxy makes that handoff match, and the
outer distance fade becomes broader. Zoomed grass now follows the coordinator's
fade range, as the other species already did; zoomed cost still needs qualification.

## Independent and integrated checks

`20261127T215435218852Z` compares the corrected single MultiMesh draw with 16
separate transformed MeshInstances using the previous shader plus only the
front-hemisphere correction. All nine tested poses agree within one RGB byte in
any channel; summed absolute error is at most three byte units across each field
strip, with zero pixels differing by more than eight. Thus the instance correction
is checked against independently submitted transforms, not just its own formula.
The fixture varies yaw and uniform scale; arbitrary nonuniform/sheared parents are
not covered by this identity test.

`20261127T215018587021Z` passes 208 full-frame checks with 195 raw 1080p frames:
old source, corrected stone, corrected stone plus broader fade, no-cover controls,
exact baseline repeat and a near-field comparison. The 1920×580 near scene region
is byte-identical. Mean frame brightness changes +0.0021% at ground level and
+0.0185% elevated. Geometry, population, removals, draw/shadow page counts,
transform bytes and the canonical save hash are unchanged. The lossless elevated
context was inspected; review movies are compressed illustrations, not metric inputs.

Three uncapped ABBA GPU groups run after image readback/encoding finishes. New
minus old median differences are −0.1605, −0.0980 and +0.2275 ms; p95 differences
are −0.292, −0.087 and −0.035 ms. No other engine process was observed in the
five-second inventory samples. These are local source-scene measurements on the
RTX 4050 laptop, not OS-wide GPU exclusivity or a universal cost guarantee. The
scene freezes 309 forest cells / 2,438 trees, so this cannot substitute for full
normal-world gameplay cost. The earlier detail-versus-grass/fern tail target stays
open. Peak private commit warning is 4.01 GiB, below the 6 GiB test limit.

## Normal moving gameplay

Final source run `20261127T221540936288Z` passes: 220.169 m of physical walking,
turning and strafing, all 2,162 physics ticks grounded, all 1,024 forest cells /
8,461 trees, normal streaming and live actors. No loading cover, death/respawn or
entry sequence occurs during measurement. Four frustum-visible stone batches
cross the predicted engine proxy/opaque threshold within the captured frames
(indices 121, 126, 156 and 176). This threshold witness plus the lab establishes
that the approach exercises the corrected handoff; it is not a universal
occlusion/streaming-pop detector.

Preparation uses one normal teleport/floor-snap to an outdoor test departure at
(1740, 0, 1700), settles with the ordinary pause menu and selects a clear heading
away from resident enemies. The menu is closed for movement. Health, combat,
collision, actor behavior and world streaming are not overridden. The only
measurement adaptations are scripted W/D/yaw and offscreen input admission;
player position is not replayed or overwritten during measurement.

All 192 consecutive full 1080p raw frame hashes independently agree, and all
source/canonical-save hashes remain unchanged. Capture spans 4.05 s, with 19 ms
median / 37 ms p95 readback cadence; the 60 fps review movie plays those frames
in 3.2 s. Therefore its playback speed and capture FPS are not gameplay performance
claims. The lossless context, sampled motion and last captured frame were inspected.
Readback-free gameplay GPU observations are 5.263 ms median / 6.262 ms p95;
these are unpaired observations. No other engine job was observed. The bounded
test-only image buffer raises private commit to a 5.42 GiB warning, below 6 GiB.

[Physical approach movie](../../reports/checks/20261127T221540936288Z/gameplay.mp4) ·
[Lossless context](../../reports/checks/20261127T221540936288Z/walking.png) ·
[Sampled motion review](../../reports/checks/20261127T221540936288Z/motion-review.png) ·
[Machine-readable evidence and exact runtime hashes](transition-evidence.json).

The successful full-frame comparison and final gameplay run were pinned
`RETAIN_READY` for human review. Following the checkpoint approval, they may
return to verified cold retention; hashes and evidence summaries remain here. Earlier unsuccessful runs remain recorded.
The original near/opaque shared shader still has SHA-256
`a16616cfd6d2f15d73f8b894f9191047d9f85f0259aa754be2aa73ea839fbae1`.

## Retained unsuccessful test attempts

- `20261127T212054966090Z`: unavailable ArrayMesh inspection method in the new
  fixture; stopped before comparison and replaced with the known proxy indices.
- `20261127T212300471313Z`, `20261127T212432187491Z`: motion packet cap reached;
  rejected. The coarse distance sweep was reduced before the refined sweep.
- `20261127T213142083769Z`: an over-wide test varying layout exceeded the device
  limit and shader failure crashed the engine. The selected compact layout passes
  the later rendered lab.
- `20261127T214337002006Z`: frozen-time uniform appeared after a helper using it;
  test-only shader compilation failure/crash. Declaration order corrected before
  integrated validation. No successful comparison is claimed for this run.
- `20261127T214627117571Z`: final encoder flush exceeded the unchanged media cap.
  Rejected; the successful replay stores two review movies at CRF22, flushes at
  each case boundary and uses 9.9 MiB of media. No storage allowance was raised.
- `20261127T215537784134Z`: a physical approach captured a respawn/loading cover,
  travelled only 23 m and exercised no witnessed transition. Rejected despite
  raw frame hashes agreeing; hashes alone cannot establish correct test content.
- `20261127T220521967827Z`: added life/readiness logging catches the player being
  killed while stationary in preparation, then respawning. It stops before
  allocating capture frames. The next harness settles with the ordinary pause
  menu and releases it for measurement, leaving health, combat and actors intact.
- `20261127T220816122408Z`: physical movement assertions pass (220.265 m, all
  2,163 physics ticks grounded, no loading/respawn interruption and four LOD
  crossings inside the 192-frame capture), but the dense-grass review movie plus
  context exceeds the 16 MiB media cap by about 0.4 MiB. The overall run remains
  failed. All 192 independent raw hashes agree. The next encoder adds a 16 Mbit/s
  review-only ceiling; no render setting or raw measurement is changed.
- `20261127T221304109221Z`: admission rejects the replay before engine launch.
  The older failed `214627` capture is checksum-verified into cold retention,
  reclaiming 26,235,129 bytes with one ordinary ready full-frame run retained.
  Saves, evidence and repository storage limits remain intact.

All run folders remain under the existing receipt-owned retention lifecycle.
Cold retention is preserved evidence, not missing evidence. No budgets are raised.

## Remaining acceptance

- Near-to-next-LOD handoff and distracting rectangular patches: compare native
  batch-wide switching against gradual per-plant transitions before promotion.
  Preserve the fully detailed nearby endpoint and measure tone, motion and cost.
- Broader FOV, terrain, object overlap and devices; previous detail GPU-tail target.

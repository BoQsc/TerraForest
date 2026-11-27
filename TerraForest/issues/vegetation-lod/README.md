# Extended vegetation LOD

- Status: Open / far-grass coverage experiment implemented in source. Nearby pixel parity, save integrity and resource ceilings pass; the prior 0.3 ms GPU-tail cost criterion fails. Other vegetation, broader travel and user visual acceptance remain open. The rejected brightening stays removed.
- Updated: 2026-11-27. Original LOD implementation `e2d0e548`; follow-ups below.
- Forests: existing 6592/192/12-triangle tiers retained; visibility 448 -> 576 m.
- Native circular preload: 640 m, maximum 405 wanted owners, 441 admission cap;
  two jobs and one 36-candidate batch/frame unchanged. No density/identity changes.
- Ferns: distant 392 -> 154 triangles; bushes 294 -> 154; twigs 136 -> 80.
  Nearby geometry, ordinary shadows and four grass tiers remain unchanged.

## Filtered far-grass coverage — 2026-11-27

The user confirmed that the screenshots came from the source project. Earlier
shading changes and aggregate measurements were insufficient: they did not isolate
pixel coverage, and their viewpoints did not reproduce the supplied scene. The
new test retains the currently saved camera (`b8f04e1d07b4...`, eye
`1772.481, 68.63347, 1684.51`). This save has moved since the supplied screenshot;
it is not an attribution of every circled pixel or the editor's full residency.

**White points were traced separately.** In an inspected hillside tile, 118 pixels
were brighter than 0.48 display luminance and 0.10 above their 5x5 local median.
Removing specular or backlight removed **zero** candidates by the diagnostic's
0.05-luminance criterion. Removing grass removed 80, small stones 26, and white
flowers five; these one-at-a-time counts can overlap. Removing the grass texture
removed only five and increased average candidate brightness. This rules out
shininess as the main explanation in this tile; it does not identify every point
in the original screenshot. Coupled with the isolated silhouette test below,
unresolved lit/shaded blade coverage is a confirmed major contributor.

![White-point baseline](images/white-points-baseline.png)
![Specular removed: points persist](images/white-points-no-specular.png)
![Grass removed for attribution only](images/white-points-no-grass.png)
Unscaled, lossless crops of the same tile. Removing grass is diagnostic only.

**The source experiment filters coverage instead of raising grass lighting.**
`filtered_grass.gd` builds a second, far-only surface at startup. Each far triangle
becomes a projected Gaussian coverage approximation using its area, centroid and
covariance. A half-pixel reconstruction footprint suppresses subpixel on/off
changes; fractional alpha blends over the actual shaded terrain behind it. This
is an approximation, not exact integration of triangle occlusion or terrain light.
Original blade normals/colors and conservative leaf shading remain; no upward
normal/full-AO brightness substitution, new atlas, temporal history or per-instance
CPU loop is introduced. Birth and outer-distance coverage fade continuously.

The original near/low surface and original nearby shadow casters remain. Far
LOD error thresholds change from 0.12/0.20 to 0.06/0.10; keeping the old thresholds
missed much of the visibly distant 72-triangle tier. An earlier-LOD-only control
separates that effect from filtering. This applies to ground-cover grass only;
other vegetation, small stones, palette previews, density and world identity stay
unchanged. No native build or export was made. Global antialiasing stays at 2x MSAA.

![Baseline field](images/filter-before.png)
![Filtered far grass](images/filter-after.png)
Matched source camera, lighting, time and population. These inspected images show
softer distant clumps without the rejected broad bright band. They are not user
approval. [Normal source startup](images/filter-source.png) also exercises the
production surface and uniform setup; its paused startup HUD is not an FPS result.

![Sideways motion: baseline above, filtered below](images/filter-motion.webp)
1.6 m continuous sideways camera travel, captured at 30 fps; unscaled 256x96
portions of retained 640x160 frames. The [forward/turn comparison](images/filter-route.webp)
covers 25.5 m with an 11.5-degree turn, sampled every eighth rendered frame at
60 Hz. Actors and streaming are paused for matched rendering; this is not physical
car handling, normal streaming or an endurance qualification. Selected frames
across both replays and the source context were visually inspected.

| Sideways crop measurement | Baseline | Earlier opaque LOD | Filtered far grass |
| --- | ---: | ---: | ---: |
| Mean display luminance | 0.400994 | 0.401904 | 0.402670 |
| Bright local-contrast pixels / frame | 355.6 | 154.8 | 73.7 |
| Dark local-contrast pixels / frame | 2668.9 | 1961.3 | 617.9 |
| Best horizontal-alignment residual | 0.023403 | 0.018253 | 0.012093 |

The filtered crop has 79.3% fewer bright and 76.8% fewer dark high-contrast pixels,
with +0.42% mean luminance. These are descriptive crop statistics, **not a
percentage of all gameplay flicker**. They include other plants/stones, real motion,
occlusion and contrast. The near view, including lighting, is byte-identical.
All 77,660 cover instances, removal state, native pages/transform allocations and
the canonical save hash are preserved.

**Cost remains an open requirement.** The final interleaved 1080p/RTX 4050 Laptop
replay excludes image readback/analysis from timing:

| Cost | Baseline | Filtered |
| --- | ---: | ---: |
| GPU median | 12.865 ms | 12.975 ms |
| GPU p95 | 14.149 ms | 14.873 ms |
| CPU render median | 3.069 ms | 3.208 ms |
| Draw calls | 2176 | 2326 |

Peak process RAM was 3.80 GiB and dedicated GPU allocation 1.64 GiB, within the
existing limits. The extra surface adds 150 draws here; earlier LODs reduce geometry.
The +0.724 ms pooled GPU-tail increase **fails the previous 0.3 ms criterion**.
Paired tail increments were +0.260/+0.520/+1.325 ms. A passing runner means
fixture/source/save/resource checks passed, not that the cost target passed.
Do not advertise this as free, universally stable, or fully qualified performance.

The TAA control also softened the image, but was global, visibly blurred motion,
and its run exceeded the RAM ceiling (6.10 GiB). It is not enabled. A combined
single-surface/alpha-prepass trial failed full near-image parity, retained the
extra draw count and worsened timings; it is not used. Invalid custom-attribute,
LOD-buffer and shader prototypes, plus the first source integration's missing
shadow-surface entry, are retained as failed evidence. The corrected normal-source
run `20261127T121058080923Z` passes 31 fixture assertions with no engine errors.
See [inputs, measurements, failed runs and source identities](filter-evidence.json).
The historical cause-loader regression `20261127T122513602769Z` also passes
30 assertions after explicitly restoring its opaque baseline; the new far wind
shader cannot silently contaminate those older paired controls.

Remaining: qualify the GPU/frame tails, normal gameplay/streaming, close-to-far
transitions at other FOVs/resolutions, terrain/light variation and weaker hardware;
trace residual other-species/stone artifacts without hiding density. Return to
per-page submission/pass costs if retaining this representation; the global
alpha-prepass experiment did not remove them. Player review is pending. Earlier
rejected comparisons below remain historical evidence, not accepted fixes.

Reproduce the source comparison read-only:

```powershell
python tools/run_godot_check.py vegetation_reconstruction --isolated-render --timeout 300 --require "VEGETATION_RECONSTRUCTION failures=0" -- --stability-source-slot=Homestead_Valley --early
python tools/analyze_vegetation_reconstruction.py reports/checks/<owned-run>
```

`--attribution-only` isolates white-point sources. `--shader-only --early` checks
the production coverage shader; `--single` preserves the rejected alternative for
diagnosis. The TAA control is selected without those mode flags. All outputs use
the admitted/receipt-owned lifecycle; no player world is copied or written.

## Far-LOD cause isolation — 2026-11-27

Clarified user direction: the softer/different distant-LOD appearance was liked.
The excessive brightness, failure to match surrounding terrain, and persistent
pixel flicker were the problems. Preserve that useful far-representation direction;
this is not a request to redesign nearby grass or change the whole grass system.
The rejected implementation remains removed, not the design objective.

**Confirmed contributor: subpixel silhouette coverage.** The new
`tests/vegetation_causes.gd` places 64 isolated production grass meshes at 90 m,
with fixed rotations and fixed LODs. It renders white masks on black, removing
wind, texture, lighting, shadows, terrain, dither and streaming. The camera samples
16 quarter-pixel offsets. Stationary captures are byte-identical. Summed linearized
pixel coverage should be constant under these translations, but the current 2x
MSAA produces large changes:

| Fixed mesh | Triangles | Median covered pixels | Median coverage range / mean |
| --- | --- | --- | --- |
| Full detail | 468 | 4.20 | 48.5% |
| First reduced tier | 72 | 2.64 | 88.1% |
| Far tier | 8 | 2.70 | 55.9% |
| Horizon tier | 3 | 3.01 | 48.8% |

These are per-plant coverage fluctuations over sample phases, not percentages of
all gameplay flicker. They establish that the silhouette alone can shimmer; an
LOD switch or animated wind is not necessary. The 8x MSAA diagnostic reduces the
72/8-triangle coverage ranges to 40.0%/32.9%, but does not eliminate them. It is
not proposed as a production setting. Adding triangles is not a reliable cure
when individual blades remain unresolved.

![Fixed eight-triangle masks, phase 0](images/causes-eight-mask-phase0.png)
![Same masks at a subpixel offset](images/causes-eight-mask-phase15.png)
Unscaled 160x160 probe crops, 90 m, 2x MSAA. No light/texture/fade changes.

**Actual visible LODs were checked, not inferred from hidden roots.** Temporary
fragment tags identify grass at true 60–124 m distance after depth testing. Four
view directions were inspected from an elevated diagnostic camera. The selected
view contains 7,108 tagged pixels from the 72-triangle tier and 3,025 from the
eight-triangle tier; no full-detail or three-triangle tags occur. Pixel counts
are not instance counts. Optimizing only the last/horizon tier would miss most
of this visible far grass. The current saved-world hash is `d4fb3582ec5c...`;
it is not the earlier coastal camera or a reconstruction of the user's screenshot.

![Visible far LOD identities](images/causes-visible-lods.png)
Yellow: 72-triangle tier; blue: eight triangles. Unlit colors and disabled fog/MSAA
are diagnostic tags, not proposed artwork. [Context](images/causes-world-context.jpg).

Matched 0.48 m sideways camera travel isolates individual features in the same
visible region. Wind is frozen in all these comparisons. The descriptive screen
difference includes expected image motion and contrast; it is not a pure shimmer
score or a quality/performance acceptance gate.

| Diagnostic override | Screen difference relative to baseline | Interpretation |
| --- | --- | --- |
| Grass hidden | 0.391 | Grass contributes much of this region's variation; remaining plants/terrain still contribute |
| Grass distance fade disabled | 1.013 | Does not remove the main effect here |
| Grass shadow reception disabled | 1.006 | Cast-shadow reception is not the main cause here |
| Grass texture disabled | 1.371 | Higher contrast worsens this measure; the existing texture is not the explanation here |
| Full-detail meshes forced | 1.337 | Extra geometry does not cure unresolved silhouettes |
| Flat unlit grass | 0.684 | Lower difference but wrong brightness; explicitly not a fix |
| Far LOD thresholds 0.08 / 0.14 | 0.882 | Useful LOD-only trend; visible speckling remains |
| Far LOD thresholds 0.06 / 0.10 | 0.833 | Useful LOD-only trend; visible speckling remains |

The threshold experiments preserve the original near/first-tier threshold 0.02,
all vertex arrays and the original lighting. Average crop luminance changes only
+0.20% / +0.17%, avoiding the previous broad brightening in this view. Their
[moderate](images/causes-world-far-lod-moderate.png) and
[earlier](images/causes-world-far-lod-early.png) captures were inspected. These
remain **test-only experiments**, not enabled runtime changes or user-approved
results. Continuous-play transition quality, nearby pixel parity at relevant
FOV/resolutions and isolated performance still need qualification before adoption.

**Brightness is a separate mismatch.** Woodland foliage uses leaf normals,
Burley lighting, ambient light and backlight. Terrain uses Lambert lighting,
ambient-disabled custom sky fill, surface normals and material textures. The
discarded upward-normal/full-AO/color-multiplier approximation reproduced none
of that terrain calibration. Native ground placement uses support normals to
reject steep slopes, but keeps upright instance bases; those bases do not encode
the terrain normal. A new far blend must account for actual terrain light/color
and slope, rather than merely choosing another global brightness multiplier.

Evidence: [compact measurements, inputs and identities](causes-evidence.json).
Runs `20261127T110001831123Z` (53 fixture assertions),
`20261127T110233221983Z` (nine low-tier assertions), and
`20261127T110629799826Z` (30 world/threshold assertions) all pass. Passing means
diagnostic integrity, not that flicker or visual acceptance is solved. All 88,725
ground-cover instances, native page/shadow/transform allocations and canonical
save hash remain unchanged within each world run. Production source is unchanged.

Reproduce using the existing save, read-only:

```powershell
python tools/run_godot_check.py vegetation_causes --isolated-render --timeout 300 --require "VEGETATION_CAUSES failures=0" -- --stability-source-slot=Homestead_Valley
```

`--probe-kind=low` restricts the silhouette probe; `--world-only` skips it.
The runner admits 12 MiB, with an enforced 8 MiB image ceiling and bounded
JSON/logs, zero new worlds/builds/exports. Receipt-owned retention archives older
members after exit, keeping two ordinary ready runs. The first full run is now
cold-retained; its manifest and versioned selected evidence remain available.
Original diagnostic code is 0BSD, original capture contributions CC0-1.0, with
underlying project-asset terms preserved. No external content or dependency added.

Next: improve far-LOD coverage/transition stability and terrain-calibrated contrast
together, preserving the liked softer distant appearance and near grass. Require
visible-surface motion evidence, brightness/terrain comparison and GPU/frame-tail
checks; do not substitute fewer plants or a lower aggregate metric for acceptance.
LOD-boundary popping, other species, exact supplied viewpoint, varied terrain/light,
zoom, physical travel and broader hardware remain unqualified.

## Moving distant-cover trial — 2026-11-27

**Rejected by the user:** the whole distant band becomes too bright relative to
its surroundings, and flicker remains strong. The measured residual improvement
did not represent acceptable visuals. Runtime `woodland.gdshader` and
`ground_cover.gd` have been restored exactly to `6e87ed07`, retaining the earlier
double-sided-normal correction. The following records the rejected experiment,
not the current runtime or an accepted partial fix. Its captures and failed cost
gates are preserved.

The brightness mismatch came from replacing original leaf normals/occlusion with
upward normals, full AO and a constant color multiplier. Terrain instead uses
its own ambient-disabled/custom-fill lighting model; an upward leaf normal does
not reproduce that terrain shading. Simply lowering the color multiplier again
does not solve silhouette coverage or establish a correct blend.

Wind isolation after rejection: `reports/checks/20261127T104035438622Z` compares
normal and frozen wind with identical original shading and camera movement.
Twenty fixture/preservation assertions pass, including byte-identical restored
near renders and unchanged canonical save. Noise/performance acceptance gates are
explicitly **not evaluated** in this diagnostic. In the controlled field, far
residual is 0.13703 with wind versus 0.13749 frozen (ratio 1.00335): removing wind
does not materially improve it. Six motion pairs were inspected. This supports
further silhouette/rasterization diagnosis, not a unique root-cause claim.

The saved world changed before this run (hash `d4fb3582ec5c...`, camera
`(1498.941, 67.46824, 905.6166)`, 88,725 ground-cover instances). Its inspected
camera faces rising terrain that obscures projected far roots, so its far-band
number is **unqualified**. Do not compare it with the prior coastal camera or
call it visible far-foliage evidence. A root's geometric distance alone does not
prove that it is the visible surface at its projected pixel. Add visibility/depth
qualification before using that metric for actual-world acceptance. The input
save hash is unchanged within the diagnostic; it is never rewritten or replaced.
[Diagnostic summary and identities](wind-isolation-evidence.json).

The initial diagnostic launch stopped before engine startup because another
receipt-owned archive writer held the lease. After it exited, the normal admitted
runner completed; no lease was bypassed or budget raised. The two newest ordinary
vegetation runs remain ready; earlier rejected captures are cold-retained.

Reproduce the diagnostic on current source:

```powershell
python tools/run_godot_check.py vegetation_stability --isolated-render --timeout 240 --require "VEGETATION_STABILITY failures=0" -- --stability-source-slot=Homestead_Valley --diagnose-wind
```

Frozen wind is a test-only override, not enabled in runtime. The subsequent
historical measurements describe the rejected lighting trial.

The rejected experiment used the following approach. At 1080p and 75-degree FOV,
woodland foliage gradually loses unresolved wind, fine shading and leaf-normal
contrast from 32 to 80 metres. The transition uses squared distance and scales
with projection size for zoom/resolution. Fully distant foliage uses a simple
ground-facing normal and a calibrated 0.65 color multiplier. This is a visual
approximation, not terrain-color sampling or translucency. Stones retain their
existing shader path. Existing coverage/dither fade remains unchanged.

Nearby grass retains its original geometry, shading and wind: the isolated near
render is byte-identical, and near-band motion measurements match exactly. There
are no new textures, geometry, draw passes or per-instance script loops. Existing
native pages, shadow pages, transform bytes, plant identities and densities remain
unchanged. Projection parameters update through the existing view-change path.
The removed trial exposed `distant_stability` for comparison.

Final source replay: `reports/checks/20261127T102434433909Z`, Godot 4.7.2
`ed1daf0bf`, Forward+, RTX 4050 Laptop, 1920x1080, 60 FPS cap. Baseline is the
shader after normal correction `6e87ed07`, frozen in
`tests/fixtures/woodland_pre_stability.gdshader`. Both shaders run the same
120-frame continuous camera path: 1.2 m/s sideways and 0.6 m/s forward, with
deterministic wind time, repeated in ABBA order. Measurements sample every frame;
lossless previews retain every fourth frame at 15 FPS. Timings exclude readback.

| Check | Synthetic field | Read-only Homestead Valley |
| --- | --- | --- |
| Far temporal residual, baseline → trial | 0.13703 → 0.08098 (40.9% lower) | 0.05365 → 0.03947 (26.4% lower) |
| Median of GPU p50 windows, baseline → trial | 5.532 → 5.605 ms | 6.952 → 6.977 ms |
| Worst paired GPU p95 increase; gate ≤0.3 ms | **+0.615 ms, failed** | **+0.397 ms, failed** |

**23 of 25 checks pass; both conservative GPU-tail gates fail.** Do not claim a
performance-qualified fix or zero GPU cost. Eight short ABBA timing groups retain
the adverse windows; no threshold was relaxed. Native instance buffers and draw
counts pass the synthetic check. The real world retains all 58,829 ground-cover
instances, page/shadow/transform allocations and persistent edits, and its
canonical save hash is unchanged. No world copy, save write, native rebuild or
installed-package export was performed.

The metric is display-luminance change at fixed anchors around actual grass
roots, using true 3D distance bands (near 8–28 m, middle 28–80 m, far 80–120 m),
320 anchors per band. It includes wind, silhouette coverage, lighting and possible
occlusion by nearer objects. It is not a pure aliasing measurement or a percentage
of all visible flicker. Actors/publication are frozen during the rendering replay;
the camera moves. This is not a physical driving or streaming/endurance test.

![Matched moving vegetation comparison](images/stability-world-motion.webp)
Left: pre-trial shader. Right: stability trial. Lossless 1:1 crops, matched camera
and wind time; no resizing/interpolation. The crop contains the densest tile of
projected distant-root anchors plus intervening nearer plants. Six evenly spaced
frame pairs and the full context stills were inspected. Distant dark speckles
soften, but clumps and color contrast remain; the transition is not seamless or
user-approved. [Before context](images/stability-world-before.jpg) and
[trial context](images/stability-world-after.jpg) are JPEG stills, not the metric
inputs. Frozen metrics/hashes: [stability-evidence.json](stability-evidence.json).

Retained earlier attempts (cold captures remain recoverable through their
`homestead.archive.json`; logs and run receipts remain at their original paths):

- `20261127T100346328273Z` and `20261127T100602937537Z`: oversized motion crops
  exceeded the declared 5 MiB limit. Reduced crop dimensions, not the budget.
- `20261127T100904585253Z`: visually rejected bright distant color band and failed
  long-window GPU gates; also an invalid global draw-count assertion during
  publication. Frozen trial shader/driver and rejected captures are retained.
- `20261127T101521899054Z`: storage admission stopped before engine launch.
  Receipt-owned archival subsequently freed space without changing limits or saves.
- `20261127T101738641573Z`: corrected color, short interleaved timings and frozen
  publication; synthetic tail gate still failed. Its global draw comparison was
  incorrectly across camera poses, and its flat-plane motion sampler misclassified
  hillside distances. Those distance claims are superseded by the final true-root
  sampler and within-pose draw check, not reclassified as passing evidence.

Historical lighting-trial command, using source revision `29e3b360` and the
recorded input save (current runtime has been restored and no longer contains
that trial; never replace the player's save to recreate it):

```powershell
python tools/run_godot_check.py vegetation_stability --isolated-render --timeout 300 --require "VEGETATION_STABILITY failures=0" -- --stability-source-slot=Homestead_Valley
python tools/analyze_vegetation_stability.py reports/checks/<run>
```

The current final run intentionally reports failure for its two unmet cost gates.
The runner admits 16 MiB (5 MiB motion packets, 6 MiB paired previews, 3 MiB context
stills, 2 MiB metadata/logs), zero saved worlds. After process exit,
`tools/maintain_homestead_captures.py --apply` owns only declared report members and
cold-retains older runs with hashes/receipts under the two-ready-run policy.
Versioned tracker images stay outside Godot imports/exports. Original code is
0BSD; original capture contributions are CC0-1.0, with underlying project-asset
terms preserved. No external implementation, dependency or asset was imported.

Remaining: isolate and reduce the worst GPU/frame-tail cost before qualifying the
minimal-cost requirement; inspect the exact supplied camera, other light/terrain
colors, zoom/resolution transitions and shadowed slopes; compare real driving and
longer/weak-hardware travel. Return with matched repeated timings and moving
captures showing both stable silhouettes and acceptable terrain contrast, then
obtain player visual acceptance. Installed-package qualification remains open.

## Distant grass speckles — 2026-11-27

The user's supplied overview crop shows small dark flecks mixed with pale cover,
including outside the building shadow. Its exact saved world, camera and distance
are unknown; the synthetic comparison below is not a reconstruction of that view.

Confirmed shading defect: `woodland.gdshader` manually inverted `NORMAL` on
back-facing leaves after Godot's `cull_disabled` path had already inverted it.
The production fragment therefore restored the wrong lighting direction. Removed
that second inversion. This affects the shared woodland foliage material, including
near leaves; stones keep their own path. Meshes, native batches, population,
interaction, shadows, fade distances and save formats are unchanged. No blending
pass, texture lookup or extra geometry is introduced; no GPU speedup is claimed.
The engine behavior was checked against its
[Forward+ shader](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl#L1168-L1175)
and [double-sided mode definition](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/renderer_rd/forward_clustered/scene_shader_forward_clustered.cpp#L786),
then demonstrated on the installed Godot 4.7.2 `ed1daf0bf`.

`tests/vegetation_shading.gd` first reproduced view-normal output 1/0 for the
front/back of a double-sided leaf. With the correction both are 1/1. The original
production shader failed this assertion; the corrected source passes all seven
checks, including exact frozen-baseline repeat and unchanged buffers for 9,984
instances. Three matched camera offsets retain the original mesh LODs and density.
The simple fixture disables cast shadows to isolate material lighting; actual
world shadow reception and terrain shape are not qualified by this check.

The inspected meadow images retain obvious distant clumps and speckling after the
correction. The count of very dark samples changes from 2,441 to 2,236 in the
defined image region, but that threshold is descriptive, not an acceptance gate.
This is a confirmed normal correction and partial visual improvement, **not a fix
for all black spots or seamless grass**. Earlier
[fade/self-shading](../../docs/evidence/vegetation_far_diagnostic/README.md) and
[LOD/MSAA](../../docs/evidence/vegetation_lod_diagnostic/README.md) comparisons also
failed to eliminate the speckling; those rejected trials remain intact.

![Baseline double-sided grass lighting](images/shading-baseline.png)
Synthetic 1080p meadow, 9,984 production foliage instances; old duplicate normal
inversion, fixed wind, no cast shadows. The regular placement is diagnostic only.

![Corrected double-sided grass lighting](images/shading-corrected.png)
Same camera, instances and materials, with the duplicate inversion removed.
Dark flecks are slightly reduced; sparse silhouettes remain visible. Neither
image is the user's world or user-approved artwork. Provenance and hashes are in
`images/manifest.json`; these original diagnostic captures are CC0-1.0.

Retained receipts:
- `reports/checks/20261127T094006354473Z/run.json`: initial generic storage
  reservation rejected before the engine launched; no limits raised or evidence
  evicted. The fixture now declares 24 MiB reports, a 20 MiB encoded-image ceiling,
  and zero saved-world allocation. It creates no export or saved world.
- `reports/checks/20261127T094139317069Z/run.json`: initial fixture parse failure;
  fixed the explicit float type. This was not a production test result.
- `reports/checks/20261127T094225737180Z/vegetation_shading.json`: expected original
  production normal failure, with baseline/corrected image controls.
- `reports/checks/20261127T094327665114Z/vegetation_shading.json`: seven checks pass;
  paired camera-offset captures inspected. No frame-time benchmark or continuous
  motion/shimmer acceptance. The matching run receipt records native/engine/source
  hashes. The adjacent identity helper uses Godot's ResourceUID generator for the
  new test sidecar; it changes no runtime assets.

Reproduce:

```powershell
python tools/run_godot_check.py vegetation_shading --isolated-render --timeout 90 --require "VEGETATION_SHADING failures=0"
```

After the owned process exits, `tools/maintain_homestead_captures.py` owns these exact report
members and cold-retains older runs under the existing two-ready-run policy.
Tracker images remain versioned outside Godot imports/exports.

Follow-up: the moving distant-cover trial above now supplies a representative
populated-world camera, motion comparison and unchanged-population/save checks.
The exact supplied view, species/LOD attribution, GPU/frame tails and user
acceptance remain open. Its shading approximation improves the measured residual
without changing the existing dither fade; a wider fade remains unqualified.
Original diagnostic code is 0BSD; no external implementation or asset was imported.

## Ground draw-page backlog — 2026-11-01

Completed the pending draw-page experiment: the 8 KiB upload allowance forced
128-instance pages, so dense visible owners created too many render submissions.
Use a bounded 64 KiB allowance / 1,024-instance page instead. Existing residency
byte ceilings, plant density, identities, ranges, shadows and meshes are unchanged.
Native rendering still owns selection and uploads; no new per-frame script scan.

Matched October 30 installed-pack 160 km/h camera sweeps, same 586 m road:
pending pages mean/max **190.95/280 → 0.12/2**; mean draw calls **1,327.63 →
1,169.52**; ground-render CPU **565.82 → 400.01 µs**. Actually drawn instances
increase **57,421 → 79,170**; this is less deferred content, not reduced density.
Frame p95 **24.189 → 22.582 ms** still misses 60 FPS. This controlled camera
sweep does not qualify physical car handling, all coverage or seamless LOD.

The combined installed build is checked for paid block placement/removal,
per-rendered-frame grass continuity, all six terrain tools, largest-volume edits,
removal persistence and 8/32/64 KiB native pages. Exact runs and retained failures:
[gameplay evidence](../runtime-performance/gameplay-evidence.json). Test fixtures
explicitly opt out of mouse capture, including external packaged drivers.
The populated maximum excavation removes 18,517 plants: support publication is
15.987 ms, just below the 16 ms fixture gate, and total edit latency is 984.515 ms.
That is not comfortable performance headroom or an ordinary pickaxe timing.
Large-edit/endurance, outer-owner coverage, foreground/weak-hardware and full-frame
budgets remain open; do not treat this page change as their completion.

## Evidence

![Extended forest](images/forest_576.png)
[448 m baseline](images/forest_448.png): identical 1024-tree grid fixture, 1080p,
same camera/light; artificial rows test coverage, not proposed forest distribution.

![Actual temporary-world travel](images/world_travel.png)
Fresh temporary seed 1703 world, moving camera, unchanged natural distribution.
No played world was read or modified. Images inspected, not user-approved.
Provenance/hashes: `images/manifest.json`.

- `tests/vegetation_extended_lod.gd`: 17 assertions; all tested owner corners,
  world edges and angles cover the visible/preload disk. Same near geometry and
  stable IDs; finite bounded nondegenerate meshes.
- `tests/scatter_priority.gd`: 23,131 parity/validation cases retain legacy API behavior.
- `tests/woodland_accents.gd`: 66 geometry, harvesting, picking and persistence checks.
- `tests/vegetation_native_selection.gd`: 2000-root/180-frame script/native parity,
  removals, transitions and sparse buffer parity pass.
- `reports/checks/20261028T150527803046Z/run.json`: 3200-plant renderer fixture;
  distant Godot primitive counter 1118 -> 544, nearby counter unchanged. This
  counter is not a claim about total hardware triangles including instancing.
- `reports/checks/20261028T151314789385Z/run.json`: actual world, 405 owners,
  5294 roots initially; bounded publication, travel and zero mouse captures.
  RTX 4050 Laptop GPU: median GPU 9.14 ms stationary / 9.15 ms moving;
  moving median/p95/max frame intervals 16.61/20.90/26.07 ms, forest CPU
  p95 0.577 ms, coordinator p95 0.225 ms. 240 frames each, offscreen 1080p,
  capped; no claim of universally smooth 60 FPS or isolated LOD speedup.
- Detailed fixture data: `reports/vegetation_lod_visual/result.json` and
  `reports/vegetation_lod_world/result.json`. Screenshots excluded from timed samples.
- Initial test-only parse errors and incorrect completion-text requirements remain
  in the 15:03/15:04 reports; corrected reruns pass, no suppressed engine errors.
- Populated city/forest approaches also pass with 391–405 resident owners:
  [city evidence and timings](../city-buildings/README.md#generated-world-integration).
  Pack startup passes; all 14 exported native DLL hashes match source.

## Remaining / resume here

- Longer/weak-hardware travel, teleport publication and longer city+forest comparison.
  Extra coverage increases resident roots and surface sampling; inspect spikes
  before extending range again. Current moving p95 exceeds a 16.67 ms frame.
- Ground mesh index switches are screen-error selected, not crossfaded. Trees retain
  their existing complementary dithering. Reopen for a visible change with camera/FOV
  and same-view comparison; do not reduce plant density to disguise it.
- No new species, new tree impostor bake or fully seamless arbitrary-speed streaming.

## Driving-speed streaming — 2026-10-29

- Confirmed: ground-cover owners fall behind fast travel; forest residency kept up
  in this fixture. This is not primarily a GPU rendering limit in these samples.
- Native root-support sampling now reuses a request-local 256-entry lattice cache
  (5 KiB stack, no persistent files). Current/original terrain and material flags
  remain distinct; edits cannot reuse a previous request's samples.
- Ground cover replenishes up to eight 64-point jobs instead of waiting for each
  four-job wave. One complete owner still publishes atomically with all 16 layers.
  Density, meshes, visibility ranges, harvesting IDs and collision rules are unchanged.
- The existing terrain worker services at most four support batches / 1.5 ms soft
  budget between background mesh work. Mutations, saves, interaction collision,
  target queries, water jobs and unknown job types remain ordering barriers.
- 160 support batches across four profiles, two seeds, boundaries, mining, filling
  and asphalt match old bytes exactly: 610 assertions. Mean 64-point native batch
  0.727→0.293 ms (2.49×). No cross-frame cache or new thread pool.
- 170 coordinator assertions include rolling/out-of-order replies, partial admission,
  invalidation, failed packets, teleport, harvest and authored plants. Worker-order,
  support, retirement, water continuation, target-readiness and vehicle collision
  readiness checks pass. Detailed receipts: [driving evidence](driving-evidence.json).

### Measured limits

Seed 1703 disposable recipe fixture; 585.6 m controlled road-camera sweep,
1080p/60 cap, RTX 4050 Laptop. **Not a physical vehicle handling qualification.**
Early physical-driver probes veered off the road and do not qualify fast driving.
Disk owner counts include off-screen/empty owners; they are not counts of visible holes.

| 160 km/h sweep | Frame p95 | Missing ground owners within 64 m, mean / max |
| --- | --- | --- |
| Original native build | 30.14 ms | 9.92 / 18 |
| Cache + rolling four jobs | 29.28 ms | 9.60 / 17 |
| Eight jobs | 28.82 ms | 6.66 / 14 |
| Bounded worker service | 23.73 ms | 4.46 / 11 |
| Installed-pack repeat | 26.47 ms | 4.31 / 12 |

The native cache alone did not fix streaming. The final 160 km/h runs still have
late cover and frames above 16.67 ms. All measured forest-visible owners were resident.
Installed 160 km/h peak: 3.30 GiB private RAM / 1.38 GiB dedicated GPU allocation;
422.7 MB distributable. Source save hash unchanged; zero mouse captures.
Installed 100 km/h sweep: frame p95 21.54 ms, mean/max missing near owners 1.75/8;
forest-visible owners all resident, peak 3.34 GiB private RAM / 1.37 GiB GPU.
There is no matched 100 km/h baseline, so this is a remaining-limit measurement,
not an improvement percentage. Both installed runs pass save/mouse/resource gates.

![Four-job intermediate at arrival](images/driving-four-job.png)
![Bounded-worker arrival](images/driving-bounded-worker.png)
Same route endpoint immediately after the speed sweep, before the eight-second
recovery. First image is the insufficient cache/four-job intermediate, not the
original build. More ground cover is ready in the second; this is not full-route
visual acceptance. Wind/time and streamed off-screen counts differ. Provenance in
`images/manifest.json`; prior images remain intact.

### Remaining / alternatives

- Require sustained real-car straightaways, turns, city/forest transitions, 100–198
  km/h, camera turns and weaker hardware before claiming seamless driving. Return
  to native chunk preparation/delivery and publication budgets, not lower density.
- Candidate next architecture: compact, versioned, pre-baked vegetation-owner
  records with bounded native decoding and upload; invalidate terrain/building
  dependencies and apply harvested/authored changes separately. Any disk cache
  must share the existing 3 GiB quota. This is **not implemented**. Keep the current
  renderer initially; these profiles do not justify replacing it with GPU scatter
  or new tree impostors. Compare complete visible coverage, visual equality, edit
  persistence, CPU/GPU timings, memory and cold/warm cache performance first.
- The integrated six-tool/edit test passed 71/72 checks, including durable removal,
  neighbours, tree collision and regeneration, but maximum-volume publication was
  26.475 ms for 18,532 queried instances, failing its 16 ms limit. Attribution to
  this change versus the prior build is unverified; retain the failure, compare
  the same fixture on the prior build before treating it as a regression or fix.
  No threshold was raised. This separate large-edit budget remains unresolved.
- Retained failed trials: invalid test asphalt/material arguments, physical driver
  setup/steering, missing ground-cover test flag, and packaged driver initially
  referencing excluded test code. Corrected harnesses are retained with receipts;
  none constitutes a production fix or successful fast-car acceptance.

Reproduce the controlled sweep:
`python tools/profile_runtime.py --slot recipe_generated_4644d8cfc8f97e43 --speed-sweep --speed-kph 160 --pack --label driving_repeat --require-resource-budget`.
Historical `--driving` is an alias for this controlled workload, not autonomous driving.

## Residency notifications — 2026-10-30

- Root cause: unchanged model and block admission/retirement emitted the same
  world-edit notifications as authoring. That dirtied every wanted ground-cover
  owner, discarded in-flight scatter work and incorrectly requested another save.
- Native model content notifications now distinguish residency. Blocks reuse their
  existing native content revision. Snapshot-cache invalidation and collection
  observers remain intact; actual edits, undo/redo, full restore and prefabs still
  invalidate vegetation. No new worker, cache, density reduction or range change.
- Validation also caught a missing content-revision increment in staged block-only
  prefabs; fixed before final qualification rather than suppressing that edit.
- Same seed 1703, 585.6 m/160 km/h controlled camera sweep, RTX 4050 Laptop,
  1080p/60 cap. Counts are disk owners, including empty/off-screen owners, not
  visible pixels. They do not qualify physical driving or arbitrary travel.

| Build | Missing near owners mean / max | Missing visible-radius owners mean / max | Frame p95 |
| --- | --- | --- | --- |
| Installed baseline `13788225` | 3.65 / 11 | 27.09 / 40 | 22.66 ms |
| Model notification fix only | 0.62 / 8 | 12.62 / 32 | 23.10 ms |
| Block + model fix, source | 0 / 0 | 0.17 / 3 | 27.32 ms |
| Block + model fix, first pack | 0 / 0 | 0.63 / 4 | 27.52 ms |
| Final pack, prefab revision regression fixed | 0 / 0 | 2.27 / 8 | 30.06 ms |

The source/first-pack runs recorded no cover exclusion-revision change or dirty
owner during the measured route. Forest-visible owner misses stayed zero.
The final repeat retains zero near misses and a constant exclusion revision;
outer coverage and timings vary, so the earlier best sample is not universal.
**This is a continuity improvement, not a frame-time improvement.** More cover
actually becomes ready; frame pacing is worse in these samples and remains open.
Do not hide this by lowering vegetation density. Return to bounded owner delivery
and render publication, then require matched repeated physical-car, sharp-turn,
zoom, edit/reload and weak-hardware/endurance evidence. Pre-baked owner records
remain only a candidate, not an implemented replacement.

Detailed reports, build identities, failed fixtures and final installed checks:
[residency evidence](residency-evidence.json). Earlier evidence is preserved.

![Prior paging notifications at the route endpoint](images/residency-before.png)
![Final installed build at the same endpoint](images/residency-after.png)
Unedited 1080p captures immediately after travel, before recovery. The far roadside
has more ready ground cover; near plants/buildings retain their appearance.
These inspected endpoints do not show every transient hole or qualify seamless
motion. Wind/time differ; provenance is in `images/manifest.json`. User review pending.

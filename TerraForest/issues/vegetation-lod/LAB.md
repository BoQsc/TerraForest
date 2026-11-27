# Vegetation diagnostic lab

Current checkpoint, 2026-11-27: human source playtest confirmed the visible flicker
correction; the user explicitly requested a source snapshot. Far stone pop-ins
while approaching, subtle LOD/distance fade and the GPU-tail target remain open.
See [scope and binary rebuild requirement](README.md#human-playtest-and-source-snapshot--2026-11-27).
Earlier stage statuses below are historical.

Status, 2026-11-27: selected fix integrated and engineering checks passed;
uncommitted, human visual review open. Storage
admission was restored by verified cold retention of 165 MiB of old completed
baseline payloads, without raising budgets or deleting evidence. The first
rendered smoke test exposed an invalid fixed-LOD control; the corrected full
matrix completed but exceeded the 6 GiB RAM gate. Neither is an accepted result.
Smaller batches now stay under 4 GiB private commit. Distance-specific framing
and in-bounds sampling replace the misleading original checks. The saved-view
lighting/species and geometry batches pass. Per-triangle fern filtering improves
the verified leaf samples but adds about 1.6–1.8 ms in two observed quiet ABBA
windows, so it is rejected for production. The seven-frond representation later
passed lossless motion, nearby equality, physical gameplay and an uncontended
uncapped comparison against the original opaque renderer. It is now integrated
into source, uncommitted. Final integration run `20261127T170227179839Z` passes
exact geometry/shader equivalence to the prototype, nearby/reference equality,
lossless pixel verification and three quiet paired cost groups against the
grass-only renderer. Default-runtime physical gameplay `20261127T171249751501Z`
also passes: 194.253 m travel, full forest, live actors, normal source shader and
fade ownership, unchanged save/runtime hashes, and 48 consecutive lossless
pixel-verified frames at 16 ms median / 32 ms p95 capture intervals. No other
engine job was observed. This is scripted input through normal physical gameplay;
it is not a human playtest. [Motion](images/gameplay-runtime.webp) and
[full context](images/gameplay-runtime-context.png) remain available for review.
Normal physical gameplay run `20261127T144446606943Z` passed with 194 m travel,
1,024 forest cells and 8,461 trees loaded. Its crop and cost qualification are
separate from controlled laboratory comparison and human visual approval.
The production freeze ended after run `20261127T164801248443Z`: a startup-only
seven-frond fern mesh and specialized shader now join the existing far-grass
filter. No global lighting or antialiasing setting changes. Human approval remains
pending; no commits or history changes are authorized.

The earlier work moved from a plausible coverage explanation into implementation
too soon. Some later isolations are useful evidence, but a wrong gameplay crop,
brightness regression and concurrent timing runs prevent a broad success claim.
This lab makes those failure modes explicit checks before more production edits.

## Capture correction discovered during qualification

The initial packet encoder passed `true` to Godot's `save_webp_to_buffer`.
That means **lossy**, not lossless. Raw luminance samples and exact raw
near/reference hashes are unaffected, but earlier preview-derived contrast
counts and brightness estimates require recapture. Historical animations remain
illustrations, not pixel-faithful motion acceptance. This limitation applies to
the numeric preview contrast comparisons below until replaced by corrected runs.
New packets use explicit lossless encoding and carry source RGB hashes, checked
again after decoding. A deliberate one-pixel corruption test checks rejection.
The lab retains full motion for the strafe path and first frames for other paths
to stay within the unchanged 8 MiB packet cap; all paths retain raw temporal data.

Gameplay capture now uses asynchronous cropped GPU readback with
bounded memory, one full context frame, consecutive frame identities and measured
timestamps. This replaces synchronous readback's 36–44 ms median cadence.
Run `20261127T164348288633Z` passes over 194.3 m with 1,024 forest cells and 8,461
trees, live actors and unchanged save bytes. All 48 frames are consecutive and
their decoded RGB hashes match. Median capture interval is 16 ms, p95 25 ms;
this is measured cadence, not a claim of perfectly constant 60 FPS. No other
engine job was observed. The later default-runtime integration replay is separate.
API meanings were checked against the engine's
[image encoding reference](https://docs.godotengine.org/en/4.7/classes/class_image.html#class-image-method-save-webp-to-buffer)
and [asynchronous readback reference](https://docs.godotengine.org/en/4.7/classes/class_renderingdevice.html#class-renderingdevice-method-texture-get-data-async).
Original helper code is 0BSD; no external implementation was copied.

## Three separate experiments

1. **Geometry sampling control.** Existing `vegetation_causes.gd` renders fixed,
   unlit individual LOD meshes over 16 subpixel phases, at several MSAA levels.
   No terrain, wind, texture, lighting, streaming or LOD switching participates.
   Earlier results establish substantial geometric coverage instability in the
   72-triangle tier. They do not establish the entire source-world flicker cause.
2. **Source-scene matrix.** `vegetation_lab.gd` loads the existing source save
   read-only, settles actual vegetation pages, and freezes simulation for matched
   camera/time replays. All interventions are in-memory mesh/material/settings
   overrides. The [42-case matrix](../../tests/fixtures/vegetation_lab.json)
   declares the parent, one changed factor, and question for every case.
3. **Normal gameplay gate.** `vegetation_gameplay.gd` uses real W/D movement,
   collisions, live actors and streaming. It is a separate test after lab review.
   Deterministic camera replay is never substituted for this gate.

The lab compares the pre-filter opaque reference with the current experimental
candidate and isolated controls. It does not silently treat the candidate as the
correct baseline. Exact file/native/save hashes accompany captured runs.

| Question | Controlled intervention | What it can establish |
| --- | --- | --- |
| Which objects contribute the points? | Remove grass, ferns, stones, bushes, flowers or twigs separately | Species attribution; contributions can overlap |
| Is motion of the blades responsible? | Freeze grass wind | Wind contribution at identical camera poses |
| Is texture minification responsible? | Disable grass texture modulation | Texture contribution without changing geometry |
| Are white points highlights or backlighting? | Disable specular and backlight separately | Separate lighting contributions |
| Are dark points shadows or canopy shading? | Disable shadow reception and canopy shading separately | Separate shading contributions; brightness is measured too |
| Does fade dithering matter? | Remove distance/birth coverage discard | Coverage-discard contribution; changes visibility, so diagnostic only |
| Are LOD switches the cause? | Hold low, eight-triangle or three-triangle color geometry | Residual noise without color-geometry switching; original shadow LOD layout retained |
| Is geometric sampling the limit? | 8x MSAA control | Additional sampling benefit and cost; not a production recommendation |
| Does temporal reconstruction help? | TAA control | Temporal benefit, cost and reviewable motion artifacts |
| Is earlier coarsening enough? | Opaque thresholds 0.12, 0.06, 0.045 | Coarsening effect, with the horizon threshold held at 0.20 |
| Is filtering doing useful work? | Filtered versus opaque at each matched threshold | Effect of the filtering implementation, separate from earlier coarsening |
| Does the horizon transition help? | Change only 0.20 to 0.10 on filtered 0.045 | Incremental horizon-tier effect |
| Does surface removal save work safely? | Toggle only native surface selection | Exact replay parity plus submission/GPU observations |
| Are residual fern leaves undersampled? | Filter existing far triangles, then lower only the fern transition threshold | Leaf coverage contribution, preserving authored lighting and nearby geometry |
| Can the filter cost be reduced? | Replace 154 triangle kernels with seven area/covariance frond kernels | Measured quality/cost tradeoff; projected area uses separate normal groups rather than one cancelling average |

Every case uses a stationary camera, lateral motion, and approach-with-turning.
Wind time advances deterministically in all three. Near-view preservation is a
separate full-frame equality check for both complete candidate variants.

## Reject misleading measurements

- Select a 320x128 field region using actual 60–120 m grass roots and measured
  image changes when **only 60–120 m grass is removed**. Foreground depth stays
  intact, preventing occluded far roots from falsely identifying near grass.
  Require at least 128 changed pixels and 12 visible grass anchors. Every selected
  anchor must stay inside the image for every pose; never extrapolate image-edge
  interpolation. Reject nonfinite or out-of-range display luminance. Preserve a
  full context view and distance-specific removal image (`field_no_grass.png`).
  A road/tool/empty-field crop fails; the rendered crop still needs inspection.
- Replay the original reference again after all interventions. Require exact
  hashes for every matched frame, excluding HUD by the verified field crop.
  The eight Python checks deliberately inject baseline noise, empty fields, changed
  nearby pixels, missing samples, contended/missing cost monitoring, truncated
  captures and changed decoded pixels to check rejection.
- Keep registered temporal luminance residual, local bright/dark contrast and
  average display luminance separate. Lower contrast after brightening is not
  sufficient evidence of a fix. A temporal residual includes real wind and
  silhouette/occlusion motion; it is not a universal flicker percentage.
- Capture matched lossless frames for the opaque reference, earlier opaque LOD,
  full filtered candidate and optimized candidate. Other diagnostic cases retain
  a frame for each path and raw temporal samples. Review side-by-side motion.
- Measure GPU/CPU/draw windows without readback or encoding, in forward/reverse
  case order. Final geometry/sampling cost controls disable the cap and VSync
  temporarily, with 240 warmup frames, 96 settling frames per case and 256 samples
  per round. This measures headroom separately from normal gameplay at source
  settings; earlier capped observations showed substantial timing drift.
  Timed runs refuse an existing render job and record observed
  overlap every five seconds. Missing or adverse overlap evidence invalidates
  GPU environment qualification. Short overlap or unrelated GPU applications can
  escape this process inventory; clean repeat measurements remain necessary.
  Explicit visual-only experiments freeze simulation/time and repeat the
  reference exactly; they may overlap other work and never qualify GPU timings.
- A removed-species/shadow/wind control is an explanation experiment, not an
  automatically acceptable visual solution. The analyzer never promotes code.

## Running and storage

Original lab code/configuration is 0BSD. Existing asset/shader licenses remain.
Use the current checkout and source DLLs; no worktree, native rebuild, export,
source copy or new saved world is part of the lab.

```text
python -B tools/run_vegetation_lab.py --list
python -B tools/run_vegetation_lab.py --grounded-view --cases fixed_low,fixed_eight,fixed_three,filtered_12,filtered_previous,residual_no_grass,residual_no_ferns,residual_no_stones,residual_no_bushes,residual_no_flowers,residual_no_twigs
python -B tools/run_vegetation_lab.py --cases no_grass,no_ferns,no_stones,no_bushes,no_flowers,no_twigs,frozen_wind,no_texture,no_specular,no_backlight,unlit,up_normals,no_received_shadows,no_fade_discard,no_self_shade
python -B tools/run_vegetation_lab.py --grounded-view --cases msaa8,taa
python -B tools/run_vegetation_lab.py --gameplay
python -B tools/run_vegetation_lab.py --gameplay --previous-filter-control
python -B tools/run_vegetation_lab.py --grounded-view --visual-only --cases fern_cluster
python -B tools/run_vegetation_lab.py --grounded-view --paired-cost fern_cluster
python -B tools/run_vegetation_lab.py --gameplay --fern-cluster-trial
python -B tools/analyze_vegetation_lab.py reports/checks/<completed-lab-run>
```

Selected runs automatically include comparison ancestors. Start with a small
subset to validate framing, restoration and shader compilation. Exercise the
matrix in bounded batches, not one accumulating process. The first new render
attempt was stopped before launch: shared reports
plus the declared 20 MiB exceeded the unchanged 4 GiB cap. This is **not** a
passing or failing vegetation experiment. The source parser initially caught an
invalid byte-array hashing call; it was corrected to `HashingContext`.

The runner admits 20 MiB, with a combined 16 MiB driver cap (including an 8 MiB
lossless-frame packet), at most 3 MiB for a review animation, and remaining log/
receipt metadata. Only receipt-owned named outputs enter existing verified cold
retention, keeping two ready runs by default. No storage budget is increased.
An archived result remains available through its receipt and verified chunks.

## Recorded failures and useful controls

Compact results, qualifications and resource peaks are retained in
[`lab-evidence.json`](lab-evidence.json), with full receipts under `reports/checks`.

| Run | Outcome |
| --- | --- |
| `20261127T142630188405Z` | Rejected: fixed-LOD buffers violated an engine constraint; another render job overlapped. Corrected control keeps visible geometry fixed with a zero-area base triangle. |
| `20261127T143210488274Z` | Full 28-case exploration completed, but 6.41 GiB private commit exceeded the 6 GiB gate. Shader reuse and smaller batches replaced this run for qualification. |
| `20261127T145341617839Z` | Engine/resource pass; rejected far framing because all-grass removal selected foreground occlusion. |
| `20261127T150024402022Z` | Distance-specific framing and exact near/reference parity pass; rejected turning metric because some anchors left the viewport and inherited bilinear sampling extrapolated. Other path observations do not qualify the entire run. |
| `20261127T150408327322Z` | Saved-view species/lighting controls pass, including bounded temporal samples, distance-specific crop, exact reference replay, near equality, save/population preservation and resource budget. |

In that last verified field, removing grass lowers lateral registered luminance
residual from 0.06005 to 0.00053. Disabling received shadows leaves it unchanged;
freezing wind, disabling specular or backlight does not materially improve it.
Removing texture modulation worsens it to 0.09835. Upward normals change mean
field luminance from 0.40845 to 0.41375 and bright outliers from 34 to 94, while
lateral residual is 0.06124. Unlit geometry raises bright outliers to 181.
These results weaken those shader adjustments as a fix for this view. They are
not universal species percentages: anchors are selected from grass, and spatial
outlier counts include overlapping contributions from other vegetation.

The normal gameplay gate waits for all 1,024 forest cells before moving. The
latest driver retains 48 consecutive rendered frames, postpones encoding until
measurement is over, and records actual capture intervals. GPU timings exclude
the readback phase. Earlier stride-six footage remains labelled as such.

## Causal results and rejected costs

The corrected geometry batch `20261127T150753233981Z` passed all framing,
in-bounds sampling, repeated-reference, nearby equality and preservation checks.
Holding the 72-triangle low tier still gives lateral residual 0.04672, the same
as automatic LOD. Switching LODs is therefore not required for the observed
noise. Earlier opaque coarsening reduces it to 0.02672; filtering at the matched
threshold reduces it further to 0.01309. The 0.045 and 0.06 filtered thresholds
are identical in this patch: moving that threshold again is not a demonstrated
remaining fix. Native inactive-surface selection gives exactly identical motion
pixels and reduces draws from 2,203 to 2,072. GPU speedup is not established.

The AA diagnostic `20261127T151404555399Z` shows stronger temporal stabilization
with TAA, but its combined MSAA/TAA process exceeds the 6 GiB private-commit gate
(6.16 GiB). It does not isolate each setting's memory cost. No global AA change
is accepted; this also changes nearby rendering. The later grass ABBA cost run
`20261127T151933069112Z` overlaps other engine work and is not qualified.

Fern anchors are actual transformed far-leaf centroids, verified by removing
only 60–120 m ferns with foreground depth preserved. Run
`20261127T153745399552Z` samples 32 points across 11 plants. Per-triangle filtering
at the earlier fern threshold reduces lateral residual 0.08432 → 0.00397 and
approach/turn residual 0.08667 → 0.01583. Field mean luminance changes about
+0.45%; dark local outliers fall 973 → 713, while bright count remains 143.
Every nearby variant is byte-identical. These are scoped image measurements,
not a universal flicker reduction or human visual acceptance.

That visually useful implementation is **rejected for cost**. In
`20261127T154743700341Z`, the first two ABBA windows add 1.5685 and 1.75275 ms GPU.
No other engine job was observed within six seconds of those windows; the
whole run overlaps elsewhere, and its third cost window is contended. Clock and
power observations are retained. An inventory cannot exclude brief or unrelated
GPU work, but the consistent penalty is enough not to promote this candidate.
Its normal physical gameplay trial `20261127T154300075191Z` passes movement,
full-forest and save-preservation checks over 194.7 m; overlapping rendering
prevents a qualified gameplay cost comparison. Readback frames have median
36 ms cadence (95th percentile 59 ms), not 60 fps footage.

The selected implementation combines each distant frond's triangles into one Gaussian
shape, preserving area, centroid and principal covariance. Five signed normal
groups per frond retain projected leaf area at oblique views. It uses seven
quads instead of 154, shared startup geometry and 35 uniform vectors; no new
textures, history buffers or per-instance CPU updates. Approximate shape and
averaged shading passed image, movement and GPU gates before runtime integration.

The resulting complete candidate passed `20261127T164801248443Z`: three quiet
uncapped ABBA groups versus the original opaque renderer improve GPU median by
0.827, 0.684 and 0.614 ms, and p95 by 0.946, 0.751 and 0.628 ms. The lossless
packet decodes to original RGB hashes; nearby and repeated-reference frames are
exact, and source/save/population/resource gates pass. This establishes the
combined candidate's scoped improvement against that baseline.

Final integration run `20261127T170227179839Z` compares the grass-only renderer
against the production seven-frond implementation. Three accepted ABBA groups
reduce GPU median by 0.295, 0.208 and 0.195 ms; p95 improves by 0.252, 0.217 and
0.163 ms. Draw count increases by 29 in this view, but rendering fewer fern
triangles more than offsets it in these measurements. The monitor observed other
work during preparation, so whole-run isolation is false; all three cost groups
have no observed overlap within the six-second margins. GPU clocks sampled
during those groups are 2145–2235 MHz. This is scoped evidence on this laptop,
not a guarantee for other GPUs, views or brief unobserved interference.

This run verifies source geometry and shader expressions against the prototype,
exact nearby and repeated-reference frames, unchanged source/save/population and
pixel-faithful lossless motion. Mean field display luminance is 0.378367 versus
0.376269 for grass-only (+0.56%) and 0.373897 for the original opaque renderer
(+1.20%). Fern-anchor registered residual changes from 0.084317 to 0.003070 on
strafe and 0.086586 to 0.015169 on approach/turn. These are motion/contrast
measurements, not universal flicker percentages. No global brightening is used.
Peak process private commit is 3.93 GiB and dedicated GPU allocation 1.65 GiB,
within the unchanged sampled resource limits.

Timed paired runs can prepare once and wait with the viewport disabled until the
external job monitor reports idle. Each complete group is accepted only with a
fresh heartbeat and no observed overlap, including a six-second margin. Rejected
groups remain in the report. A transient heartbeat read race invalidated run
`20261127T165619317516Z`; that owned run was stopped, the reader now fails closed
without emitting JSON parser errors. The integration rerun above passes.

## Decision before another production change

Record each hypothesis as supported, weakened, unresolved or contradicted with
its specific controlled comparison. Do not rank a candidate from one aggregate
number. Require repeatable source-scene evidence, unchanged nearby pixels,
terrain/brightness review, uncontended cost measurements, and correctly framed
normal physical gameplay. Preserve rejected candidates and failed tests.
Human visual approval remains separate. No commits are authorized here.


## Stone and flower follow-up — 2026-11-27

Requested scope: prove the remaining stone/flower causes, retain nearby pixels
and terrain tone, qualify GPU cost and replay normal physical gameplay. No commit
is authorized before human validation. The established grass/fern renderer stays
fixed during these experiments. The matrix now has 67 cases; original source
materials/assets, native instance buffers and saved-world bytes remain unchanged.

Two initial framing runs (`20261127T172727787910Z`, `20261127T173002005685Z`)
failed the minimum flower-anchor gate. Ground/elevated views contained only seven
and six usable petal samples. Those are rejected, not causal results. A bounded
twelve-yaw scout now selects natural source flowers by measured far-only removal,
with no inserted instances or density change. The accepted view has 23 samples
across 12 plants, 60–120 m away. Lab camera elevation is explicitly eight metres
above ordinary eye height; the separate gameplay gate remains grounded.

Stone controls (`20261127T173327049610Z`) pass with 48 anchors across 18 stones.
Fixed low LOD is pixel-identical to automatic LOD on the measured paths. Removing
normal mapping, texture variation or fade does not materially improve the moving
residual; disabling specular changes it only slightly. Lighting removal retains
instability. Small-stone pixel coverage is the dominant tested mechanism.

Flower controls (`20261127T174240239818Z`) similarly rule out LOD switching and
specular as the main cause. Wind explains stationary motion but does not solve
camera-motion noise. Simplifying procedural petal shading has a strong effect.
The finer controls in `20261127T175052759387Z` identify the unbounded edge term:
`mix(1.0, 0.79, edge * edge)` can become negative when extrapolated UVs leave the
triangle. Bounding only that multiplier reduces the isolated strafe residual
from 0.096622 to 0.027319. Bounding canopy shading or removing the high-frequency
rib sine does not materially help. The matched species-removal subtraction
separates background motion from the reported object contribution. These are
registered motion/contrast measurements, not universal flicker percentages.

The first combined prototype replaces far small stones with an analytic silhouette
whose area is derived from all 48 authored low-mesh face vectors; its textures,
roughness, specular and reconstructed terrain intersection remain. Sparse flower
triangles initially use area-filtered coverage and averaged, bounded edge shading.
`20261127T174637920808Z` passes nearby/reference equality and decoded RGB hashes.
In its inspected field, mean display luminance changes from 0.47124775 to
0.47123770 (−0.0021%). Raw strafe residual is 0.012497 → 0.005045 for stone
samples and 0.097045 → 0.004347 for flower samples.

That implementation is **not promoted**: the three quiet paired groups in
`20261127T175052759387Z` add 0.455/0.395/0.262 ms GPU median and
0.491/0.461/0.380 ms p95. The current experiment groups each flower's two crowns
into four area/covariance kernels, retaining separate pale heads and green stems/
leaves. Its quality/cost gate, integration, physical gameplay and human review
remain open. Existing captures are retained by receipt; admission limits are not
raised. Godot shader built-ins were checked against the
[official spatial shader reference](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html);
implementation is original project code, not copied from that documentation.


The four-group experiment (`20261127T180032417380Z`) reduces the flower tier to
8 triangles. Exact nearby/reference and source/population checks pass. Raw stone
strafe/approach residuals are .002893/.007173 versus .012497/.023216; flowers
are .005123/.007616 versus .097045/.095538. Mean field display luminance changes
by -0.0358%. One quiet tail still adds .351ms, above the .3ms cost target.

A 33,540-byte area lookup (`20261127T181425461867Z`) is accurate within .47212%
at 8192 tested mid-cell directions, but does not establish a GPU cost win. It is
retained as an experiment, not selected for runtime. Split ABBA measurements
(`20261127T182117180687Z`) identify stones as the larger remaining cost:
median +.267–.449ms versus flowers -.123–+.257ms. All six windows are quiet by
the process monitor. Clock drift and short/unrelated GPU work remain limitations.
The next control skips expensive vertex work only when a stone is fully faded,
without removing visible stones or changing brightness. Runtime integration and
physical gameplay remain pending until this final candidate is assessed.


Source integration `20261127T183409513441Z` passes the actual production helper
geometry/shader comparison, exact nearby/reference frames, source/save/population
preservation and pixel-faithful motion. Four flower groups and the stone early
visibility exit are enabled in the normal source; the texture lookup and the
expensive per-triangle flowers remain laboratory controls only. Far source
stone residuals are .002893/.007173 for strafe/approach, versus .012497/.023216;
flower residuals are .005133/.007676 versus .097045/.095538. Field mean brightness
changes approximately -0.036%. Nine harness validity tests pass.

Quiet GPU groups 0/2/3 report median +.29275/-.013/+.1535ms and p95
+.4005/+.0155/+.136ms versus the grass/fern baseline. Group 1 is rejected for
observed interference. The .3ms incremental tail target is **not passed**. This
is a visible improvement with bounded added cost, not a claim that filtering is
free. Human review and broader settings remain required. A prototype-only exit
run had worst tail +.3015ms, also retained as a narrow miss.

Physical gameplay admission was delayed by a report-storage limit and by an
active player session. The user closed that session to allow verified archival.
A bounded `--gameplay --wait-idle` launch now waits up to 180 seconds after storage
admission if another engine starts during preflight. It never stops another
process. The gameplay analyzer distinguishes preflight overlap from the actual
engine interval (with six-second margins), retaining the full witness. This is
not permission to report contended gameplay timings as qualified.


Final physical source gameplay `20261127T190137324274Z` passes all checks without
trial overrides: 194.1817m travel, 2162/2162 grounded ticks, full 1024-cell forest,
8461 trees, live actors/streaming, and far draw pages for stones/white/gold/violet
flowers (165/37/25/43 respectively). All 48 frames are consecutive and decoded
RGB hashes match; capture cadence is 15ms median/32ms p95. Source and saved-world
hashes remain unchanged. No other engine job was observed during the actual
engine interval. GPU phase medians are 4.863–5.691ms, p95 6.326–7.431ms; these
single-run observations do not replace the paired lab cost comparison.
Full context and native frames 0/15/31/47 were inspected. The inspection contact
sheet and motion preview together use 3,128,741 bytes, below the existing 3MiB
analysis cap. Versioned review copies carry provenance and hashes. Nine harness
negative controls, final GDScript/Python parsing and whitespace checks pass.
The project/source is ready for human review; no commit or export was made.
The stricter .3ms incremental detail GPU-tail target remains explicitly open.


### Whole-frame rejection and expanded diagnosis (2026-11-27)

The user rejected the integrated visible result. Prior registered samples and
320-pixel gameplay crops did not qualify the entire frame. The new
`tests/vegetation_fullframe.gd` compares all 1920x1080 raw pixels while moving the
normal world camera, with ground-level and elevated poses. It holds population,
geometry, lighting and time fixed between baseline, bounded-edge, invalid-value
witness, bounded witness, no-cover attribution and baseline-repeat controls.
No production shading change is justified by a partial run alone.

The witness evaluates the original material and marks negative albedo magenta,
nonfinite albedo cyan and values above one yellow; the original geometry,
coverage and depth remain. Local dark/bright impulse counts include the entire
viewport (including legitimate UI/edges). They are diagnostic counts, not a
universal flicker metric. Matched raw RGB differences and repeat identity test
causality; H264 videos are visual review only. The normal physical gameplay
harness now supports full-viewport asynchronous readback, encoded/analyzed only
after its movement and GPU measurement windows.

Initial harness failures remain retained: `20261127T192255355184Z` was blocked
before launch by storage admission; `20261127T192558927445Z` exposed a test-only
uniform declaration-order error; `20261127T192804297481Z` exceeded the declared
image cap. Its full evidence is cold-retained, including the observed negative
albedo witness; it is not a passing movement comparison. The revised capture
saves fewer duplicate context PNGs under the same 20 MiB admission.


Completed whole-viewport run `20261127T193738421329Z`: 337 raw full frames,
349 fixture checks, exact baseline repeat, unchanged save/population/draw pages.
Negative markers reach 1,983 before, four with edge-only bounding, and zero in
all 48 views after also bounding the interpolated root/canopy shading. The
normal shader now contains those bounded expressions. Valid authored-domain
values and all geometry/material parameters are unchanged. Average full-frame
luminance changes +0.183% on the ground and +0.020% elevated. In elevated frame
24, extra dark/white impulses over the no-cover image fall from 328/1 to 0/0.
These are whole-viewport diagnostics, not a guarantee of every possible kind of
shimmer. The yellow marker counter also detects brown background pixels; it
must not be cited as proof of high vegetation albedo without background
subtraction. No nonfinite markers were detected, but it is likewise a display
colour detector. Magenta has zero baseline/no-cover false positives here.

The interpolation mechanism is consistent with the [Vulkan MSAA documentation](https://docs.vulkan.org/samples/latest/samples/performance/msaa/README.html):
a covered sample can use shading evaluated at a pixel center outside a thin
primitive. The local witness and one-factor controls establish the faulty
edge-domain expression independently of that mechanism explanation.

Full media stays ready in the receipt-owned report under `RETAIN_READY` for
human review. `fullframe-evidence.json` contains the versioned compact results;
original full-size PNGs and three 1080p review movies are linked from the issue.

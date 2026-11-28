<!-- SPDX-License-Identifier: CC0-1.0 -->
# Near vegetation handoffs — snapshot checkpoint, 2026-11-28

The accepted stone/distance-fade checkpoint is `b0c90fd8`, pushed with tag
`playtest/stone-transitions-2026-11-28`. The user requested this **first-grass-handoff snapshot** be committed and pushed
on 2026-11-28 after the source playtest launch. Its tag is
`snapshot/near-lod-fade-2026-11-28`. Causal tests and physical gameplay pass in
the scope below. Snapshot approval does not establish universal visual acceptance.
Other species,
later handoffs and every possible rectangular artifact are not declared resolved.

## Cause demonstrated in isolation

Grass has four tiers; the other ground-cover families have three. These are not
fixed concentric rings: the engine chooses mesh LOD using each draw batch's
bounds, with thresholds dependent on view and resolution. Ground cover uses
16 m draw partitions. At the first grass handoff, geometry changes from 26 blades
with five segments (468 triangles) to 12 blades with two segments (72 triangles).
A rectangular group can therefore change density and silhouette simultaneously.

The fixture holds 144 plants resident, with fixed lighting/time and no streaming,
births, shadows or filtered far quads. Ordinary opaque LOD alone reproduces the
grouped change; fixed full/low references, tagged tiers and exact source repeats
provide controls. This proves one cause of rectangular handoffs, not that every
rectangle in the user's gameplay has the same cause.

The refined 41-position approach advances 2.5 cm per sample. At two batch switches,
the strip's summed absolute RGB difference from the no-cover reference changes:

| Camera separation | Source | Fixed low control | Per-plant opaque fade |
| --- | ---: | ---: | ---: |
| 14.525 m | +29.54% | +0.47% | +0.35% |
| 14.400 m | +18.89% | -0.30% | -0.35% |

These are grass-contrast changes within a fixture strip, not whole-frame
brightness percentages or a general flicker score. Normal rasterization variation
remains between samples.

## Initial wide candidate and rejected alternatives

The initial candidate uses complementary opaque coverage over 12–18 m per plant, one
mesh/surface, depth writes and no per-instance CPU updates. Both fully established
endpoints match the corresponding original opaque images byte-for-byte. A blended
alpha alternative fails both endpoint comparisons and is rejected.

The candidate submits extra high/low geometry in the transition band. Local ABBA
GPU observations show no increase in this tiny fixture, but cannot establish
full-world cost. The later two refined groups measure median differences of
-0.012/-0.009 ms and p95 differences of -0.014/-0.014 ms; the first group's larger
source tail is retained in the data, not presented as a performance gain.

The native-size comparison was inspected: the source's density step is visible,
while the candidate pair changes much less. Grain during continuous motion,
silhouette mismatch inside the fade, actual gameplay brightness and full-world
GPU cost were unqualified by that fixture. Endpoint equality does not prove these
properties. The subsequent real-scene run measures p95 increments of
+0.59/+0.95/+0.64 ms: the wide band is rejected for cost.

## Current short fade and normal gameplay

The current band is approximately **12–14 m at normal 1080p/75° settings**,
following the engine's projection/resolution metric. It ends at error 0.0198,
before the unchanged batch cutoff at 0.02. Plant origins lie inside the batch
bounds, so every plant has reached the identical low mesh before the batch can
switch. This removes the simultaneous visible shape change at this handoff.

Inactive geometry collapses in the vertex shader. The base draw includes 72 extra
low-LOD triangles, then returns to the original 72-triangle buffer at the original
cutoff. There is no new texture, draw pass or per-plant CPU update. A cached shader
variant enables the fade only for grass; it compiles out for other vegetation.
Lighting, tint, textures, wind and near blade positions retain their expressions.

The final textured/shadowed fade sweep `20261127T232729276103Z` compares against
the committed shader fixture. Both established endpoints are exact. Its largest
6 cm contrast step is 1.86%, versus 1.80% for fixed low grass. The current world
comparison measures **+0.03537% mean display brightness** and exact nearby pixels.
Its three paired GPU median increments are +0.189/+0.218/+0.220 ms; p95 increments
are -0.045/+0.106/+0.101 ms. The preceding cost-only run measured p95 increments
+0.247/+0.359/+0.172 ms. A universal +0.3 ms allowance is therefore not claimed;
the earlier detail GPU-tail target remains open.

Physical gameplay `20261127T234144741194Z` passes **312.75 m** of held movement
with collisions, normal streaming, live actors, 1,024 forest cells and 8,461 trees.
There are 3,006 grounded ticks out of 3,013 and no measured loading/death/respawn
frames. One explicit route setup teleport precedes measurement; the walk does
not replay positions. All **192 consecutive native 1080p frames** have unique raw
hashes matching the independent analyzer. Visible plants occupy the fade band
throughout; five old near-LOD batch boundaries are crossed inside the capture.
Nearby pixels after the walk match the baseline exactly; the save hash is intact.

The lossless context and sampled motion review were inspected without finding
the earlier simultaneous near batch-density jump. Human judgment of grain and
silhouette is still required. Interleaved walking GPU medians are
5.312/5.261/4.698 ms versus baseline 5.364/5.037/5.061 ms. Those windows visit
different positions and do not establish a performance gain. Readbacks and
warmup are excluded, but the test-only capture buffer stays allocated. Capture
spans 5.307 seconds; the 60 fps review movie lasts 3.2 seconds and is not a
sustained-60-fps claim.

## Failed comparison and camera negative control

The initial world test failed nearby equality, but even unchanged baseline
captures differed while all 1,140 terrain nodes/transforms remained unchanged.
Repeated global-position assignment followed by `look_at` passes through the
rotated player parent at large coordinates and loses transform precision.
Rounded matrix strings hid that difference. One canonical complete transform
restores exact baseline and candidate images, with and without shadows
(`20261127T231734715248Z`). The player camera implementation is unchanged.

Run `20261127T232902522565Z` passes the current visual comparison but fails one
new negative-control assertion: restoring the observed global matrix introduces
another parent-inverse round trip. Keep that overall failed run visible. The
later passing physical test changes matrix bytes and pixels with three legacy
assignments, then restores pixels exactly using the saved **local** matrix.
It also rechecks candidate-versus-baseline nearby equality. This closes the
camera-control defect without weakening the image gate. The corrected standalone
driver receives separate parser verification.

## Evidence and remaining gate

- [Structured results and hashes](near-transition-evidence.json).
- [Coarse lab](../../reports/checks/20261127T224204985941Z/transition.json): all controls and endpoint checks.
- [Tagged tiers](../../reports/checks/20261127T224204985941Z/tagged_context.png): red full / blue low show grouped selection.
- [Source context](../../reports/checks/20261127T224204985941Z/source_context.png) and [candidate context](../../reports/checks/20261127T224204985941Z/dither6_context.png).
- [Refined lab](../../reports/checks/20261127T224518006743Z/transition.json) and [native-size lossless comparison](../../reports/checks/20261127T224518006743Z/transition_review.png): source before/after, then candidate before/after the first switch.
- [Lab implementation](../../tests/vegetation_near_transitions.gd), run through the admitted 12 MiB capture family; receipt-owned retention preserves archived evidence.

Current evidence: [real-scene page witness](../../reports/checks/20261127T232902522565Z/page_witness.png),
[candidate context](../../reports/checks/20261127T232902522565Z/near_fade_24.png),
[full-frame measurements](../../reports/checks/20261127T232902522565Z/analysis.json),
[physical report](../../reports/checks/20261127T234144741194Z/vegetation_gameplay.json),
[lossless starting context](../../reports/checks/20261127T234144741194Z/walking.png),
[moving review](../../reports/checks/20261127T234144741194Z/gameplay.mp4), and
[native-size crops around three crossings](../../reports/checks/20261127T234144741194Z/motion-review.png).
Movie-derived images are review material, not raw pixel measurements.

Storage admission failures and rejected comparisons remain in the structured
evidence. After archive capacity was reached, 16 unpublished chunks were retired
only after scanning published references and verifying unchanged live source
copies. No referenced archive data, capture, save or limit was removed or raised.
[Recovery record](../../reports/checks/20261127T232902522565Z/archive_recovery.json).
Current comparison/gameplay captures are pinned for human review. Release those
pins after approval/rejection and use verified cold retention; older cold captures
remain recoverable through their owning manifests.

The user authorized committing and pushing this snapshot on 2026-11-28.
The remaining visual gate is explicit feedback on near-handoff seamlessness,
grain and silhouette; the snapshot request alone does not close that gate.
Broader FOV/resolution/light, high-speed movement, other species and later tiers
remain separate coverage requirements before universal closure. If fading alone
still looks different, compare a silhouette-preserving low mesh next. The prior
220 m test validates the stone checkpoint; this new 312.75 m test covers the
current near-handoff candidate.

Original AI-assisted investigation documentation and measurements, generated from
this repository's lab in response to the user's near-handoff/rectangle report;
CC0-1.0 under the repository contribution policy. New code is 0BSD.
`tests/fixtures/woodland_pre_near.gdshader` preserves the repository shader from
`b0c90fd8` under its existing 0BSD notice. No external assets imported.

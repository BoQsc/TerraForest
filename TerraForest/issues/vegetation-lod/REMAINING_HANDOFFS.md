<!-- SPDX-License-Identifier: CC0-1.0 -->
# Remaining cover handoffs — accepted source snapshot, 2026-11-28

**Human acceptance — 2026-11-28:** The user verified the latest source after checking
standing still and walking, and authorized commit/push. Milestone:
`playtest/vegetation-fades-2026-11-28`. This accepts the current fade/projection
snapshot, not universal seamlessness or the earlier GPU-tail target. Historical
failed and rejected controls below remain evidence. Shared DLLs are excluded;
restoring the native page-overlap change requires rebuilding the structures addon.


Continuation: [far proxies, grass horizon and grouped shadows](FAR_HANDOFFS.md)
now have a separate candidate and causal controls. This document preserves the
earlier opaque-tier experiment and its limits. The combined corrected source now has human approval as recorded above.

Baseline: approved snapshot `84d60efd`, tag
`snapshot/near-lod-fade-2026-11-28`. The user still sees nonseamless transitions
while moving. The first grass fade did not cover every species or every tier.
The investigation originally separated that checkpoint from a new candidate; current acceptance is recorded above.

## Transition inventory

Distances below describe the normal 1080p/75-degree projection. Mesh cutoffs use
distance to the closest point of each draw batch, not concentric rings around
every plant. Origin distances drive the new fades. These distances change with
projection and resolution; they are approximate explanations, not fixed constants.

| Ground-cover transition | Snapshot | Current candidate |
| --- | --- | --- |
| Grass full to low, about 14 m | Per-plant fade, already approved as a snapshot | Unchanged |
| Fern, low bush, woody bush full to low, about 18 m | Hard batch switch | Per-plant fade over approximately 15.7–17.5 m |
| Flowers and dry twigs full to low, about 14 m | Hard batch switch | Per-plant fade over approximately 12.1–13.9 m |
| Small stones full to low, about 21 m | Hard batch switch | Per-plant fade over approximately 19.2–21.0 m |
| Bushes and dry twigs low to outer opaque tier, about 56 m | Hard batch switch | Per-plant fade over approximately 52.4–56.2 m |
| Grass low to filtered triangles, about 32 m | Hard representation switch | Still hard; separate follow-up |
| Grass filtered triangles to horizon triangles, about 70 m | Hard batch switch | Still hard; separate follow-up |
| Ferns/flowers to filtered proxies, about 28 m; stones about 32 m | Hard representation switch | Still hard; separate follow-up |
| First appearance of uploaded instances | Existing 0.65-second fade | Unchanged |
| Outer visibility | Existing final 32 m distance fade | Unchanged |
| Shadow casting | Separate hard native cutoff: grass 24 m, others 48 m, plus 4 m guard, measured against 32 m owner bounds | Unchanged; geometric fade checks do not prove shadow continuity |

This inventory qualifies ground cover. A source audit also finds that trees already
have timed LOD and shadow transitions (default 0.28 seconds in
`addons/vegetation/forest.gd`), while large boulders already use complementary
detail/horizon coverage (`boulder_fracture.gdshader`, 72–104 scaled projection
units). Those are different owners; their presence in code is not a new visual
qualification. Buildings are outside this vegetation investigation.

## Causes and controls

The fixed-population lab keeps 144 objects in the same 16 m draw partitions.
Wind/time are frozen, shadows are off and population never changes. Normal LOD,
fixed-before, fixed-after and disabled page optimization are compared at identical
camera transforms. Every source repeat is pixel-exact. Disabling the optimization
produces identical pixels in every completed tested sequence; it is not the cause
of these jumps. The grouped authored geometry switches are sufficient to reproduce
them without streaming or births.

Selected boundary events measure change in the strip's summed absolute RGB
contrast against the no-cover control. These are not whole-frame brightness
changes or a universal flicker score:

| Event | Snapshot change | Fixed after control | Candidate change |
| --- | ---: | ---: | ---: |
| Fern first boundary | +25.19% | +1.65% | +0.76% |
| Low bush first boundary | +32.18% | +1.73% | +1.73% |
| White flower first boundary | +19.28% | -0.76% | -0.76% |
| Stone first boundary | +7.89% | +3.27% | +3.49% |
| Dry twig first boundary | +40.41% | +2.10% | +2.10% |
| Woody bush first boundary | +31.42% | +2.71% | +2.71% |
| Low bush outer boundary | +1.52% | +0.77% | +0.77% |

Other events and their less favorable ordinary rasterization changes remain in
the structured evidence. The new fade does not remove ordinary motion-induced
pixel variation. The initial grass-filter/horizon audit showed approximately
-2.42%/-3.35% contrast steps at its selected boundaries; the existing distant
representations still need a separate efficient transition experiment.

## Implementation and cost

`opaque_lod_fade.gd` builds adjacent-tier index buffers once during startup.
The fragment shader uses complementary opaque coverage, with fully inactive
geometry collapsed. Each original LOD cutoff still retires the previous tier;
the transition finishes before that cutoff. There is no added texture, draw
pass, transparent sorting, history buffer or CPU update per plant. Extra adjacent
geometry is submitted in the existing draws, so the implementation is not free.
Material projection uniforms update only when the projection/resolution metric
changes. Other assets compile the feature out. Original lighting expressions,
near vertices, materials, wind and the grass-specific fade are retained.

Lab nearby endpoint images match exactly for fern, stone, white flower, low bush,
dry twig and woody bush cases. Golden/violet flowers share the flower authoring
path but do not have separate isolated color-specific sweeps in this iteration.
Their materials are included in the real-scene comparison.

Real-scene comparison `20261128T002409423934Z` passes all assertions, exact nearby
pixels, exact source repeat and source-save preservation. Mean viewport brightness
changes by **-0.01088%**. Three interleaved ABBA GPU groups measure median increments
**+0.137/-0.0715/+0.0025 ms**, p95 **+0.081/-0.105/-0.010 ms**. Draw pages,
shadow pages and instance transform bytes remain unchanged. This is a frozen
local scene (216 forest owners), not a complete-world performance guarantee.
The image was visually inspected. The separate physical full-forest run below
passes; human moving review remains required.

## Evidence and retained failures

- Initial baseline audit: `20261128T001456897900Z`; cold-retained with its
  `homestead.archive.json`, including lossless packets, raw hashes and analysis.
- First opaque candidate: `20261128T001829198742Z`.
- Later opaque tiers and remaining shrub/twig near tiers: `20261128T002253763721Z`.
- Real-scene comparison: `20261128T002409423934Z`, pinned for human review.
- `20261128T001014936068Z` exceeded its packet cap. It is not a passing comparison.
- `20261128T001228641962Z` used an obsolete LOD-introspection call from an older
  repository test, and also exhausted capture capacity. Its controls are invalid.
  The corrected driver reads the installed engine's RenderingServer surface
  records and decodes the declared index width. It retains hashes for each raw
  lossless strip and enforces completed controls before analysis.

Physical run `20261128T002911081900Z` completed 280.25 m with every physics
sample grounded, 192 raw frames, 30 changed-species boundary crossings, visible
fade-band instances in six species, and exact nearby parity. Its receipt **fails**
because the old approach gate demanded an unchanged stone-to-proxy crossing.
The cover-specific gate now requires at least four changed species and both first
and later opaque transitions; the old stone gate remains for stone tests. This is
a corrected scope check, not a claim that the failed receipt passed. The raw
reference is pinned. Its post-run archive attempt also hit the unchanged archive
limit and retained the source evidence. A corrected physical run subsequently passed, as recorded below.

No native build, export, new save or storage-budget increase is used. An old
23,057,614-byte runtime frame trace and a 12,764,989-byte completed terrain campaign
were cold-retained losslessly with hash-verifying manifests to admit the checks:
`reports/runtime_performance/20261109T072428340063Z_first_playtest_uncapped/frames.archive.json`
and `reports/terrain_edit_campaign/endurance_4800_initial.archive.json`. Their full
samples remain restorable; sibling comparisons, summaries and saves are retained.

## Normal moving gameplay

Corrected run `20261128T004314645305Z` **passes**: 280.342 m of physical movement,
3,058/3,058 grounded physics ticks, no invalid gameplay frames, all 1,024 forest
owners ready, live actors and normal streaming. Its 192 consecutive 1080p frames
match the independent raw-pixel analyzer hashes. Capture spans 4.139 seconds
(median interval 21 ms, p95 30 ms). The movie is encoded at 60 fps for review;
that encoding rate is not measured gameplay FPS.

It witnesses 33 opaque handoffs across five changed species, visible fade-band
plants in six species, and five existing grass near-boundary crossings. Nearby
pixels still match exactly after the walk; the bad-camera negative control
changes pixels and exact restoration recovers the baseline. Runtime/source-save
checks pass. The driver holds movement keys with normal collision and uses
scripted yaw; it does not replay positions during measurement.

Three moving ABBA groups give median GPU deltas +0.0565/+0.2675/-0.1315 ms,
p95 -0.056/+0.453/-0.098 ms. Movement advances through different positions, so
these are contextual observations; use the frozen paired scene above for the
isolated increment. No other engine process was observed. The capture itself
warned at 5.82 GiB RAM while retaining raw images; this is not a production RAM
claim. Eight launcher unit checks also pass.

[Walking movie](../../reports/checks/20261128T004314645305Z/gameplay.mp4),
[native-size frame-pair review](../../reports/checks/20261128T004314645305Z/motion-review.png),
and [lossless walking context](../../reports/checks/20261128T004314645305Z/walking.png).
The frame pairs show samples 33/34 and 159/160 around witnessed near handoffs;
only the movie/contact sheet are compressed. These images were inspected; they
do not establish universal seamlessness. The run is pinned for human review.
[Structured evidence](remaining-handoff-evidence.json) preserves every selected
lab event, controls, cost groups, runtime hashes and failures.

The capture also observes 31 grouped shadow enable events. Their visual
contribution needs a same-camera caster-only control. The filtered grass/fern/
flower/stone representation changes and grass horizon change need their own
coordinated opaque/transparent overlap experiment, with brightness, shadow and
GPU gates. They are not covered by this candidate.

An intervening run `20261128T003643186309Z` never launched: interrupted archive
output exceeded the limit. Recovery verified two unreferenced chunks against
unchanged live captures before removing only those duplicate bytes (1,069,592
bytes); the recovery receipt is in that run. All original evidence remains.
No storage limit was raised. The passing walk, video and review total under the
admitted 12 MiB. After measurement, unchanged lines in `ground_cover.gd` and the
shared launcher regained their original line endings; normalized executable text
is identical. Before/after hashes are recorded in the structured evidence.

Return gates: human judgment of grain and silhouette, followed by separate
proxy/horizon and shadow experiments before universal closure. The new opaque
fade targets the normal ground-cover configurations used in the lab/gameplay;
other authoring configurations are not qualified by these captures.
**Do not commit this follow-up without the user's validation.**

Original AI-assisted code and investigation for this repository: code 0BSD,
documentation/data CC0-1.0. No external code or assets imported.

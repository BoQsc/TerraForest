<!-- SPDX-License-Identifier: CC0-1.0 -->
# Far proxies, grass horizon and grouped shadows — 2026-11-28

**Human acceptance — 2026-11-28:** The user verified the latest source after checking
standing still and walking, and authorized commit/push. Milestone:
`playtest/vegetation-fades-2026-11-28`. This accepts the current fade/projection
snapshot, not universal seamlessness or the earlier GPU-tail target. Historical
failed and rejected controls below remain evidence. Shared DLLs are excluded;
restoring the native page-overlap change requires rebuilding the structures addon.


**Human review update:** [Nearby gray/shadow bands while walking](SHADOW_BANDS.md) were reported after this candidate launched. The far-proxy projection cause is reproduced and the corrected guard passes exact nearby comparisons. Physical walking passes 189 m with 192 verified frames; human review subsequently accepted the corrected source; the earlier engineering passes below did not cover this fault.

**Status: scoped lab and physical gameplay checks pass; corrected latest source human-verified on 2026-11-28.** This continues
the [opaque-tier experiment](REMAINING_HANDOFFS.md), not universal seamlessness.
The comparison baseline includes that uncommitted opaque fade. The Git checkpoint
is still `84d60efd`; comparisons here are not against its older grass-only fade.

## Causes and changes

The earlier per-plant masks did not cover three independent paths:

| Path | Proven discontinuity | Candidate |
| --- | --- | --- |
| Opaque grass/fern/flower/stone to filtered proxy | Engine index selection switches a whole 16 m batch. The native one-surface optimization also excluded the incoming representation until the nearest batch point reached the cutoff. | Complementary per-root screen masks finish before the engine cutoff. Native near-only selection now uses the **farthest** batch point at fade start; far-only retirement keeps the original nearest-point end and shadow guard. |
| Filtered grass to horizon grass | Eight analytic blade proxies become three at one batch threshold. | Both existing sets share the filtered surface during the overlap. Their existing analytic alpha is weighted per root; zero-weight vertices skip projection and collapse. The old horizon index switch then removes inactive geometry. |
| Small-cover shadows | Native distance policy turns every caster in a page on/off together. | Fade only shadow-pass coverage over 16–24 m for grass and 36–48 m for other small cover. Whole-page shadow retirement remains enabled beyond the fade. |

At the tested 1080p / 75-degree view, opaque-to-proxy bands are approximately
26.0–31.5 m for grass/stones and 22.5–28.0 m for ferns/flowers. Grass horizon
overlap is approximately 61.9–70.2 m. Representation distances follow the existing
projection/LOD metric; shadow distances are horizontal metres. Exact nearby
geometry and material lighting are retained. This is a distance-driven blend;
camera movement advances it without a random temporal mask or new history buffer.

The opaque/proxy masks are complementary rather than multiplying both surfaces'
opacity by the blend: that would expose extra terrain midway through the change.
The original filtered proxy shading, depth, authored colors, near grass detail,
wind, instance identities and outer visibility endpoint are retained. Distant
shadow strength intentionally changes inside its stated fade band.

`IN_SHADOW_PASS` keeps shadow attenuation out of the color material. The installed
Godot 4.7.2 renderer compiled and exercised this path; the builtin is documented in
the [official spatial-shader reference](https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/spatial_shader.html).
No external implementation was copied.

## Causal lab

Representation run `20261128T075630530026Z` passes five fixed-population suites:
grass proxy, grass horizon, fern proxy, white-flower proxy and stone proxy.
Each keeps 144 plants resident, freezes wind/time, repeats identical camera
positions, and compares source, fixed-before, fixed-after, native-optimization-off
and candidate images against no-cover images. Source repeats and nearby endpoints
match exactly. Disabling native surface selection leaves source pixels identical:
the engine's grouped geometry switch itself is sufficient to cause the jump.

At old grass proxy and horizon batch boundaries, candidate contrast changes match
the already-switched control. For example, the grass horizon source changes
-1.119% while normal movement with the fixed incoming representation changes
+2.764%; candidate also changes +2.764%. The excess discontinuity is removed at
that boundary. A flower boundary changes -8.014% in source versus +7.291% fixed
incoming and +7.277% candidate. These are vegetation-contrast steps relative to
no-cover, **not whole-frame brightness or a universal flicker score**. All selected
events, controls and packet hashes are retained in the structured evidence.

Shadow run `20261128T075817434927Z` separately enables the sun and holds color
geometry fixed. For both grass and fern, candidate with native cutoff enabled is
**pixel-identical at all 13 poses** to candidate with all native casters retained.
The source gains two caster pages at the crossing. The candidate has already faded
their contribution, so removing those pages changes no pixels. This isolates the
group cutoff; it does not eliminate shadow-map sampling/cascade changes in general.

[Representation comparison](../../reports/checks/20261128T075630530026Z/handoff_review.png)
shows source, candidate and fixed-incoming rows, with before/after columns.
[Shadow context](../../reports/checks/20261128T075817434927Z/grass_shadow.png)
shows the controlled grass population. Images were inspected. The two qualifying
lab runs remain ready under the existing two-copy retention policy.

## Integrated appearance and cost

Full-scene run `20261128T080012838762Z` passes 522 checks, exact nearby pixels,
exact source repeat and source-save preservation. Its 69,511 ground-cover objects,
draw pages, shadow pages and instance-buffer bytes remain unchanged. The frozen
local world has 216 forest owners / 910 trees; the separate walk exercises the
full forest. Mean viewport brightness changes **-0.01337%**. The extreme-impulse
detector is essentially unchanged and includes legitimate UI/edges; it does not
prove that all flicker is absent.

Three interleaved ABBA groups, 240 GPU samples per case/group, measure median
increments **+0.328 / +0.5125 / +0.6205 ms**, p95 **+0.816 / +1.168 / +0.786 ms**.
Readback/encoding are excluded. No other engine process was observed, which is
not an OS-wide GPU exclusivity guarantee. The overlap has a measurable cost and
does **not** close the earlier detail-tail target. It retains existing draw owners
and textures, uses startup-built index buffers and shared shaders, and adds no
per-instance CPU updates. More pages may temporarily submit both surfaces; far
pages still retire the outgoing surface. No density reduction hides the cost.

[Integrated candidate](../../reports/checks/20261128T080012838762Z/near_fade_24.png)
was visually inspected. This scene preserves nearby appearance and does not show
the earlier brightness washout. The capture warned at 4.64 GiB RAM while retaining
review data; that is not a production-memory measurement.

## Physical gameplay and acceptance

Run `20261128T081702404738Z` **passes**: 280.067 m, all 3,055 physics ticks grounded,
all 1,024 forest owners ready / 8,461 trees, live actors and normal streaming.
The 192 consecutive full-viewport frames match the independent raw-pixel analyzer
hashes. It witnesses 21 proxy crossings, 12 grass-horizon crossings and 75 grouped
shadow toggles. Every observed toggle has exactly zero remaining shadow coverage
across every affected root. Visible grass occupies all three fade bands throughout
all 192 frames. Nearby pixels match exactly after walking and after exact local
camera restoration; the bad-camera negative control changes pixels as expected.
Runtime hashes and canonical save bytes remain unchanged.

The driver uses normal held movement keys and scripted yaw. Test-only per-root
witnesses and captures are excluded from the separate moving GPU windows. Three
ABBA groups give median deltas +0.161 / +0.601 / +0.502 ms and p95 +1.346 / +3.717 /
+1.302 ms. These moving windows traverse different positions and populations;
use the frozen scene above for the isolated increment. The tails remain a concern,
not a performance pass. No other engine process was observed. Capturing the
images warned at 5.93 GiB RAM. Capture spans 5.040 s, with median 25 ms / p95 37 ms
between samples; the 60 fps movie encoding does not measure gameplay FPS.

[Walking movie](../../reports/checks/20261128T081702404738Z/gameplay.mp4),
[frame pairs around witnessed transitions](../../reports/checks/20261128T081702404738Z/motion-review.jpg),
and [lossless walking context](../../reports/checks/20261128T081702404738Z/walking.png).
The inspected contact sheet uses native-size crops from compressed movie frames
103/104 (proxy), 95/96 (horizon) and 140/141 (shadow); it is a visual aid, not raw
pixel proof. The successful walk and review stay below the admitted 12 MiB and
are pinned for human review. Nine launcher unit checks pass.

[Structured evidence](far-handoff-evidence.json) retains raw frame hashes,
observed transitions, exact-control results, cost groups, source/native hashes,
failed attempts and retention receipts.

Human approval remains required for grain, silhouette, horizon density and shadow
fade appearance. Other FOVs/resolutions, steep views, other lighting, fast travel,
teleports, bulk edits, tree/boulder transitions and the earlier GPU-tail target
are not universally qualified. Return to any visible remaining boundary with the
same-camera fixed-representation control and a physical reproduction. **Do not
commit this follow-up until the user validates it.**

## Reproduction, failures and retention

Use the admitted launchers with other gameplay/render jobs idle:

```text
python tools/run_godot_check.py vegetation_final_handoffs --isolated-render --timeout 300 --require "VEGETATION_HANDOFFS failures=0"
python tools/run_godot_check.py vegetation_final_handoffs --isolated-render --timeout 300 --require "VEGETATION_HANDOFFS failures=0" -- --shadow-suite
python tools/run_vegetation_fullframe.py --seamless
python tools/run_vegetation_fullframe.py --gameplay --approach-review --seamless
```

The first smoke run, `20261128T075158733757Z`, failed shader compilation because
Godot forbids returning from `vertex`; inactive geometry now uses an if/else.
`20261128T075405542691Z` compiled but its endpoint control supplied different
projection metrics to source/candidate. Both now receive the same disabled-LOD
metric for that isolated endpoint, with real-projection nearby parity checked
separately in the integrated scene. Neither failed receipt is a passing result.

First physical run `20261128T081046903558Z` completes 274.841 m with all 2,998
physics ticks grounded, 192 raw frames, exact nearby parity, all three transition
bands and 77 observed shadow toggles at zero remaining coverage. It nevertheless
**fails five assertions**: they compared the production shader object with the
original resource, although the production material now owns a fade-enabled
variant. The corrected checks compare the entire expected shader code, retain
runtime material ownership, and verify live clock/projection updates. The failed
receipt remains pinned and is not promoted to a pass.

Post-run archival also reached the existing archive limit. Recovery verified five
unpublished chunks against unchanged live captures and every published local
archive manifest, then removed only those duplicate chunks (4,216,313 bytes).
`20261128T081046903558Z/archive_recovery.json` records the proof. Original captures,
published archives and saves remain intact. Pinning that failed moving reference
keeps it outside automatic retirement while its correction is reviewed.

The native overlap change was rebuilt in both existing structures debug/release
DLLs, without an export or isolated source copy. Only `static_surface_lod.cpp`
compiled in the final builds; binaries also contain existing unrelated checkout
work. Tests use debug. Source restoration requires rebuilding the native library.
Unchanged lines regained original line endings before the final walk; normalized
executable text is identical to the earlier lab/full-scene checks. The exact
before/after hashes are in
`reports/artifact_retention/vegetation_final_handoff_eol_20261128.json`.

No storage budget increased and no save/evidence was discarded. Losslessly
recompressing verified existing archive chunks freed 4,083,438 bytes; receipt:
`reports/artifact_retention/vegetation_fade_recompression_20261128.json`.
Completed creation fixtures from two older, later-failed location-baseline runs
were cold-retained using already-present hash-verified chunks, freeing 47,207,220
loose bytes with zero new compressed payload. Their failures/logs and the latest
passing fixtures remain ready; restoration manifests are
`reports/location_baseline/20261102T174105330668Z/bulk.archive.json` and
`reports/location_baseline/20261102T181359468541Z/bulk.archive.json`.
Full-scene and successful moving captures are pinned for human review; release
pins only after review and verified cold retention.

Original AI-assisted investigation and implementation for this repository:
code 0BSD, documentation/data CC0-1.0. No external code or assets imported.

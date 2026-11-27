<!-- SPDX-License-Identifier: CC0-1.0 -->
# ★ Vegetation flicker: investigation lessons

**Flicker correction confirmed in human source playtest, 2026-11-27.**
Starred at the user's request. Earlier results were rejected; the later full-frame
correction was accepted in the observed playtest. Stone pop-ins, distance/LOD
transitions, broader coverage and the separate GPU-tail target remain open.

[Canonical issue and current status](README.md) ·
[Notable investigations](../notable/README.md) · [Detailed lab history](LAB.md)

## Why this case is worth remembering

Distant grass looked like flickering dark and pale pixels rather than vegetation.
Distance suggested LOD or subpixel coverage, and those mechanisms did contribute
in the tested scenes. A separate fault remained in the shared vegetation shader:
an edge-shading expression could leave its intended domain and produce negative
colour values on thin triangles. Changing only the far representation left that
shared path in use elsewhere in the frame.

The mistake in validation was equally important: improvements in selected sample
points and small motion crops were treated as stronger evidence than they were.
The user's full-frame observations contradicted that implied success. Earlier
brightness adjustments also changed the appearance without establishing the cause.

## What distinguished the causes

| Question | Evidence and its limit |
| --- | --- |
| Was LOD switching the entire problem? | Fixed-LOD and other controls still showed moving residuals. Coverage mattered, but did not explain every visible defect. See the [lab](LAB.md). |
| Could shading itself generate black flashes? | A diagnostic shader marked negative colour values across the entire viewport. Matched camera/time interventions changed the suspect expressions while preserving geometry and lighting. |
| Was bounding the edge term enough? | It removed almost all negative markers, but left up to four in the tested views. Bounding the interpolated root/canopy shading removed those remaining markers. |
| Did the comparison reproduce the same frame? | The baseline repeat was pixel-identical. Population, draw pages and the source save were checked for preservation. |
| Were all dark or white pixels evidence of vegetation failure? | A control with ground cover hidden distinguished scene/UI pixels from cover-related extreme impulses. The yellow diagnostic detector also matched background colours; its count alone could not prove excessive vegetation albedo. |
| Did the source correction run during actual movement? | Physical gameplay retained collision, live actors and streaming, with 192 consecutive full-viewport raw frame hashes independently matched. The encoded review movie is lossy; measurements use raw pixels. |

The recorded [full-frame lab evidence](fullframe-evidence.json) covers 337 raw
1920×1080 frames across interventions, including 48 views per principal case.
Up to 1,983 negative-colour markers became zero in the corrected case. In one
matched elevated frame, additional extreme dark/white impulses relative to hidden
ground cover fell from 328/1 to 0/0. Those numbers describe the tested views and
detector; they do not establish that every form of temporal shimmer is gone.

The [physical gameplay evidence](fullframe-gameplay-evidence.json) records about
194 metres of travel and a 3.2-second continuous full-resolution recording. The
recording is a sample of that route, not footage of the entire journey.

## Correction and transferable lessons

The current [shared shader](../../addons/world_ecosystem/woodland.gdshader) bounds
the edge, root-shading and canopy-shading calculations to their authored ranges.
It preserves valid-domain shading, geometry, textures, lighting and LOD distances.
It adds no textures, draw passes, temporal buffers or runtime allocations. The
earlier GPU-tail requirement remains open; no paired performance win is claimed
for this correction.

- A defect that becomes visible with distance can still originate in a shader
  shared with nearby geometry. Trace every active rendering path.
- Separate coverage, shading, LOD selection and brightness with controlled
  interventions before choosing a correction.
- Instrument invalid intermediate values rather than hiding their output with
  a global brightness adjustment.
- Match the test's field of view and motion to the user's complaint. Keep exact
  repeat controls and inspect the whole frame as well as useful local samples.
- Validate the diagnostic itself against unchanged/background controls. A marker
  colour can occur naturally, and a detector can miss other kinds of flicker.
- Preserve failed hypotheses and rejected visuals. Record which claim each
  measurement supports, and keep engineering checks separate from human approval.

## Human validation and remaining work

On 2026-11-27 the user played the latest source in Homestead Valley and said,
“Yeah you seem to have solved it”. The corrected shader hash, automated evidence
and snapshot limitations are recorded in the [canonical issue](README.md#human-playtest-and-source-snapshot--2026-11-27).

The same session identified small-stone pop-ins farther away while approaching.
Their cause and regression status are not established. The requested next effect
is a subtle LOD/distance fade, with nearby appearance and brightness preserved.
The user requested a source snapshot before these further changes. Native binaries
are shared with unrelated work and require rebuilding when restoring this snapshot.

To guard this correction, repeat the full-frame counterfactual lab with its exact
baseline repeat, invalid-colour witnesses and no-cover control, then physical
source gameplay with independently verified raw frame hashes. Test any transition
change separately for nearby equality, terrain tone and paired GPU cost before
human review. The earlier cost-tail miss remains open; a visual approval does not
close it or establish a universal result across scenes and devices.

The star remains visible so future work can learn from both the shader fault and
the earlier validation failures.

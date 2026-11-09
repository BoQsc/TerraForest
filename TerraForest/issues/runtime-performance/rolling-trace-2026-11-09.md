# Fresh default world and rolling-trace investigation

Status: Recorder implemented; several blocking calls identified. Stable 60 FPS
with headroom remains unqualified. No performance optimization or visual reduction
is installed by this change. User motion/visual review remains open.

## Fresh world first

Generated through the unchanged browser's Generate & play path before adding
the recorder: **Frontier expedition**, seed **1703**, generator **29**, recipe
version **3**. Options: biome 0, three settlements × two districts, network 2,
trails 2, road grid 3, material veins and introduction enabled. This is the latest
default; older tests asserting Connected countryside are not current-default
evidence. Preparation records **51 buildings, 7,007 earthwork edits and 12 lakes**.

World: `StartupBench_FPS_20261109T073252`; plan digest
`8c8a80efba88a7f51c51ece614ec42ddd8c3546d60c6e0a045dace8c5a7d102c`.
First readiness: **74.467 s**; control after fly-in/waking: **82.497 s**.
A twenty-second post-control observation catches **99.426 ms** maximum frame,
but that old startup observer disables world physics and takes diagnostic
screenshots. It establishes an arrival symptom, not an isolated gameplay cause.

Later observations use the real writable session at its saved upstairs spawn,
approximately **(1058.5, 61, 325)**, with no teleport to the old road route. The
arrival screenshot was inspected: brick upstairs room, windows, lamp, held tool,
trader objective and live forest HUD. It is scene-content evidence, not approval
of motion. The fresh reference is retained; matched controls use new owned copies
with equal source-root hashes and copied optional presentation sidecars.

Hardware: i5-12450H, RTX 4050 Laptop, Godot 4.7.2 Steam/Vulkan Forward+, 1080p,
Legion Quiet Mode unchanged. Source runs are scripted/offscreen with focus admitted
for the test, not a human foreground smoothness assessment. Existing OS/shader
caches remain; no forced cold-cache claim.
Instrumentation was extended between runs; manifests retain dirty-worktree state.
Do not treat every exploratory trace as the same instrumented source revision.

## Concrete causes and controls

| Path | Direct evidence | What needs fixing |
| --- | --- | --- |
| First-person depth-correction activation | Matched normal arrival: **223.587 ms** total, **160.549 ms** draw interval, **8** new pipeline specializations. Test-only depth protection disabled: **72.097 ms** arrival, **7.077 ms** draw interval, **0** new specializations. Other blocking costs remain. | Prepare/warm the required depth/material variants before player control. Preserve the accepted native-depth behavior, clipping and lighting; disabling it is a diagnostic, not the fix. |
| Existing arrival photograph check | `arrival_photograph.request()` calls `Pictures.read_image(..., Vector2i(1,1))`: it decodes a full PNG and resizes it merely to determine presence. Measured **34.7–46.9 ms** in repeated source runs; **43.2 ms** remains in the depth-disabled control. | Carry validated availability from the browser or validate off-thread/cache it. Preserve corrupt/missing-picture fallback and first-photo behavior. A synchronous full decode at play release is unnecessary. |
| First zombie admission | One `add_child(zombie)` runs the complete synchronous initialization. A matched sample spends **190.293 ms** in population readiness; new-zombie breakdown includes **132.093 ms** scene setup, **43.374 ms** anatomy, **11.336 ms** hit areas. Another sample reaches **264.441 ms** population readiness. | Stage/prewarm the scene and immutable anatomy/shape data or prepare a bounded pool before control. One-body-per-frame admission alone cannot bound a single 190 ms body. This is admission work, not evidence that navigation search causes this stall. |
| Distant parked-vehicle prototype | Readiness **73.891 ms**, of which **72.790 ms** is `parked_render_parts`. The path validates the baked prototype receipt by hashing source files and loads the mesh synchronously on first use. Other repeats show **60.8–84.1 ms** total. | Validate/load the immutable prototype through startup resource preparation rather than this final main-thread readiness call. Keep receipt/provenance validation; do not bypass it. |
| Autosave snapshot capture | Repeated capped frames contain **14.6–16.1 ms** save capture and reach **31.7–34.1 ms** total. An uncapped outlier spends **38.490 ms** in save capture: **24.940 ms** water and **8.396 ms** structures within **38.355 ms** component capture. | Bound snapshot capture itself. Water's native frozen-snapshot path still walks/copies region state on the calling thread; deferred encoding/disk I/O does not remove that work. Preserve atomic revision/epoch consistency and persistence barriers. |

The first-person control is one matched pair, not a lockstep statistically powered
benchmark. It strongly localizes the arrival render spike to activation of that
path; it does not identify every engine pipeline variant or guarantee that every
future shader stall is removed by warming those particular variants.

## Remaining frame and headroom costs

- A later capped **55.995 ms** frame has **43.199 ms** in the drawing interval,
  reported GPU **10.671 ms**, no new pipeline specializations and only about
  **25.8 million** main-thread cycles (similar to adjacent normal frames). That
  is different from the CPU-heavy arrival event. The exact engine/driver/OS wait
  is still unattributed. Windows scheduling/presentation stack evidence is needed;
  WPR is installed, but this process is not elevated. No privileged recording was
  started or other recording disturbed.
- The uncapped run still catches **176.407 ms** during later play, followed by
  **8 physics ticks** in the next **111.931 ms** frame. Catch-up amplifies an
  initial stall; it must not be mistaken for the original cause. These uncapped
  observations are not a matched cap-only comparison: earlier drivers turned
  per frame and saved their final yaw. The later matched driver uses elapsed-time
  turning and restores yaw; the earlier traces remain marked exploratory.
- The matched normal trace reports approximately **5,000 global draw calls**;
  GPU mean **12.99 ms**, p99 **15.21 ms**, maximum **15.92 ms** in retained
  gameplay windows. Root timers may lag and these are triggered windows, not an
  unbiased whole-session GPU distribution. Nevertheless, the rendering margin in
  this room/world is much smaller than the earlier road fixture suggested.
  Attribute building/prop/forest/shadow passes before choosing batching, culling,
  LOD or shadow-work changes; do not silently lower visual settings.
- Terrain publication, collision attachment, cover callbacks and NPC admission
  continue to consume millisecond bursts. Their nested timers overlap. None of
  the listed maxima can be summed into a fictional single-frame budget.

Use **16.67 ms** as the hard 60 FPS interval budget. A useful proposed engineering
target is no more than **12 ms** CPU/GPU critical-path work in representative
steady travel, leaving about 4.7 ms of margin; this is a proposal, not a newly
approved project acceptance gate. Tail latency and rare stalls must be qualified
separately. Average FPS is insufficient.

## Recorder delivered and verification

[Usage and interpretation](../../docs/FRAME_TRACE.md). Opt-in normal gameplay,
automatic isolated/sustained triggers, manual marker, bounded pre/post history,
off-thread JSON/file output and eight rotating files. Save components, new-zombie
initialization, startup readiness subcalls, vehicle prototype stages, thread work,
shader counters and writer activity are captured.

Matched continuous observation samples (milliseconds, p99 / maximum):

| Phase | Tracing off | Tracing on |
| --- | ---: | ---: |
| Arrival idle | 27.294 / 82.035 | 35.783 / 43.388 |
| Time-based turning | 24.803 / 30.303 | 20.338 / 32.905 |
| Settled idle | 20.274 / 20.929 | 19.888 / 26.815 |

Neither repetition is a performance pass. Variation prevents claiming zero
observer cost. The on-run recorder's measured draw-end callback mean is
**0.129 ms**, p99 **0.229 ms**, maximum **0.997 ms**; these exclude other added
probe/stage overhead. Uncapped descheduling produced larger callback elapsed
outliers. Worker activity is now recorded for further correlation. Turn/idle
measurements above come from the continuous driver, not duplicated trigger files.

Checks: bounded ring/history, post frames, immutable writer snapshots, deferred
cooldown capture, sustained sub-20-ms cadence, file replacement/rotation, explicit
marker and G non-interception pass. Three Python analyzer tests cover overlapping
windows, missing counter adjacency and inconsistent frame rejection. Existing
photograph behavior, vehicle scene loading and loading progress UI checks pass.
Godot generated the new resource UIDs. No native code or dependency was added.

Retained non-passes: first recorder draft had three GDScript type-inference errors
(corrected before integrated runs); the matched trace-off control completed its
observations but reports one ObjectDB leak at shutdown, so its launcher result
remains failed. Trace-on/control-depth runs close cleanly. One check launch raced
editor DLL reload and failed before running; after import completion its retry
passes. Export initially stopped for the stale startup dependency index, then
for missing imported audio-cache samples. Index regeneration passes. Full import,
then removal of stale cache metadata for 211 missing audio outputs and a reimport,
identify the underlying error: the original Kaino WAVs are in a WAVE format the
Godot importer rejects. No audio source/format or export scope was changed.
Required building/notice/index gates pass, but the package refresh remains blocked;
the previous installed PCK is retained. Normal source gameplay can trace now;
packaged parity requires repairing that separate audio import boundary and a fresh
packaged trace. These failures are retained, not rewritten as passes.

## Resume and evidence

Implementation follow-up: [world/player foundation](foundation-2026-11-09.md)
now records the controlled fixes, binary debris bake, persistence checks and
repaired audio export boundary. The failure descriptions above are retained as
historical evidence; they do not describe the latest delivery state.

Prioritize first-person warmup and arrival PNG availability, then staged admission/
prototype preparation and bounded immutable save capture. Return to the independent
presentation wait with a foreground scheduling trace. Validate every fix with
matched normal visuals, the fresh default recipe, new/reopened worlds, strict tail
timings and persistence/interaction regressions. Dense travel, combat, caves/water
edits, physical driving, long sessions and weaker hardware remain unqualified.

[Committed measurements, hashes and source links](rolling-trace-2026-11-09.json).
Local raw runs remain under `reports/stall_investigation/`: generation
`20261109T073252Z`; first trace `20261109T073945Z_rolling`; fine stages
`20261109T074311Z_detail`; exploratory uncapped `20261109T074559Z_uncapped`;
matched off/on `20261109T074848Z_control_matched` /
`20261109T075110Z_trace_matched`; depth control
`20261109T075735Z_depth_control`. Reports and screenshots stay out of imports and
exports. They contain project-rendered existing assets, not newly imported art.

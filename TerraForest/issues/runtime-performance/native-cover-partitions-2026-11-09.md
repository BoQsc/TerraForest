# Native cover draw partitions

Status: implemented; GPU savings established in the sampled default world.
Stable 60 FPS, general visual acceptance and pursuit latency remain open.
Updated 2026-11-09. New implementation/tests are original 0BSD code; no assets,
dependencies, graphics preferences or world-generation recipe were changed.
Implementation: `d71ccc57`; trace/outdoor driver: `746d28f3`; corrected harvest
fixture: `d805a6d0`. Captures retain the corresponding pre-commit source hashes.
[Machine-readable evidence](native-cover-partitions-2026-11-09.json) retains
run/native/package hashes, complete phase frame distributions, trace metrics,
resource counters and unresolved tails. The [earlier prototype](cover-render-partitions-2026-11-09.md)
and its failures remain evidence for the original diagnosis.

## Change and limits

The native static collection now supports spatial draw partitions independently
of its authoritative 32 m groups. Ground cover opts into 16 m subcells. A linear
derived index replaces the prototype's second renderer; canonical transforms,
IDs, snapshots, collision groups, density, mesh/material assets, shadow policy
and distances remain unchanged. Conservative per-page bounds include 0.05 m of
local shader bend/wind before instance scaling and rotation.

Visible identities and fade ages survive subcell moves and removals in the same
scene call. Pending additions keep normal byte/upload admission. A separate fix
keeps a partial visible page when its pending growth cannot fit the remaining
budget. New layout storage joins collection retirement. The
[API contract](../../docs/STATIC_RENDER_STREAMING.md) distinguishes logical
admission from physical draw-node limits and estimated memory from measured
VRAM. This does not impose a total frame deadline: immediate edits and optional
partitioned archive publication can still scale with affected records.

## Integrated performance and visuals

Serial source controls use owned clones of the latest default generator-29,
seed-1703 fixture at 1920×1080, normal 60 FPS cap/VSync and quality. The first
stationary comparison retains exactly **74,320** resident cover instances in
both modes. Physical pages change **667 → 1,891**; the new derived layout
estimate is **118,152 bytes**. Arrival GPU medians change **12.456 → 7.459 ms**.
Sampled peak dedicated GPU allocation is approximately **1.475 GB** in both
runs; process private commit remains approximately **3.86–3.88 GB**.
The reverse-order repeat measures **7.878 ms** with partitions, then
**13.632 ms** with the legacy layout, again with 74,320 instances. These four
serial arrival samples support roughly **40–42% less GPU time** in this view;
they do not demonstrate a proportional frame-rate improvement.

The first outdoor pair uses the same three camera poses across 16 m of travel.
Stationary GPU medians change **7.755 → 5.337 ms** at the first view and
**7.870 → 5.464 ms** at the last. Live wind and actors continue. The partitioned
run's player is later killed and respawns; its later turning/idle population is
therefore not a matched outdoor density comparison. The camera sweep holds
height with fly mode and does not qualify physical walking or driving.

Native cover processing during the sweep increases: its captured p99 changes
**1.142 → 2.292 ms**, with maxima **1.258 → 3.260 ms**. GPU savings come with
additional selection/upload work and draw nodes. The rolling trace now records
each collection's native selection, cleanup and upload phases so these costs
remain visible. Stationary native processing is only a few microseconds.

The [subsequent contiguous-selection change](render-stage-attribution-2026-11-09.md#native-selection-allocation-change)
reduces allocation work without changing admission. A clean later source pair
shows active-selection median 2.058→1.699 ms, with functional and installed checks.
That limited comparison does not close this earlier travel-cost regression or
the full frame-time gate; workloads/clocks differ and broader tails remain.

Inspected source views retain near/far grass, rocks, terrain, building edges and
shadows without an obvious missing patch at the sampled boundaries. Smaller
bounds can alter automatic mesh LOD selection; this is scoped engineering
inspection, not universal visual parity or user art approval. Existing pickaxe
grip/presentation limitations are unchanged. Captioned comparisons and source
hashes are retained in the image manifest.

| Sampled view | Legacy 32 m | Native 16 m |
| --- | --- | --- |
| Start: road edge and near grass | [Legacy start](images/cover-native-legacy-0.png) | [Native start](images/cover-native-native-0.png) |
| End: dense foreground and boulder shadow | [Legacy end](images/cover-native-legacy-2.png) | [Native end](images/cover-native-native-2.png) |

[Inspected packaged end view](images/cover-native-packaged.png) retains the same
camera pose and visible cover. The matching **556,864,716-byte PCK** has SHA-256
`67cf0f244fc1b73467f1d3d246fc6f4394b95a91749df9ca7d67d10c8e220db6`.
It passes explicit gameplay save and strict shutdown. Arrival GPU median is
8.035 ms; outdoor sweep GPU median is 5.983 ms. Sweep frame p99 is 28.726 ms
and maximum 34.941 ms after the screenshot boundary correction. Arrival p99
is 35.922 ms: this package still does not satisfy stable 60 FPS.

## Verification and retained failures

- Debug and isolated release: all six ownership/continuity/retirement/region/
  placement suites pass. The final dedicated fixture has **28 checks** including
  exact snapshots, shader-padded bounds, cross-subcell moves, preserved fade
  payloads, sparse partial-page growth, mesh replacement, full identity
  replacement, region reload and complete layout cleanup. Strict exits are clean.
- Source frame-recorder, ground stream (**171 assertions**), retirement and
  graphical fade checks pass. The trace analyzer's three unit checks pass.
- Matching package: the dedicated partition fixture passes all 28 assertions.
  After correcting its input/startup setup, the current harvest world passes
  **46 assertions**, native harvest passes **15**, and durability passes **21**.
  They verify contact timing, inventory/payment rollback, felling, persistent
  cover removal and rejection of stale duplicate rewards. All strict exits are
  clean. These checks do not replace the old fixture's unverified placement UI.
- The first native installation attempt failed because the user's normal game
  held the DLL. After the user closed it normally, installation and tests passed;
  the access-denied build log remains retained.
- `ground_cover_interaction_world` is **not green**. The first invocation omitted
  its cover options; the corrected invocation also fails legacy 81-cell/population
  and interaction assumptions, then dereferences a missing placement and times
  out. Neither result is counted as a passed gameplay gate. Modernizing that older
  fixture and verifying its replacement/placement scope remains required.
- The first current harvest invocation also fails before contact: its offscreen
  driver did not supply the captured-input state required by real attack
  admission. The fixture now waits for playable entry and supplies captured input
  only during its synchronous contact transaction, restoring it before any await.
  It exits cleanly on failed admission instead of indexing an empty transaction.

## Remaining stalls and closing evidence

The first indoor controls still have frame p99 about **28.4–28.6 ms**, despite
the GPU improvement. The legacy outdoor run also captures a **502.857 ms** idle
frame: **485.540 ms before process**, **7.638 ms draw**, reported GPU **13.232 ms**,
only **31.25 ms** main-thread CPU, eight catch-up physics steps and native planning
**9–15 µs** per step. No pipeline-count increase or active trace writer explains
it. This narrows the symptom toward a wait/scheduling interval; the exact source
is not established. The earlier 97.573/480 ms stalls remain unresolved too.

The initial outdoor driver mislabeled the interval immediately following each
screenshot readback (486–617 ms) as movement/turning. These are retained as
diagnostic contamination, not gameplay stall evidence. The driver now drains
two draw boundaries under the screenshot label and records readback duration.
The JSON excludes those identified adjacent intervals from phase statistics,
retaining their frame IDs; the independent 503 ms idle stall is not excluded.

Before full acceptance: reproduce normal foreground frame pacing and isolate
engine/OS/render waits; budget cover selection under faster travel; qualify long
walking/driving, dense edits and retirement on weaker hardware; repair the old
interaction fixture; and improve multi-floor pursuit and first-use hit-area
admission without removing gameplay checks. Dense explosive chains, long-session
leak/memory behavior and multiplayer authority/population scaling remain open.

Reproduce serially from the repository root:

```text
python TerraForest/tools/check_render_partitions.py --suite
python TerraForest/tools/check_render_partitions.py --release --suite
python TerraForest/tools/check_frame_trace_world.py --short --legacy-cover --gpu-profile --label cover_control
python TerraForest/tools/check_frame_trace_world.py --short --outdoor-cover --gpu-profile --label cover_native
python TerraForest/tools/check_frame_trace_world.py --short --outdoor-cover --save --executable --label cover_pack
```

# Object rendering and full-game walking qualification

Work requested 26 November 2026: 1,000 objects at 60 FPS while walking with
ordinary gameplay systems running. **Qualification remains open.** The earlier
stationary object-system check disabled the world physics callback and cannot
close this requirement. Native insertion speed is not a frame-rate result.

## Implementation

- Outdoor 01 version 1.0.1 reduces tiny tube-cap tessellation. The ten original
  models total 34,064 triangles instead of 111,376 (69.4% fewer). Authored sizes,
  collision boxes, materials and stable item/model identities are preserved.
- `pack_render_mesh.gd` prepares cached render meshes once during catalog setup.
  Compatible opaque surfaces share a texture array and material, with original
  RGB values, UV wrapping, texture dimensions, roughness and metallic values.
  Pixel-identical textures share a layer. Source meshes remain the authoring and
  provenance inputs; no per-frame mesh conversion or new saved representation
  is introduced. Unsupported materials/surface layouts remain intact.
- Meshes with nearly coincident surface bounds and different culling modes keep
  their original materials. This preserves the authored lamp shade's draw order.
  Glass, emissive surfaces and other unsupported properties retain their original
  materials. Across 110 models, 442 surfaces become 208.
- Godot's existing core `ImporterMesh` processor adds 735 index LOD levels while
  retaining full-detail geometry. Custom vertex shaders, skinning and existing
  LOD/shadow-mesh assets are conservatively excluded. No engine implementation
  or third-party asset is copied into the project.
- Native visual pages accept an authored 32/64/128 m span while canonical
  storage/collision regions remain 32 m and each page remains capped at 256
  records. Small ordinary world models use 64 m pages; pack props use 128 m
  aligned pages. Larger pages initially increased local-light/shadow work; after
  adding index LODs, the final 128 m comparison improved CPU/frame cadence over
  the shared-material 32 m trial, though it still missed the strict tail gate.
- Object inspection performs occlusion rays only after finding room for a label.
  Its existing radius, candidate cap, layout frequency and input behavior remain.

The implementation uses existing external Godot APIs:
[ImporterMesh](https://docs.godotengine.org/en/4.7/classes/class_importermesh.html),
[Texture2DArray](https://docs.godotengine.org/en/4.7/classes/class_texture2darray.html)
and [spatial shaders](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html).
New project code is original 0BSD; original pack assets remain CC0-1.0.

## Measurement contract

`tests/object_rendering_world.gd` loads Hidden_Meadow read-only into a temporary
session. Its unchanged input SHA-256 is
`12fe7b19bccd0c9e9e6475a7e6efc1f4620794ba3ac7336d9d81ff6b0d4c41ec`.
No player save, clone, export or derived world cache is created. A temporary
collision platform holds the route independently of asynchronous saved-region
paging. Ground-level runs place it at Y=44.25; early raised runs used Y=64.
Those camera/terrain contexts must not be treated as matched comparisons.

The route inserts 1,000 additional native model records, then walks the normal
player approximately 55 m in each of four 600-physics-tick legs: outward/return
with labels off, then outward/return with labels on. Total measured duration is
40 simulation seconds and approximately 220 m. Terrain, water, vegetation,
resident zombies, actors, vehicle fleet, player physics and physical item drops
remain enabled; the driver checks every measured physics tick. It spawns extra
live zombies and two actors, drops four ordinary items per leg, and verifies
all inserted records and the unchanged source hash afterward. Existing world
objects remain present. This is substantially more than an isolated 1,000-mesh
scene, but it does not exercise every possible gameplay action.

Hardware: Intel Core i5-12450H, NVIDIA RTX 4050 Laptop GPU; Godot 4.7.2 Steam,
Forward+, 1920×1080, VSync and frame cap disabled. The isolated renderer uses a
non-input Windows desktop. Screenshots are outside timed intervals. No other
engine, native build or CPU test runs concurrently with timed walking.

The strict local gate requires **both p95 and p99 frame cadence <=16.667 ms in
each leg**, plus the gameplay/collision/residency assertions. GPU timing alone
does not qualify 60 FPS. A zero-added-object control uses the identical route and
systems and is explicitly labelled CONTROL; it cannot qualify the dense scene.
Packaged/export discovery and runtime LOD generation remain unverified until
the next requested packaged build. No universal hardware claim follows from a
local route pass.

```text
python tools/run_godot_check.py object_rendering_world --isolated-render --require failures=0 --timeout 300 -- --require-60fps --mixed-packs --ground-level
python tools/run_godot_check.py object_rendering_world --isolated-render --require failures=0 --timeout 300 -- --require-60fps --ground-level
python tools/run_godot_check.py object_rendering_world --isolated-render --require failures=0 --timeout 300 -- --mixed-packs --ground-level --control-no-added-objects
python tools/run_godot_check.py object_pack_render_mesh --isolated-render --require failures=0 --timeout 180
```

Reports are receipt-owned under `reports/checks/`; the bounded trace includes
frame cadence, render CPU/GPU time, draw counts, player positions and stage
percentiles. The admitted retention adapter keeps two ordinary ready captures
per family and hash-verifies older evidence into `homestead.archive.json`.
Cold evidence is preserved and can be restored into a new inspection directory.

## Evidence and remaining acceptance

The full-detail material comparison `20261126T133656440181Z` passed 237 checks:
all 110 bounds, full-detail triangle counts, collision metadata and cached
identities match; six rendered views cover textured geometry, glass, emissive
materials and the optimized outdoor models. Maximum RGB channel difference is
1/255 and mean difference is 0.000078743 over 2,654,208 channels. Matched distant
views were inspected; silhouettes and materials remain consistent at that size.
This is scoped visual engineering verification, not user approval of the mansion.

Earlier experiments remain in their original receipts, including:

- `20261126T122715026271Z`: invalid benchmark floor placement caused grounding
  failures. The benchmark now uses independent temporary collision support.
- `20261126T123239603504Z`: valid unoptimized Outdoor-only raised-route baseline;
  outward labels-off p95/p99 21.771/27.051 ms and GPU p95 19.097 ms.
- `20261126T123544733957Z`: reduced outdoor tessellation lowered that leg to
  15.084/18.381 ms; GPU p95 9.050 ms. The strict tail gate still failed.
- `20261126T123758369239Z`: raised-route mixed-pack baseline; outward labels-off
  p95/p99 23.312/32.213 ms, 11,866 draw calls at p95.
- `20261126T125243921177Z`: rejected unanchored large visual pages increased
  shadow submissions; fixed spatial alignment was restored.
- `20261126T132024280040Z`: LODs reduced ground-route GPU cost but left CPU frame
  cadence over budget. This is not a 60 FPS success.
- `20261126T132356604225Z`: ground-route mixed-pack GPU p95 4.94–5.96 ms, but
  frame p95 16.96–19.77 ms and p99 19.88–27.49 ms; all four frame gates failed.
- `20261126T132834293682Z`: rejected shader-discard culling changed cabinet glass.
- `20261126T133229803577Z`: shared material sorting changed three lamp-edge
  pixels. Conservative coincident-surface fallback fixes the comparison without
  weakening its threshold. Both rejected visual comparisons remain retained.
- `20261126T133810250168Z`: shared-material/fallback 32 m ground-route trial,
  1,000 mixed props: p95 19.07–23.87 ms, p99 22.65–34.28 ms, GPU p95
  5.54–6.45 ms. All functional assertions passed; all four frame gates failed.
- `20261126T134052441532Z`: same-route zero-added-prop control, 35 functional
  assertions pass. p95 12.66–15.44 ms, p99 15.16–18.58 ms. Existing world and
  gameplay already have tail stalls; this is not a dense-scene qualification.
- `20261126T134342320182Z`: rejected diagnostic `--render-thread separate`.
  The engine reports texture-update errors and render-server synchronization
  warnings. No production threading default is changed. Timings from this
  erroring run are not qualification evidence. The safe/separate diagnostic
  runner override remains explicit in its command receipt.
- `20261126T134609137005Z`: final aligned 128 m pack pages plus 64 m small
  ordinary-model pages, shared materials and LODs, ground-level mixed-pack walk.
  All functional assertions passed; all four strict frame gates failed. All
  3,506 native model records (including the 1,000 additions) were rendered with
  no pending uploads, changes or reads. The temporary route kept 2,400 physics
  ticks, 2,881 actor steps, up to 8 resident zombies and 16 physical drops, with
  zero invalid simulation ticks. The native horizon used 536 visual pages.

| Final mixed-pack leg | Median ms | p95 ms | p99 ms | GPU p95 ms | Render CPU p95 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Names off, outward | 14.065 | 19.418 | 23.993 | 9.003 | 7.064 |
| Names off, return | 12.352 | 15.573 | 16.841 | 8.133 | 5.261 |
| Names on, outward | 15.634 | 21.415 | 26.796 | 8.794 | 7.979 |
| Names on, return | 13.386 | 16.997 | 20.806 | 7.637 | 5.361 |

Typical frames are above 60 FPS in this run; the slower frames prevent a stable
60 FPS claim. On/off comparisons also include different evolving AI/physics
states, so they are not isolated measurements of label cost.

Final Outdoor-only ground route `20261126T134903560062Z` uses the same production
rendering policy. All 36 functional assertions pass, including complete native
rendered residency; the four strict frame gates fail. Loading took 25.725 s.

| Outdoor-only leg | Median ms | p95 ms | p99 ms | GPU p95 ms |
| --- | ---: | ---: | ---: | ---: |
| Names off, outward | 11.477 | 15.298 | 18.457 | 9.656 |
| Names off, return | 9.741 | 14.254 | 16.883 | 8.933 |
| Names on, outward | 12.320 | 17.006 | 20.181 | 9.870 |
| Names on, return | 10.681 | 15.755 | 20.166 | 8.375 |

The no-added-prop control already exceeds 16.667 ms at p99 in three legs. This
supports continuing with CPU submission and base-game tail work rather than
claiming that lower object GPU time alone solves the full-game target. Any
future batching across asset types needs bounded update/memory costs and the
same exact identity, editing, collision and save/reload guarantees.

## Regression verification

Both structures native configurations were rebuilt; current DLL SHA-256 hashes
match their build receipts. Tests use the admitted shared runner serially.

| Check | Receipt | Result |
| --- | --- | --- |
| Native horizon: 100,000-record pressure, bounds, exact identities/poses, save bytes and wider aligned pages | `20261126T135138799210Z` | 70 checks pass |
| Registry, stable item/model/recipe/icon identities and malformed packs | `20261126T135204298945Z` | 230 checks pass |
| Universal drop/recollection/persistence | `20261126T135233302968Z` | 1,273 checks pass |
| Physical item transactions and collisions | `20261126T135250769864Z` | 196 checks pass |
| Original-size geometry, collision, resizing and reload | `20261126T135412634933Z` | 26 checks pass |
| Rendered G/input/menu behavior | `20261126T135432001489Z` | 35 checks pass |
| Ordinary game inspection, scatter, storage and native fixture | `20261126T135554110640Z` | 32 checks pass |
| Fresh-process structure bytes, filled duffel contents and removal protection | `20261126T135809463373Z` | Pass |
| Reduced Outdoor 01 geometry and authored icon sheet | `20261126T124759765199Z` | 94 checks pass |

The earlier original-size attempt `20261126T135315305324Z` did not launch: its
generic 256 MiB planned-output allowance exceeded available report headroom.
After reading the test, only its headless branch was admitted at 2 MiB (small
logs/receipt, no image/save/export; a tiny process-owned preference file is
removed by the test). Storage budgets were not raised and evidence was not
evicted. Launcher tests pass (7), including that rendered checks retain the
conservative allowance; retention tests pass (3).

The historical stationary dense scene can now be compared at the same scope:
`20261126T120200048287Z` p95/p99 19.79/20.53 ms versus
`20261126T135554110640Z` 7.628/8.190 ms; p95 draw calls 1,755 versus 1,165.
That fixture disables the ordinary world physics tick in its dense phase. Its
improvement is evidence of rendering work, not a substitute for the failing
full-game walking gate. Fresh fixture SHA-256:
`884191dc6be641aab55e72142f22ce6c79113790ca9165d67176679af69459e6`.

Outdoor/mansion provenance, all ten Homestead provenance records and all 33
offline notices pass their check modes. No additional external code/assets,
full export, saved-world edit or engine threading default was introduced.
Headless editor import `object_rendering_uid_import_20261126T135943Z` passed
without errors and generated all three new Godot UID sidecars.

The remaining requirement is repeatable 60 FPS under the complete mixed-pack
walking workload. Return to the measured CPU rendering/gameplay bottlenecks;
close only with all four strict frame gates plus functional and visual checks.
Do not reduce object count, shadows, simulation or the acceptance threshold to
make this milestone pass. Mansion visual approval, generated-site terrain fit
and full circulation remain separately open in the existing integration issue.

## Follow-up: character admission stalls (26 November)

The opt-in `--cpu-diagnostics` route now separates physics callbacks, physics
solver tail, process work and draw submission, including main-thread CPU work,
native block/horizon/light timings and corpse preparation phases. Ordinary
qualification runs omit this instrumentation. Trace size stays below the
existing 8 MiB cap and the 32 MiB receipt allowance; no storage budget changed.

Saved-corpse restoration was still doing synchronous scene setup and installing
large head hulls in single steps. Diagnostic `20261126T141311696302Z` measured
up to 5.354 ms of restoration work, with a 4.214 ms head installation. The
character initializer now yields between scene instantiation, attachment,
anatomy, baking, individual physical bodies and animation setup. Saved-corpse
and ordinary live-population admission use 750 us cooperative slices. Pending
characters remain hidden and unavailable; readiness, distance, visibility,
capacity and support are rechecked before publishing a live resident. Reset,
retirement and cancellation dispose of incomplete work.

Large saved-pose hulls use the engine's unsimplified convex cleaner on a worker
through an immutable CPU-only Mesh packet. No engine implementation was copied.
Main-thread installation uses the resulting boundary vertices. Fingers retain
their original compound shapes and are installed in separate quanta. Other
small hull clouds are unchanged. Cleaning is not bit-identical geometry:
independent rest/attack/morph ray contacts agree within 0.5 mm (observed worst
0.340 mm), below the existing 3 mm head margin. Immediate combat deaths retain
the original synchronous path. Worker completion is joined before cancellation
releases its owning data; no worker reads the scene tree.

- `20261126T141911042542Z`: collision-cloud/contact checks, 86 pass.
- `20261126T142010211203Z`: staged saved-anatomy and no-debris checks pass.
- `20261126T142514380803Z`: lifecycle checks, 27 pass, including tiny-budget
  progress, worker cancellation, unparented-scene cleanup and live admission.
- `20261126T142859237106Z`: corpse rest/support checks, 33 pass.
- `20261126T143022929665Z`: corpse walking has one existing failure: leftward
  torso speed 3.07536 m/s exceeds its 3 m/s limit. The committed-baseline replay
  `20261126T143217251653Z` reproduces every recorded route metric exactly,
  including that failure. Neither the threshold nor physics policy was changed.
  Both receipts retain their complete `corpse_walk_result.json`; this remains
  an open baseline limitation, not a passing regression.

Diagnostic `20261126T142050850922Z` reduced observed restoration peaks to
1.806 ms, but a second GPU game was running during it and the preceding detailed
profile. These are attribution evidence, not clean FPS comparisons. The user
closed the competing game before strict replay `20261126T142559219408Z`.
The machine remained in its existing Legion Quiet Mode; no power setting,
resolution, object count, shadow policy or gameplay system was changed.

| Uncontended mixed-pack leg | p95 ms | p99 ms | GPU p95 ms |
| --- | ---: | ---: | ---: |
| Names off, outward | 18.503 | 21.063 | 8.859 |
| Names off, return | 16.184 | 18.627 | 7.979 |
| Names on, outward | 21.476 | 26.296 | 8.960 |
| Names on, return | 17.630 | 20.087 | 7.687 |

All 36 functional checks passed: 2,400 gameplay physics ticks, eight active
zombies, physical drops, all 1,000 added records and unchanged save bytes. All
four strict frame gates still failed. Stable 60 FPS remains open; the next work
is CPU draw submissions (5,208–7,521 p95 calls), including the 45 authored
material surfaces per complete zombie. Any batching must retain original skin,
morphs, material appearance, severing, collision and saved-state behavior and
pass the unchanged four-leg timing contract before this requirement closes.

## Closeout: character material batching (26 November)

At the user's request, this investigation ends with the verified improvements
committed and the remaining performance work recorded. Stable 60 FPS remains
unqualified; do not interpret this development checkpoint as closing that target.

`zombie_render_mesh.gd` combines compatible opaque R4 material surfaces into a
cached shared PBR shader. A complete visible rig uses 14 surfaces instead of 45;
including the hidden severing caps, 123 surfaces become 40. Texture arrays retain
the source dimensions, mipmaps and UVs. Source-order vertices, skin weights,
blend shapes, original culling bounds and index-LOD transitions remain intact.
Collision/anatomy still use the original CPU geometry. Unsupported materials,
custom models and custom geometry sources keep the existing rendering path.
Derived geometry propagates invalidation to the original cache listeners.
This is original 0BSD code using existing Godot APIs and assets, with no new
third-party intake or native binary changes.

The shared textures and combined geometry are prepared once per process. Reading
the source importer's LODs is cold preparation, not a per-character or per-frame
operation; it is separate from the offline collision/render bake counters.

- `20261126T164428070146Z`: geometry-bake checks, 19 pass, including independent
  skin/morph contacts and source-edit invalidation.
- `20261126T164822830801Z`: native/reference animated and detached mesh baking,
  164 surface comparisons, zero failures.
- `20261126T164642572542Z`: 77 geometry/material checks pass. Paired full-body,
  face and bite-pose images were inspected. Mean RGB-channel error is 0.00944
  byte; 169 of 3,145,728 channels differ by more than two bytes. The result is
  visually matched within the declared tolerance, not pixel-identical.
- `20261126T165629156606Z`: final six-view comparison, 83 checks pass. Both
  distant views differ by at most one channel byte, and rendered primitive
  counts match the original in every view (6,866 at 6 m; 5,277 at 24 m).
  The full comparison sheet and final walking capture were visually inspected.
- `20261126T165848309404Z`: final staged character lifecycle regression passes.
  Ten launcher/retention unit tests also pass. Admitted editor import
  `zombie_render_uid_import_20261126T165803091565Z` generated both new script
  identities without engine errors; source and UID sidecars are committed together.
- `20261126T164336368743Z`: rejected first LOD-access attempt used an API absent
  from the installed engine. The supported ImporterMesh API fixes it; the
  original erroring receipt remains retained.
- `20261126T164901688601Z`: another Company of Heroes process was running during
  this replay; it is contended evidence, not a performance comparison. The user
  closed it before the following strict replay.

Strict full-game replay `20261126T165138197821Z`, without CPU diagnostics:

| Mixed-pack leg | Median ms | p95 ms | p99 ms | GPU p95 ms | Render CPU p95 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Names off, outward | 12.847 | 16.832 | 20.155 | 8.393 | 6.610 |
| Names off, return | 11.206 | 14.705 | 16.516 | 7.597 | 4.959 |
| Names on, outward | 15.549 | 20.269 | 32.003 | 8.766 | 7.500 |
| Names on, return | 12.833 | 16.675 | 20.178 | 7.941 | 5.401 |

All 36 functional assertions pass, including all 1,000 additions remaining
resident, complete rendered representation, ordinary gameplay execution and
unchanged player-save bytes. Only one of the four strict timing gates passes.
Draw-call p95 falls to 4,709–7,109, but slow frames remain. The machine retains
Legion Quiet Mode and the same 1080p renderer, shadows and gameplay settings.

Diagnostic `20261126T165408389667Z` passes its 36 functional assertions; its
command deliberately omits the FPS gate and therefore is not a qualification
pass. It retains 2,982 detailed rows. Slow frames combine draw submission and
physics callbacks, sometimes executing three or four physics steps after a
stall. Profiling overhead and run variation preclude treating its worse tails
as a clean A/B result. Inspection layout in the strict run takes approximately
1.4 ms typically and up to 2.5 ms per refresh. These are investigation leads,
not proof that a particular remaining subsystem is the sole bottleneck.

Resume when dense-world performance is prioritized again: attribute the
remaining physics/collision-selection and draw-submission tails, then test any
change against this same four-leg route. Closure requires every p95 and p99
below 16.667 ms, all gameplay/residency/save assertions and relevant visual and
geometry regressions passing. Do not lower the gate, reduce the workload or
disable systems to claim completion. The existing corpse-walk speed failure
and separate mansion design/terrain/circulation acceptance remain open.

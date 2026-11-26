# Frame-tail investigation — 2026-11-26

Status: scoped draw-work reduction verified; overall frame-p99 improvement remains
unproven. Normal-desktop and same-scene verification are complete. Preserve
the unfavorable repetitions below. This follows the
[collision-work investigation](physics-residency-2026-11-26.md#collision-work-reduction-follow-up).

## Why collision improvement did not move the frame percentile

The route contains about 3,600 rendered frames and 26 corpse admissions spread
across multiple preparation frames. Reducing admission cost does not necessarily
remove the other contributors to the 36th slowest frame. In ordinary capture
`20261126T002716146642Z`, the slowest 1% average
11.892 ms drawing, 3.974 ms physics callbacks and 3.695 ms process callbacks.
Overall p99 was 21.919 ms. These boundaries do not include all engine work and
must not be added to overlapping terrain/zombie substage timers.

Detailed captures `20261126T003024554519Z` and `20261126T003944919903Z` found
21.846–30.030 ms gaps between **Update Occlusion Buffer** and **Update Visibility
Dependencies**. Draw-thread cycles stayed near ordinary draw work on those long
draws. This implicates waiting/descheduling around engine occlusion work, rather
than collision construction or the project's occluder publication: the latter
took only 4–11 microseconds in two of those frames. Engine worker-pool dispatch
and joins are a plausible mechanism, not a directly sampled wait-stack diagnosis.
[Godot implementation inspected](https://raw.githubusercontent.com/godotengine/godot/master/modules/raycast/raycast_occlusion_cull.cpp).
That source is architectural context; the installed executable identifies itself
as Godot 4.7.2 Steam `ed1daf0bf`.

The **Setup 3D Scene → Setup Sky** gap reached 7.390 ms. Its scope includes scene
list construction, sorting, instance buffers and pipeline preparation; its name
does not make this a sky-shader cost. Draw pipeline compilation remained zero in
the later detailed capture. Diagnostic capture itself raises p99 to 28–29 ms, so
it is excluded from ordinary cadence comparisons. The analyzer now rejects mixed
diagnostic/ordinary comparisons and records delayed render readback separately.

## Actual redundant work: water render ownership

The frozen post-route scene contained 2,709 visible water mesh nodes. Water's
4 m storage/query owners were also its rendering units. Removing only water
geometry in the post-route diagnostic reduced 5,003 submissions to 3,803 and
CPU draw wall time by about 1.3 ms in both orders. Terrain, ground cover and zombie
surfaces are additional substantial draw contributors. The inventory counts scene
objects, not actual camera-visible submissions.

The implementation combines current water owners into 16 m draw pages. It keeps
the exact indexed triangles, winding, normals, UVs, contact colors and material.
Water quantities, storage, picking, collision and settlement still use their
original owners. A bounded native worker combines immutable CPU packets without
GPU geometry readback. Page preparation does not gate water/terrain publication.
At an edit commit the affected page immediately exposes the current individual
owners, then optional consolidation resumes. A late worker result cannot replace
a newer revision. Reload and removal use the same ownership rules.

Limits: 32 MiB retained CPU packets, 512 KiB per page, 4 MiB per job, at most 16
pages/64 owners per page in one job, one owned worker at a time. Dense or invalid
inputs keep their individual meshes. Original GPU meshes remain available for
immediate edits; this deliberately trades bounded extra resident memory for fewer
recurring submissions. One route retained 24,589,536 CPU bytes with 295 active
pages and no fallback or stale publication. Its peak private commit was 4.07 GiB
(warning), dedicated GPU allocation 1.66 GiB; existing budget limits are unchanged.
The larger draw unit also coarsens culling and transparent-object sorting.
Geometry equivalence is not a pixel-identical-image guarantee; the inspected
water/crater views are scoped visual evidence, not universal visual acceptance.

The same-scene toggle in `20261126T010923478386Z` restores individual draws without
changing camera, simulation, geometry, page resources or actor identities:

| Order | Draw mode | Submissions | Mean draw wall | Mean draw cycles |
| --- | --- | ---: | ---: | ---: |
| Forward | Pages | 3,916 | 7.890 ms | 17.679 million |
| Forward | Individual owners | 4,962 | 8.611 ms | 19.154 million |
| Reverse | Pages | 3,916 | 7.484 ms | 16.564 million |
| Reverse | Individual owners | 4,962 | 8.601 ms | 18.875 million |

This demonstrates 7.7–12.2% less draw-thread work at that view, not a whole-route
frame-p99 improvement. GPU timing remains a separate delayed measurement.

## Cadence evidence and rejected paths

All ordinary runs below use the same read-only `Hidden_Meadow` save, seed 1703,
six 600-physics-tick legs, 1920×1080 Forward+, 60 Hz physics, VSync and 60 FPS cap.
Source SHA-256:
`b5c310dba6521eae0219d1cceed7c65022c7178ecf23214e2aca0becd62408ee`.
Receipts live under `reports/checks/<run>/`; cold traces are verified through
`physics.archive.json`, not missing evidence.

| Run | Configuration / result | Frame p99 | Maximum |
| --- | --- | ---: | ---: |
| `20261126T002716146642Z` | Original draw ownership, basic boundaries; population drift | 21.919 ms | 36.929 ms |
| `20261126T004324020531Z` | Original ownership; post-route render-group probe | 22.100 ms | 38.332 ms |
| `20261126T010440689150Z` | First pages run; population drift, RAM warning | 25.577 ms | 65.220 ms |
| `20261126T010923478386Z` | Pages and lightweight CPU counters; outcomes match `004324` | 25.772 ms | 111.810 ms |

The matched row is an unfavorable result, not a demonstrated frame-pacing win.
Several long frames have only ordinary main-thread CPU work, including waits
outside the measured viewport scope. The presentation controls below distinguish
renderer work from those stalls. The observer now anchors engine timestamps to
UTC; resource-monitor intervals retain their own collection cost and aggregate
CPU load, so instrumentation interference can be checked explicitly.

Rejected experiments:

- `20261126T003440359537Z`: four global worker threads, preserving the previous
  total occlusion-ray budget, failed the 120-second loading bound and hung during
  teardown. Only the owned process was stopped. Both settings were restored.
- `20261126T003818580642Z`: stopping/inactivating/unregistering physical bones
  before corpse deletion did not consistently improve deletion cost. Experimental
  code was removed; evidence remains.
- `20261126T011511765764Z`: an unbatched control completed its legs but hit a
  test-only empty typed-array reporting error before writing cadence. It is a failed
  run, not a timing comparison. The reporting path was corrected.
- Early render-page checks failed on a test declaration and on comparison against
  unquantized normals. Comparing both paths after identical renderer packing
  passes. An intermediate test accidentally reused readback arrays containing an
  unsupported stream; that error and its timed-out run remain in the check logs.

## Repeatability correction

The native awareness record used its transient scene ObjectID to initialize
roaming randomness. Changing render allocation can therefore change actor behavior
even with identical source, world seed and player inputs. Persistent population
admission now supplies the stable actor identity and world seed separately from
the runtime lifetime/query handle. Manual actors retain their existing default
initialization; restored sleep state still follows its existing restoration path.
The native regression verifies identical decisions across different ObjectIDs and
global random seeds, and distinct streams for different world seeds.

Final timing comparisons must apply this correction to **both** render modes.
Earlier timings are historical context, not a fair comparison across changed
actor random streams. This fixes one replay dependency; asynchronous navigation,
physics ordering and complete state restoration still prevent a claim of fully
deterministic human replay.

## Verification and remaining work

### Matched streams and wait attribution follow-up

The first stable-stream pair has identical route endpoints and populations:
`20261126T012151413000Z` (individual draws with prepared page resources) versus
`20261126T012401520778Z` (pages). Mean draw cycles fall from 20.088 to 18.217
million, and whole-thread cycles from 37.450 to 35.547 million. Frame p99 is
27.723 versus 28.483 ms: **no demonstrated p99 improvement**. The external resource
monitor's most expensive GPU collection takes 0.376 ms; its intervals rarely
overlap the long frames. It does not explain the stalls.

Repetition with builds and analysis idle during the route gives p99 31.705 and
32.285 ms (`20261126T063156547953Z`, `20261126T063433898428Z`). The second site has
three versus four living actors in its first two legs, so this repetition is not
accepted as a matched timing comparison. Stable initial random streams do not
make asynchronous navigation deterministic.

Additional controls retain adverse evidence:

- `20261126T012653841223Z`: disabling occlusion raises mean draw cycles to
  20.062 million; p99 remains 26.447 ms, with population differences. Occlusion
  stays enabled in the product.
- `20261126T064201772747Z`: VSync disabled, existing 60 FPS cap retained; p99
  31.172 ms and maximum 92.930 ms. This does not remove the stalls; the normal
  VSync setting remains unchanged.
- `20261126T064527699804Z`: **all** render-page preparation disabled, not merely
  the draw toggle. Zero pages, CPU packets and worker work; p99 31.298 ms, maximum
  120.437 ms. Endpoints/populations match batched run `063433898428Z`. Its extra page
  resources therefore do not explain these long stalls. Original and batched
  paths both retain them.

Diagnostic `20261126T063736518632Z` additionally sampled the owned main thread's
Windows scheduling state and cycle counter. It did not suspend threads, change
priority or change affinity. 4,066 samples took 3.690 ms per collection on average;
this is intrusive diagnostic evidence, **not** normal timing acceptance. The
observed no-work intervals include:

| Engine interval start (us) | Sampled duration | Windows wait state | Correlated frame |
| ---: | ---: | --- | --- |
| 38,227,290 | 31 ms | Unknown wait | 49.422 ms, site 0 out |
| 39,840,290 | 30 ms | Unknown wait | 68.314 ms, site 0 out |
| 69,737,290 | 32 ms | UserRequest | 52.108 ms, site 1 idle |
| 80,022,290 | 47 ms | Executive | 86.835 ms, site 1 back, physics callbacks |

The first three are after the same device frame's final recorded render command
and before `frame_post_draw`, not inside its occlusion/culling markers. Associate
device markers by **CPU timestamp**, not the sample row that happens to receive
their delayed readback. For example device frame 1620 spans 38,215,966–38,220,461 us,
while that draw completes at 38,259,398 us. Godot's
[render-server ordering](https://raw.githubusercontent.com/godotengine/godot/master/servers/rendering/rendering_server_default.cpp)
places frame submission/presentation after viewport commands. This narrows a
boundary; it does not identify a specific Vulkan/Windows call without a stack.
The physics-callback wait remains a separate unattributed interval.

### Water regression correction

`20261126T012902840886Z` fails three water checks because this paused-combat fixture
inherited the player's saved asynchronous barrel-chain mode. It consumed the
barrel but did not run the crater submission scheduler: zero measured frames and
6.216 ms to the premature idle return. The fixture now fixes its intended
single-crater mode without saving a preference, and requires actual terrain
publication. `20261126T062900766653Z` passes all checks: conserved quantity,
downward redistribution, settled reload, unfinished loading-time settlement and
legacy snapshot migration. The three above/underwater images were inspected;
they show continuous water coverage without an obvious page-boundary seam in
these views. This is not universal shoreline-quality acceptance. The existing
general-world-image export warning is unrelated and retained in the log.

### Presentation controls and normal-desktop replay

All captures through `20261126T065238205934Z` used the non-input Windows desktop
and a windowed surface. The normal desktop controls below are explicitly launched
with `--visible-render`; source saves remain read-only. Do not conflate a desktop
change, focus change or fullscreen/windowed change with a runtime optimization.

- `20261126T064821270724Z`: manual `force_draw(false)` removes large stalls but
  produces 6,221 samples in the route instead of about 3,600. Its p99 18.662 ms
  and maximum 28.684 ms are **not** normal cadence acceptance. The option is now
  explicitly named `--manual-no-present-probe`.
- `20261126T065238205934Z`: detaching the viewport from the window retains the
  ordinary render loop, 60 FPS cap, 3,600 distinct process frames and full scene
  rendering (mean GPU 6.142 ms). P99 is 21.162 ms, maximum 29.334 ms, zero intervals
  over 33.333 ms. Site 1 populations differ, so this is a presentation-boundary
  diagnostic, not an accepted optimization comparison.

The detached control uses the documented viewport attachment API rather than
replacing the engine loop. See [RenderingServer API](https://docs.godotengine.org/en/latest/classes/class_renderingserver.html)
and [viewport implementation](https://raw.githubusercontent.com/godotengine/godot/master/servers/rendering/renderer_viewport.cpp).
These are architectural references, not proof of the installed driver's wait stack.

| Normal-desktop run | Configuration | Frame p99 | Maximum | Intervals >33.333 ms / >50 ms |
| --- | --- | ---: | ---: | ---: |
| `20261126T070030406214Z` | Fullscreen, focused throughout; all page work disabled | 21.102 ms | 28.715 ms | 0 / 0 |
| `20261126T070247727088Z` | Fullscreen, focused throughout; pages enabled | 21.055 ms | 29.561 ms | 0 / 0 |
| `20261126T071239064577Z` | Windowed, unfocused throughout; pages enabled | 21.824 ms | 40.420 ms | 3 / 0 |
| `20261126T071627306907Z` | Windowed, unfocused throughout; all page work disabled | 22.460 ms | 35.580 ms | 1 / 0 |

Both pairs preserve source hash, resolution, input route and endpoints, but have
different site 1 living populations (3 versus 2 fullscreen; 3 versus 4 windowed).
The analyzer rejects both as matched whole-route A/B comparisons. Their lower
tails relative to the later isolated runs are evidence against treating those
isolated stalls as ordinary player-visible performance, **not** evidence that
water batching eliminated them. No product VSync, FPS, worker-pool or occlusion
setting was changed. No particular driver call is proven responsible.

`20261126T070815870283Z` is a rejected windowed attempt: it lost focus briefly,
later had zero movement on two legs, and the old harness still printed success.
Its cadence is not route acceptance. The driver now consumes physical input before
game/UI handlers, retains actual focus, and asserts gameplay input remains available
and each movement leg moves. Window-mode probes occur before world loading.
The repeat `071239064577Z` passes all six leg assertions with the original endpoints.
No assertion filters or removes slow frames. Desktop, window mode and focus are
now included in comparison metadata; the analyzer obtains older surface provenance
from the original launcher receipts without rewriting the raw captures.

The valid windowed repeat freezes simulation only **after** completing the route.
Its same-camera, same-actor, same-resource comparison, in both orders, gives:

| Order | Draw mode | Submissions | Mean draw wall | Mean draw cycles |
| --- | --- | ---: | ---: | ---: |
| Forward | Pages | 3,928 | 6.380 ms | 14.452 million |
| Forward | Individual owners | 4,974 | 7.202 ms | 16.513 million |
| Reverse | Pages | 3,928 | 6.809 ms | 14.462 million |
| Reverse | Individual owners | 4,974 | 8.144 ms | 17.850 million |

This is 1,046 fewer submissions (21.0%) and 12.5–19.0% fewer main-thread draw
cycles. GPU means remain about 5.9–6.1 ms. The earlier rejected route's frozen
view independently gives 1,461 fewer submissions and 15.4–18.6% fewer draw cycles;
its stationary route does not invalidate a fixed-scene geometry toggle, but it
cannot qualify gameplay timing. The primary accepted work evidence is `071239`.

### What still sets the normal frame tail

In the focused fullscreen batched run, 15 of the 36 slowest frames have over
2 ms of corpse restoration, and 25 have over 1 ms of terrain surface publication;
these sets overlap. Their mean physics, process and draw boundaries are 4.106,
3.990 and 8.122 ms. About 100 frames per route still contain over 2 ms of restored
corpse work. The largest geometry install remains the head (mean 2.594 ms), while
each hand's compound installation averages about 1.15 ms. The largest site 1
transition also includes a roughly 10 ms engine interval after physics callbacks.
These are measured contributors, not separately isolated Jolt or terrain-root causes.

Water batching removes recurring submission work and improves CPU headroom. It
does not remove those coincident workloads or guarantee a lower capped-frame p99.
The fully matched stable-stream isolated pair above also records no p99 gain.
Remaining closure requires a normal-desktop equivalent workload with deterministic
state checks, attribution of the engine waits, and further actual-work reduction
in the surviving corpse/terrain publication costs. A deferred build queue or lower
population cap alone would not establish that work was removed.

### Verification and reproduction

The persistent-awareness fix is committed as `8d5f4bd1`; water draw pages and the
barrel-fixture correction as `c41183eb`; replay instrumentation and comparison
safeguards as `95b5ff49`. New implementation is original AI-assisted
0BSD code. No third-party source or new dependency was imported; existing native
dependency versions, grants and build settings are retained.

- Both water debug/release native libraries build. Geometry and page lifecycle
  checks pass, including stale jobs, removal, immediate edit fallback, reload and
  same-scene toggle: `20261126T010906216507Z`. The final 17-assertion run adds safe
  disabling and passes as `20261126T065740067837Z`. Godot generated both matching
  new script UIDs during the admitted import `uid_import_20261126T065552Z`.
- The integrated route checks every current water owner is drawn exactly once
  and that each page retains the sum of its owners' triangle counts.
- Stable awareness stream regression: 37 checks pass,
  `20261126T012134278016Z`. Both world-runtime native variants build; the pinned
  Zig cache required a diagnostic verbose recompilation after file-not-found
  errors. Dependency versions and optimization settings were not changed.
- All four native debug/release libraries pass the canonical build tool's source,
  dependency-signature and output-hash freshness check after these changes.
- Cadence/retention/resource-tool regressions pass (5 cadence tests, 11 resource
  tests); bounded sampling-cost evidence and presentation-comparison rejection
  have regressions. Resource sampling remains at 0.5 s and retains at most 2,048
  intervals. The Windows CPU/memory probe also passes known-work versus idle and
  processor-normalization checks. No storage or runtime budget was raised.

Run from the project root with the configured Godot executable:

```text
python tools/run_godot_check.py physics_residency_world --godot GODOT_EXE --visible-render --timeout 300 --require "PHYSICS_RESIDENCY failures=0" -- --windowed-probe --original-water-render-probe
python tools/run_godot_check.py physics_residency_world --godot GODOT_EXE --visible-render --timeout 300 --require "PHYSICS_RESIDENCY failures=0" -- --windowed-probe --render-ablation
python tools/analyze_physics_residency.py reports/checks/CONTROL reports/checks/CANDIDATE
```

Omit `--windowed-probe` for normal fullscreen. `--render-ablation` affects only
the post-route frozen scene. The runner admits bounded output, records hashes,
and cold-retains older captures after exit. Timing requires equivalent populations,
presentation, focus and settings; a successful functional replay alone is not a
timing pass. An uncapped headroom check, engine wait-stack attribution, simultaneous
combat-death coverage and arbitrary recorded human input replay remain open.
Return to those gates with retained state and matching normal-desktop runs;
do not label this draw-work reduction as complete FPS stabilization.

# Walking performance lab — 2026-11-28

Status: **one causal native fix tested; overall qualification still fails**. User requested systemic resolution of every
walking drop below 60 FPS, with 61 FPS and headroom. The human-approved vegetation
snapshot is `dd5accbb`; this investigation does not reduce nearby detail, lighting,
population, physics, streaming or view distance. The user authorized committing
and pushing this source checkpoint on 2026-11-28; normal-desktop and human
performance validation remain open.

## Acceptance contract

- Retain every measured walking frame. Any interval above 1000/60 ms is critical;
  a good mean or p99 cannot override a single failure. Loading/setup is separate;
  a death, respawn, menu, missing sample or capture overflow invalidates the route.
- The 61 FPS budget is 16.3934426 ms. Initial **20% headroom** means every frame
  at or below 13.1147541 ms in an uncapped capacity run. This is intentionally
  stricter than the older p99 <=20 ms / maximum <=50 ms performance gate.
- Uncapped, VSync-disabled capacity and 61-cap pacing are different experiments.
  A 60 FPS limiter cannot prove 61 FPS capacity. Engine post-draw cadence does not
  measure physical display presentation; display refresh/VRR must be qualified
  separately on the interactive desktop.
- Production actors, ground contacts and streaming remain active. Only initial
  route setup teleports. Route movement uses held keys and yaw steering with the
  normal player physics controller. The canonical save is read-only and hashed.
- Finite route passes do not establish universal world performance. Qualification
  must cover fields, populated streets, forests, shoreline, interiors, caves,
  streaming boundaries and combat/corpse accumulation, with repeats and human
  traversal. The first fixture is the already-tested Homestead outdoor route.
- Capture source/native/engine/save identity, actual viewport/render scale,
  adapter, presentation mode, cap, route state and exact frame IDs. Check source
  consistency and competing render jobs before/after. This is not proof that all
  unrelated background activity was absent during the run.

## Two recorder modes

`tools/run_walking_lab.py` is the bounded launcher. It uses the source project,
an existing save, the shared isolated-render runner and no export/world clone.

```powershell
python tools/run_walking_lab.py --seconds 30
python tools/run_walking_lab.py --seconds 30 --diagnostic
python tools/run_walking_lab.py --seconds 30 --pacing cap61
python -m unittest discover -s tools -p test_walking_performance.py
```

Qualification uses preallocated packed scalar samples, no frame dictionaries,
images, JSON serialization, trace flushing or GPU queries in the measured loop.
Binary compression and analysis occur after measurement. The recorder's measured
callback overhead is retained, not subtracted from cadence. This does not include
all signal dispatch/observer effects; matched instrumentation comparisons remain
required before a borderline success can be accepted.

Diagnostic mode adds delayed viewport GPU/render CPU counters, draw/primitive and
pipeline counts, terrain queue/stage work, vegetation/residency timings and native
main-thread cycle/CPU counters. Windows thread CPU time is coarse, not a precise
per-frame execution timer. GPU values can lag; do not correlate them to a current
frame as though they have matching IDs. Engine phase spans and subsystem work
overlap, so they must not be added together. Diagnostics cannot qualify capacity.
The heavy historical rolling recorder remains available for follow-up causes;
it is not enabled in the lightweight qualification run.

Both modes retain all frame cadence and positions, an index of every critical
frame, and a small worst-frame convenience table. Raw data is SHA-256 checked on
analysis. The gate's negative controls include a single 50 ms hitch hidden by a
10 ms p99, a 61-only miss, missing frames, NaN, overflow, death and cap changes.

## Diagnosis and optimization policy

First reproduce a failing route and locate the wall-time phase. Then vary one
factor, retain adverse controls and repeat in alternating order. A subsystem
timing correlation is a lead, not a cause. Prove the responsible operation with
matched input/state or a narrow counterfactual. Distinguish actual CPU work,
physics stepping, GPU work, pipeline compilation, streaming/publication and
engine/driver/OS waits. A render-thread wait is not fixed by merely moving more
code into C++.

Use native contiguous records/jobs, bounded publication, batched rendering or
GPU compute when measured total cost improves. Include transfer/readback,
synchronization, memory peaks and worst-case work. A rewrite is justified by
measured structural limits, not by language or API alone. Preserve save
compatibility, contacts, population and visible behavior; compare those alongside
performance before promoting a change.

## Proven first cause: LOD mesh switches synchronously read back GPU buffers

The light baseline walked 174 m with normal actors/streaming at 1920×1080.
Detailed repeats located 15–24 ms in `NativeStaticBatch::update_surface_lod`,
outside its selection/upload/cleanup timers. Ground-cover GDScript was generally
only tens of microseconds. The offending operation is the MultiMesh mesh switch,
not a slow grass-generation loop. Bounds lookup was an initial lead; the isolated
mesh-assignment control below identifies the narrower operation.

Godot's [renderer implementation](https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/storage_rd/mesh_storage.cpp)
contains a mesh-switch path that reconstructs bounds from a GPU buffer when its
local transform cache is absent. That source is architectural context, not a
claim that online master is byte-identical to the installed 4.7.2 Steam engine.
The installed-engine counterfactual establishes the observed mechanism:

- Two non-visible MultiMeshes had identical 215-instance buffers, custom bounds,
  counts and mesh geometry. The same real-world scene continued rendering behind
  the test. Only one variant received a single transform write **before** the
  full buffer upload, creating Godot's local cache without a GPU readback.
- Eight alternating windows of 64 actual mesh switches: uncached median
  **16.921–20.025 ms**; cached median **0.009 ms** in every cached window.
- All four before/after full-buffer equality checks passed. No mesh, instance,
  shader, terrain colour or render-quality change produced that difference.
- Resident cover buffers totalled 3,558,912 bytes at the measured endpoint.
  A CPU copy therefore adds about 3.4 MiB of transform data for that population,
  plus engine metadata (not a universal bound or motion-vector estimate).

The native change in `static_streaming.cpp` creates that CPU cache
before the authoritative upload, only for batches configured with surface LOD.
The full upload overwrites the temporary transform exactly. The instance-count
change path handles cache reallocation too. Existing residency/upload limits
bound the extra copy; ordinary non-LOD props keep their old behavior. Only the
source/debug structures DLL has been rebuilt and tested; release/export coverage
is not claimed. Shared DLLs also contain unrelated native work and are excluded
from this focused source checkpoint. Rebuild the source module with
`python tools/build_native.py --addon structures --target template_debug`.

### Measurement can hide this bug

Godot's [per-instance getters](https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/storage_rd/mesh_storage.cpp)
can create the same local cache. Inspecting transforms before timing can therefore
erase the very stall being investigated. Several existing vegetation witnesses
inspect per-instance transforms, so their timings cannot alone qualify the
previously uninspected ordinary walking path. Full-buffer retrieval used by this
counterfactual returns the data without creating that cache. Correctness capture
and intrusive inspection must run **after** the ordinary performance window.

## Results and limits

All runs below used the same canonical save hash, start, input route, source engine
and full render resolution; saves stayed unchanged. Async simulation is not fully
deterministic, so whole-route comparisons are observational. The isolated
mesh-switch experiment above supplies causal evidence for that operation.
See [compact evidence and identities](walking-lab-evidence.json); raw binaries,
metadata, logs and cold-archive receipts remain under `reports/checks/<run>/`.

| Run | Mode | p99 ms | Maximum ms | Critical frames / total |
| --- | --- | ---: | ---: | ---: |
| `095830327744Z` | Original, lightweight | 39.783 | 44.599 | 964 / 1,487 |
| `100306271619Z` | Cache fix, lightweight | 24.832 | 31.348 | 352 / 2,168 |
| `100601394117Z` | Cache fix, diagnostic repeat | 20.383 | 39.599 | 112 / 3,040 |

All IDs have prefix `20261128T`. **Every row fails the strict target.** The last
row's extra instrumentation and run-to-run variation prevent treating it as an
ordinary capacity result. In its retained worst frames, the most expensive cover
batch was 1.059 ms; the former 15–24 ms mesh-switch signature is absent. The worst
remaining interval has 34.525 ms in the draw boundary with tiny vegetation work;
other frames include long physics callbacks and collision publication. They need
separate controls and normal-desktop verification, not attribution to this fix.

The frozen post-route full/half-resolution control retained identical draw and
primitive counts but had substantial timing drift between windows. It remains a
diagnostic, not evidence for reducing resolution or a precise pixel-cost claim.
No resolution change was promoted. The display reports 60 Hz; these uncapped
engine timings do not establish 61 physically presented images per second.

Validation: seven analyzer tests pass, including single-hitch, missing-frame,
invalid-state, resolution and clock-corruption negative controls. The existing
`vegetation_final_handoffs --smoke` regression (`20261128T100850403453Z`) passes
with exact nearby grass pixels, stable population and repeated-source parity.
That smoke scope covers the grass/proxy handoff, not every vegetation species.
Its engine result passed; automatic post-run archival initially failed at the
archive budget. Evidence stayed intact; recovery is recorded in its receipt.
`static_lod_cache` (`20261128T101641714139Z`) also passes all 15 assertions on the
actual renderer: initial pose/custom-data bytes, repeated near/far mesh switches,
growth, shrinkage, pooled-page reuse and unchanged authoritative snapshots.
Godot generated both new tests' UID sidecars. All six retained frame traces were
reanalyzed, including cold captures, preserving the original invalid-run status
and every critical-frame count. Reanalysis checks the engine receipt too, so a
trace flushed before a cleanup error cannot later become a false valid result.

Rejected runs remain visible: `093954545104Z` failed the new driver's initial
type check. `094224464864Z` completed traversal but failed cleanup because a
physics observer remained connected after freeing the game. Observer teardown is
fixed; its timing data is retained as failed evidence, not clean qualification.

### Remaining requirements

1. Attribute the remaining physics/collision-publication and draw-tail spikes
   with matched controls. Do not infer a driver or Jolt cause from a broad span.
2. Repeat lightweight uncapped and 61-cap pacing on the normal desktop, measuring
   instrumentation influence and recording display/power state. Current isolated
   desktop results cannot close presentation behavior.
3. Extend fixtures beyond this one outdoor route to the matrix above, including
   live combat/corpses, dense streets and streaming boundaries. Zero critical
   frames and the stated headroom are required, not just improved averages.
4. Obtain human playtest approval before closing appearance or normal-play
   performance acceptance. Nearby appearance and brightness remain protected.
   The user explicitly authorized commit/push of this partial checkpoint on
   2026-11-28; that authorization does not claim the remaining FPS target is met.

## Evidence lifecycle

Each invocation admits 2 MiB report growth and zero world/scratch output before
creating its receipt. The packed trace has 24,000-frame capacity and a 1.5 MiB
compressed-file bound. Exceeding either fails the run. Source/native hashes and
the driver copy accompany the receipt; logs and small analysis stay ready.
The shared receipt selector knows the `walking_performance` family. This launcher
archives only that family's older completed captures, retains two ordinary ready
copies and honors `.retain`/`RETAIN_READY`. Reconstruction is verified before
exact owned files retire. No storage budget is raised, save removed or evidence
silently discarded. Archives restore using the repository's existing retention
workflow. A failed budget or maintenance operation remains visible.
The analyzer can also read/hash-check this family's cold files directly without
allocating a restored copy. The small `static_lod_cache` renderer regression
admits 512 KiB for logs/receipt and zero saved-world bytes; it writes no captures.

Original lab code/documentation is AI-assisted repository work under 0BSD,
reusing the existing repository's walking setup and instrumentation interfaces.
No external implementation or asset was imported.

# Foundation qualification

The foundation is unqualified until integrated workloads meet explicit resource,
latency, correctness and endurance requirements. Isolated green tests do not
authorize claims about furnished cities or large multiplayer populations.

## Implemented adversarial mining test

`tools/foundation_scaling.py --godot PATH` runs workload multipliers 1, 4 and 16
sequentially in the actual streaming terrain/forest scene at 1920×1080 fullscreen,
full render scale and a 60 FPS cap. Each fresh temporary world runs:

1. Initial streaming baseline.
2. Repeated excavation/addition at a fixed control site.
3. Deepening excavations at separate sites.
4. Surface mining across new regions, with stepped travel that does not wait for
   destination residency. This deliberately stresses interaction with streaming.
5. The original control operation after accumulating distant edits.
6. Recovery without additional edits.

The multipliers submit 136, 544 and 2,176 edits respectively. At least 90% must
actually change terrain, preventing empty-space commands from masquerading as
throughput. Queueing, field mutation, rebuilding, publication, draw callbacks,
patch work, frame intervals, page/triangle counts and engine memory are retained.
Compact per-phase checkpoints and frame CSVs preserve progress on interrupted
runs. Detailed event/patch traces are serialized only after capture disconnects;
the original full checkpoints introduced hundreds of milliseconds of observer
overhead and invalidated the original boundary-frame stall conclusions.

Provisional rejection gates: frame p99 above 20 ms, any frame above 50 ms, edit
publication p95 above 150 ms, or return-control median degradation above 25%.
These are early rejection criteria. Passing does not demonstrate strict 60 FPS,
CPU/GPU headroom, physical input-to-photon latency, or an hour-long soak. Engine
memory excludes some native/GPU allocations and includes retained test events.
A capped frame interval does not
measure available GPU headroom. No city, active entity population or multiplayer
traffic is included in this test.

## Required primitive pressure matrix — not yet certified

The [bounded backend density job](TERRAIN_DENSITY_BACKEND.md) passes 38 real
queue checks, including eight outstanding requests, revision rejection and
shutdown accounting. The existing 42 publication checks still pass. Final
consumer staleness, player arbitration and loaded latency remain outstanding.

The [opt-in native density command](TERRAIN_DENSITY_COMMAND.md) is now exposed
in both extension builds. Thirteen release-thread API checks and 22 native
wire parity cases pass; the existing 42 worker publication checks still pass.
Backend queue/player adoption and end-to-end latency remain outstanding.

The [cubic numerical follow-up](TERRAIN_CUBIC_NUMERICS.md) exposes and corrects
seven additional cubic errors. All 67 numerical cases now pass, along with
the traversal/frozen-ray controls. This remains finite-precision experimental
code, with runtime performance and broader traversal adversaries unqualified.

The [near-tangent quadratic suite](TERRAIN_RAY_NUMERICS.md) exposed seven
query failures. A separate lower-degree solve corrects all 33 cases while
retaining the original query controls. General cubic near-tangency remains
unqualified; this is not runtime adoption.

The [experimental density query](TERRAIN_DENSITY_QUERY.md) adds bounded native
cell traversal and cubic first-root handling. Eighteen analytic controls and
all 22 frozen ray-miss locations pass. Runtime ownership, broader numerical
adversaries and rendered-surface agreement remain unqualified.

The [density-crossing diagnostic](TERRAIN_DENSITY_RAYS.md) brackets field hits
at all 22 frozen triangle-ray misses within 2 mm, with shifted air/solid
controls. There is no existing exposed density interaction raycaster; first
hit traversal, tangencies and runtime integration remain to be implemented.

The [shape-sweep follow-up](TERRAIN_COLLISION_SWEEPS.md) passes all 528 centered
sphere/capsule casts and 528 displaced controls across the frozen ray-miss
faces and diagnostic transforms. Ray failures persist; these results narrow
the failure to query behavior in the tested cases, not proven player fall-through.

The [exact-zero merge variant](TERRAIN_EXACT_ZERO.md) preserves all tested
topology/partitions and recovers all 21 frozen missed rays. One of 180 newly
sampled rays still misses a nonzero thin triangle, so collision qualification
remains failed. The variant is opt-in; production defaults are unchanged.

The [collision isolation experiment](TERRAIN_COLLISION_ISOLATION.md) repeats
21 missed faces across 756 coordinate/scale/ray cases. Origin rebasing does
not recover the original faces; size and ray-length sensitivity also occurs
in direct Geometry3D queries. Tiny-face robustness remains unresolved.

The [candidate collision probe](TERRAIN_CANDIDATE_COLLISION.md) **fails**: 21 of
180 real Godot physics rays miss very small candidate triangles, although
native collision recipes preserve all input faces. Earlier nonzero-area and
topology checks are insufficient for collision readiness. Adoption is rejected
pending numerical robustness diagnosis and correction.

The [combined CPU surface entry](TERRAIN_CANDIDATE_SURFACE.md) couples geometry
and normals: all 27 allocation failure points and initial/final cancellation
controls discard both outputs. This is not yet a material/collision/render
packet or Godot-worker integration.

The [bounded normal density cache](TERRAIN_CANDIDATE_NORMAL_DENSITY.md) reduces
the retained 32 m cave normal pass from 16.19 to 4.92 ms versus height-only
caching, preserving 75 paired outputs. Scratch is 32,368 bytes for that owner.
Integrated pipeline and graphical qualification remain outstanding.

The [normal column cache](TERRAIN_CANDIDATE_NORMAL_CACHE.md) preserves all 75
paired outputs and reduces aggregate fixture median normal time by 57.2%.
The 32 m cave still takes 12.15 ms for normals alone; gameplay adoption and
integrated normal-halo invalidation remain unqualified.

The [canonical normal reference](TERRAIN_CANDIDATE_NORMALS.md) preserves exact
normals across tested partitions, but direct scalar sampling costs 27.85 ms
for the 32 m cave fixture in the retained run. Runtime adoption is rejected;
density reuse and an explicit shading halo are required.

The [candidate geometry dependency control](TERRAIN_CANDIDATE_LOCAL_DEPENDENCY.md)
passes six real-edit cases at region interiors, edges and corners. Only 1, 2
or 4 owners change; all unselected owners match fresh rebuilds exactly. This
does not qualify LOD, shading dependencies or runtime scheduling.

The [candidate output allocator](TERRAIN_CANDIDATE_OUTPUT_ALLOCATION.md) recovers
from all 30 injected position/index growth failures without partial output or
tracked-buffer leaks. The follow-up also recovers all three sampler allocation
failures through the world entry point. The subsequent [fixed edge table](TERRAIN_CANDIDATE_EDGE_TABLE.md)
removes hash-node allocation and passes all 24 combined candidate allocation
failure injections. This does not establish engine-wide OOM resilience.

The [experimental native region interface](TERRAIN_CANDIDATE_INTERFACE.md) now
separates meshing from its benchmark, rejects invalid region/buffer inputs and
retains exact geometry and cancellation checks. It remains unregistered in the
game extension; runtime integration remains incomplete.
Its world-backed entry now covers cancellation during sampler setup as well as
meshing, with exact output parity. The world must remain immutable during a build.

The [candidate build-limit controls](TERRAIN_TETRA_BUILD_LIMITS.md) verify explicit
output-limit/cancellation status, discarded partial geometry and exact recovery.
A native-thread follow-up verifies per-world epoch interruption and isolation.
Godot-worker integration remains unqualified for the replacement candidate.

The [two-plane candidate sampler](TERRAIN_TETRA_ROLLING_FIELD.md) reduces a 32 m
region's sampling payload from a 1.07 MiB density buffer to 17 KiB including
height/page caches. Exact density and geometry parity, including sampler edge
controls, pass. Output storage and total runtime performance remain unqualified.

The [rolling crossing-map candidate](TERRAIN_TETRA_EDGE_STORAGE.md) bounds temporary
edge entries to one height layer, preserving all geometry bytes. Its alternating
layer stress case falls from 73,984 to 289 entries. This is a memory tradeoff with
roughly unchanged aggregate meshing time, not runtime adoption or a total memory bound.

The [tetrahedral sign-scan optimization](TERRAIN_TETRA_SIGN_SCAN.md) reduces the
sum of fifteen fixture median meshing times by 39.6%, with all 75 paired outputs
byte-identical. This improves the isolated candidate; it is not integrated into
gameplay and does not qualify its field error, LOD or full pipeline cost.

The [native coverage transition probe](TERRAIN_TRANSITION_DECISION.md) passes 54
checks while refining a real parent into thirteen owners, editing locally and
coarsening only after refreshing the dirty parent. This supports reuse of coverage
publication; automatic distance scheduling, cave geometry and FPS remain unqualified.

The [mixed-size cut probe](TERRAIN_MIXED_CUT_DECISION.md) preserves tested open
boundaries with thirteen owners over a 256 m extent. It rejects the cave cut for
topology and exact local replacement: editing four fine regions also changes
three coarse neighbors under a fresh rebuild. Dependency bounds remain unresolved.
Full-resolution controls show those neighbor surfaces are unchanged; the
simplification changes. Expanding the synchronous rebuild set restores tested
equivalence but takes 199 ms of native work in the cave fixture, so it is rejected
as the live-edit solution.

The [publication probe](TERRAIN_PUBLICATION_DECISION.md) passes 35 checks for a
four-region edit, including actual physics queries before/after the batch swap.
It fixes duplicate-completion publication but excludes worker scheduling, mixed
LOD coverage and graphical performance. It supports reuse of this component only.
The follow-up adds 42 passing checks through the real worker and public edit API,
including completion arriving before preparation. Mixed LOD coverage, scheduling
under load and graphical performance remain unqualified.

The [bounded LOD admission experiment](TERRAIN_LOD_ADMISSION_DECISION.md) safely
falls back in 18 of 30 cases but takes up to 516 ms. It is rejected for live edits;
passing geometry checks through fallback does not qualify runtime performance.

The [controlled simplifier](TERRAIN_CONTROLLED_SIMPLIFICATION.md) preserves all
tested boundaries/components with pruning disabled. Independent sampled-distance
checks nevertheless reject 39 of 60 error settings; library-reported error alone
is insufficient for LOD admission.

The [native LOD probe](TERRAIN_NATIVE_LOD_DECISION.md) demonstrates substantial
edited-mesh reduction but rejects six component-pruning outputs. Native
simplification remains a candidate with explicit locks, pruning control and
independent shape-error qualification.

An isolated [C++ tetrahedral candidate](TERRAIN_TETRA_PROTOTYPE.md) passes the
retained cave topology and fine-partition checks. Dense sampling, geometry volume,
changed interpolation and absent LOD/error qualification keep it out of gameplay.

The [boundary/topology probe](TERRAIN_BOUNDARY_DECISION.md) preserves fine geometry
across tested partitions but rejects existing cave topology. Edited regions also
show no LOD triangle reduction. Both gate reuse of the current mesher unchanged.

The subsequent [cheap locality probe](TERRAIN_LOCALITY_DECISION.md) rejects both
extraction-only optimization and covering distant terrain with fine regions.
It measures a promising local component cost, but does not qualify a replacement.

The opt-in [reconstruction-region cache experiment](TERRAIN_REGION_CACHE_EXPERIMENT.md)
adds native parity, cancellation, local invalidation and working-set pressure tests.
Its warm reuse improves extraction, but cold/thrashing regressions and full-patch
simplification costs reject enabling it as the foundation fix. It remains outside
normal gameplay and does not change the integrated qualification status.

| Primitive | Adversarial variables | Required evidence |
|---|---|---|
| Terrain editing | Fixed local edit versus 1×/4×/16× remote edited pages; deep cavities; patch corners; cold/coarse and settled/fine destinations | Local work and latency remain bounded; exact collision/density agreement; per-patch amplification measured |
| Block meshing | Solid walls, checkerboard occupancy, alternating materials, one stair per chunk, dense stairs, slopes and windows | Bake throughput, input/output amplification, triangles, peak scratch memory and main-thread publication cost |
| Building representation | Furnished interiors, occluded rooms, many unique props, long sight lines, distant skyline | Visible geometry/objects bounded by relevance and screen error, not total city population; no missing distant substitutes |
| Vegetation | Dense ground cover plus trees, moving camera, edit storms and structure exclusions | Unaffected instances preserved; selection/upload budgets; shadow and overdraw cost measured |
| Physics/entities | Dormant population scaled separately from awake bodies, contacts, animation and effects | Dormant cost bounded; active-budget saturation visible; no silent simulation loss |
| Storage/streaming | Cold cache, reversal, repeated boundary crossing, high-speed arrival, dirty eviction and reload | Latency distributions, bounded queues/RAM, exact persistence and safe player readiness |
| Multiplayer | Increasing players, interest overlap, simultaneous edits, packet loss/reordering | Server tick cost, bandwidth, deterministic conflict outcomes and bounded catch-up |
| Endurance | Sustained mixed workload, repeated save/reload and travel loops | Memory/queue plateaus, stable latency, no degradation hidden by averages |

For each matrix row, increase one dimension at a time before combined stress.
Record actual quantities and resource saturation, not just a scene name or
success flag. Retain failed results. Do not lower visual quality, reduce world
content, weaken thresholds or drop work to turn failures green without explicitly
documenting a product-level tradeoff. Use an isolated native microbenchmark to
explain an integrated failure, not to replace the integrated test.

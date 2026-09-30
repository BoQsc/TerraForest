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

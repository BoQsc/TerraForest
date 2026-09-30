# Integrated mining pressure: foundation rejected

**Measurement correction:** the original detailed JSON checkpoints serialized
the entire accumulated trace synchronously between phases. Independent Godot
measurement confirms hundreds of milliseconds of observer overhead. The reported
353/382 ms boundary-frame stalls are withdrawn as evidence of game-engine stalls.
The corrected harness writes compact progress during capture and full traces
after capture stops. Original artifacts remain intact for audit. Native patch
costs and individual edit timings still identify expensive coarse rebuilds, but
the old frame distributions must not be used to qualify gameplay performance.

Godot 4.7.2, Vulkan Forward+, GTX 1060 Max-Q, 1920×1080 fullscreen,
full render scale, foreground/background cap 60 FPS. All three completed runs
returned failure from explicit performance gates, without script/runtime errors.
The workload is specified in [foundation qualification](FOUNDATION_QUALIFICATION.md).

| Workload | Changed edits / submitted | Travel edit p95 | Travel edit maximum | Original control median | Return control median |
|---|---:|---:|---:|---:|---:|
| 1× | 136 / 136 | 251.5 ms | 334.5 ms | 19.6 ms | 19.7 ms |
| 4× | 544 / 544 | 268.5 ms | 385.2 ms | 19.4 ms | 101.2 ms |
| 16× | 2,164 / 2,176 | 369.2 ms | 452.2 ms | 19.5 ms | 51.6 ms |

The 16× trace identifies work amplification by visible terrain patch size:

| Travel rebuild patch width | Patch count | Mean worker build time | Maximum |
|---|---:|---:|---:|
| 16 m | 2,792 | 3.24 ms | 5.54 ms |
| 32 m | 75 | 11.48 ms | 14.34 ms |
| 64 m | 147 | 38.31 ms | 52.91 ms |
| 128 m | 72 | 90.13 ms | 121.65 ms |
| 256 m | 144 | 335.17 ms | 370.31 ms |

The original control site used four 16 m patches per edit, averaging 1.92 ms per
patch. On return it used two 32 m patches and one 64 m patch per edit. This
directly demonstrates that a fixed local edit can become substantially more
expensive because the visible LOD coverage differs. The nonmonotonic 4×/16×
return latency also means these runs must not be interpreted as a clean
asymptotic curve against edit count alone.

`TerrainStream._invalidate` rebuilds intersecting visible patches up to 256 m
wide. Native terrain reconstruction samples the fine surface before simplifying
coarse patches. Their combination is unsuitable as the unrestricted interactive
edit cost model. The next implementation must decouple local edits from large
coarse rebuilds while preserving complete visual/collision coverage and seams.
Blocking input until streaming catches up would move latency elsewhere, not
prove that this cost has been fixed.

The original 16× run recorded 69, 98, 353 and 382 ms boundary intervals across
excavation, travel, return and recovery. These include benchmark checkpoint work
and are not valid standalone game-stall measurements. Engine
static memory rose from approximately 215 MB at the original control to 355 MB
after recovery. Changing residency/cache contents confound this comparison;
this is not yet evidence of a leak or a verified memory plateau. The monitor also
includes the benchmark's growing retained event buffers.

## Evidence and limits

[Summary](evidence/foundation_mining/summary.json) and compressed full reports,
frame CSVs and run logs are retained under `evidence/foundation_mining/scale_*`.
The 16× run additionally retains its exact workload source and terrain source/DLL
hashes. The earlier 1×/4× workload has the same site isolation and edit counts but
predates individual patch tracing/checkpoint output. The exploratory run used a
shared control/excavation site and is excluded from the comparison above.

These are short pressure tests of streaming terrain and vegetation, with stepped
travel through multiple biomes. They intentionally do not wait for destination
residency. Public edit calls exclude mouse capture and brush-queue delay. They
do not certify walking/vehicle behavior, furnished cities, entities, networking,
GPU headroom, power efficiency, or multi-hour endurance. Some defects are
already exposed; broader foundation qualification remains incomplete.

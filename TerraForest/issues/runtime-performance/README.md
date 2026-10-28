# Runtime performance

- Status: Improved-partial; installed and packaged walking verified.
- Updated: 2026-10-28. Baseline: `5bfe87f4`.
- User review: Not reviewed. No visual quality reduction intended.

## Changes

- Forest residency refreshes only when its cell/radius/limit changes; settled
  forests skip full-owner searches. Edit resampling and reconciliation still run.
- Ground cover skips settled scheduling and obsolete constant-density scans.
  Density, draw distance, shadows and bounded retirement remain unchanged.
- Native terrain planning computes requests and coverage from one validated
  state, rather than decoding the same dictionaries twice. No cross-frame cache.
- Static collision readiness uses the existing unloaded-region bounds tree,
  including transformed extents and empty-region handling. Structure queries
  reuse the registered model array instead of allocating it on every call.

## Measurements

Same seed-1703 disposable save, approximately 248 m of actual walking along the
same asphalt route; 8 s idle, 45 s walking, 8 s recovery. RTX 4050 Laptop GPU,
1920×1080, 60 FPS cap, offscreen/no mouse capture. Saves unchanged. AI and timing
are not lockstep; these are scoped samples, not a general FPS guarantee.

| CPU work | Before | After |
| --- | ---: | ---: |
| Forest scheduler, mean walking frame | 202 µs | 79 µs |
| Forest scheduler, mean idle frame | 135 µs | 4 µs |
| Ground-cover coordinator, mean walking frame | 181 µs | 153 µs |
| Terrain schedule/coverage/eviction, mean update | 2.20 ms | 1.93 ms |
| Native request + available-coverage microbenchmark, median | 0.324 ms | 0.219 ms |
| 2,048 collision queries against 4,096 unloaded regions | 43.37 ms | 0.66 ms |

Walking frame p95 was **21.48 → 22.20 ms**, so this is not a demonstrated overall
frame-p95 improvement. A single 199 ms baseline interval did not repeat in the
first updated run (37.5 ms maximum); its cause is not established or closed.
GPU cost is not optimized by this change.

Installed-pack repetition: 248.18 m walked, forest 76 µs/frame, cover
137 µs/frame, terrain update 1.94 ms; frame p95 21.85 ms, maximum 43.64 ms.
Both native configurations build; export validates all 14 external DLL hashes.
The read-only source-save hash and zero-cursor-capture checks pass again.
[Packaged run and summaries](../../reports/runtime_performance/20261028T181805414845Z_packaged_roads/run.json).

[Baseline frames](../../reports/runtime_performance/20261028T175902800822Z_baseline_roads/frames.json),
[updated frames](../../reports/runtime_performance/20261028T180747834274Z_optimized_roads/frames.json),
[old-pack collision benchmark](../../reports/runtime_performance/old_pack_collision_retry/model_focus_discovery.json),
[new collision benchmark](../../reports/checks/20261028T181340947816Z/console.log).

## Verification and images

- 332 planner assertions, including fused/separate equality for stationary,
  targeted, travelling and navigation-interest cases over dirty/partial states.
  [Latest planner run](../../reports/checks/20261028T181803359516Z/run.json).
- 158 cover assertions: identical settled records, edits, harvest, partial and
  reversed replies, teleport retirement, reset and retry. Tree budget checks
  include idle, radius changes, reload, resampling and reconciliation.
  [Cover](../../reports/checks/20261028T181137770427Z/run.json),
  [trees](../../reports/checks/20261028T180714976009Z/run.json).
- 58 spatial-discovery assertions, 100,000-placement metadata reload, streamed
  terrain collision, density queries, vegetation support and edit recovery pass.
  [Metadata](../../reports/checks/20261028T180942617211Z/run.json),
  [terrain coverage](../../reports/checks/20261028T181326196848Z/run.json),
  [edit recovery](../../reports/checks/20261028T180945872140Z/run.json),
  [support](../../reports/checks/20261028T180947070513Z/run.json),
  [model regions](../../reports/checks/20261028T181959238763Z/run.json).
- Earlier failed harness runs are retained under `reports/runtime_performance`
  and `reports/checks`: bridge route accidentally started under its deck; old
  mocks/signatures and obsolete immediate-retirement expectations were corrected.
  The bridge trial is not a walking-performance baseline.

![Baseline road arrival](images/baseline-road.png)
Baseline arrival near (896, 57, 1500), seed 1703. 2,963 tree roots / 376 owners.

![Optimized road arrival](images/optimized-road.png)
Updated arrival on the same route with the same tree/owner counts. Camera
position and wind phase differ slightly; not a pixel-equality comparison.

## Remaining / reproduce

Run `python tools/profile_runtime.py --slot <disposable recipe_generated slot>`;
add `--pack` for the installed build. It rejects ordinary player-save names,
uses read-only loading, records hashes/timings, and removes only its own passed
temporary derived cache. Use a populated generated test fixture with asphalt roads.

Multi-hour walking/mining/driving, maximum cities, cold fast-travel and lower-end
hardware remain unqualified. Return with repeated frame traces and finer zombie
update timing to attribute the isolated stall; do not treat an absent recurrence
as a fix. Loading/generation wall-time and GPU-bound rendering need separate
matched benchmarks before further changes. Preserve the same visual settings.

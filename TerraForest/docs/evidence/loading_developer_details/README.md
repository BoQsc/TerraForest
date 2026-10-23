# Visible loading work and TerraForest branding

2026-10-23. Gold/green TerraForest lettering is centered slightly above the
middle. The existing wide, slim progress bar stays at the bottom. A separate
scrollable developer panel is visible by default in generation, coordinator
verification/publication and ordinary saved-world loading.

The bottom bar itself now names the landscape coverage fraction required before
play, collision probes ready, the worker task, queue/in-flight/upload counts and
published cache hits/misses. Nearby-first loading counts its actual 384 m coverage
requirement; the full-map root count remains available in diagnostics. Model and
water waits identify their separate blockers. These are existing readiness gates,
not weaker conditions or a timer-based completion animation.

Both developer columns are scrollable and text-selectable. They expose stage
history with wall-clock durations, native terrain startup/bake progress, world
identity and paths, cached mesh/collision counters, derived-cache accounting,
tree/ground-cover/water state, model paging, plan cache/digest, map preparation,
photograph timings, coordinator metadata, verification results and hardware.
Values are observed, not predictions. Source durations and units retain their raw
field names. Native jobs without finer progress report their phase/worker status;
this does not pretend to expose every engine internal operation or stream stdout.
The configured log path is labeled as a setting because launchers can override it.

Developer snapshots refresh at 4 Hz using main-thread state and atomic or already
published worker counters. They never query the native terrain world mutex during
baking, scan storage, create another viewport or read back screenshots. Polling of
the gameplay loading panel stops when play starts. Stage text and bar counters
update with actual loading state; the detailed snapshot can lag by up to 250 ms.

Verification:
- `ui/`: rendered 1920x1080 wordmark placement, no overlap, slim bar, all raw fields,
  literal text safety, scroll retention, real-world diagnostic data, exact required
  coverage fraction and polling shutdown; passed.
- `generation/`: real browser creation, baking, three photographs, map caching,
  native verification and publication; passed (41.6 s whole harness, not a benchmark).
- `reopen/`: fresh process opens that world read-only, shows real readiness stages
  from 94% to 100%, hits all four map caches and preserves the canonical save; passed.

The three PNGs were inspected. This is loading visibility/UI acceptance, not a
claim that generation is faster, the world art is approved or large-world runtime
performance is qualified. Existing photograph latency, mining and storage gaps
remain tracked in WORLD_FOUNDATION_STATUS.md.

Cancellation passed from the rendered browser (`cancel/`), preserving existing saves.
The preceding headless invocation timed out because this UI harness waits for
`RenderingServer.frame_post_draw`; it was the wrong invocation, not a successful
check. Its manifest/log are retained in `cancel_headless_timeout/`.

The package was rebuilt (250,077,872 bytes) and its headless startup smoke check
passed with 14 external native libraries. Full generation and rendered UI tests
above ran from source; package smoke is a narrower startup check.

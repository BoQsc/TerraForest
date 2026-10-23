# Elapsed and estimated remaining loading time

2026-10-23. The shared bottom bar now includes elapsed and estimated remaining
time in its header. The timer runs independently of stage observations, so time
continues during an unchanged worker phase. Measured total freezes at playable
completion. Failed/cancelled operations freeze without showing success; cancelling
keeps elapsed time running and removes the ETA.

The browser stamps the operation origin, the coordinator forwards it to the
rendered generator and first game load, and each process converts its initial
carry to monotonic local duration. The cross-process origin uses Unix milliseconds
once per process; subsequent updates use monotonic ticks. Later reloads/teleports
reset the operation. This presentation is independent of authoritative world data.

ETA is explicitly approximate. It uses the slope of actual weighted progress over
a bounded recent 30-second window; after at least two seconds and two advances it
can predict remaining duration. At startup it says estimating. After ten seconds
without progress it says recalculating and withdraws the stale number. It never
counts to zero before completion. Future stages can have different costs, so the
estimate can change substantially. No claim of calibrated ETA accuracy or faster
loading is made. It uses no historical hardware measurements or storage scans.

Verification:
- `estimator/`: injected monotonic times exercise steady/changing throughput,
  stalls/recovery, late observations, handoff baseline, failure/cancellation,
  completion, formatting, future timestamps and a bounded long-run sample window.
- `ui/`: actual world load advances elapsed, finishes at 100%, freezes total and
  stops timer polling; 1920x1080 layout checks ensure timers do not overlap the
  title, button, developer panel or bar. Existing diagnostics/scroll checks pass.
- `generation/`: real browser generation/publication verifies that the coordinator,
  generator child and game launch all carry the exact same timestamp.
- `reopen/`: fresh read-only full-game load of that generated world preserves a
  simulated 15-second earlier origin through completion, hits all four map caches
  and preserves the canonical save. The fixed carry is test setup, not a measured
  generation duration. The full generation above separately validates propagation.

The first generation regression caught a JSON-number handoff bug: a timestamp was
formatted with a decimal suffix and rejected as an integer in the next process.
That failed run is retained in `timestamp_regression/`; explicit integer conversion
corrected it and the full workflow then passed. PNGs were visually inspected.

This closes the requested timer presentation. Photograph latency and the larger
world-generation, storage, mining and world-art requirements remain tracked in
WORLD_FOUNDATION_STATUS.md.

Rendered browser cancellation also passed (`cancel/`). Existing saves stayed intact.

Package rebuilt (250,742,636 bytes); headless startup smoke passed with 14 external
native libraries. Full generation and rendered timing checks ran from source.

# Loading and generation progress presentation

2026-10-23. The shared panel spans 90% of the viewport near the bottom. The bar is
18 pixels tall at 1920x1080; stage text is 17 pixels, the title 18 and percentage 20.
Cancel/quit remains accessible without the earlier tall, oversized panel. Saved
world photographs remain the background when available.

The percentage estimates completed work across weighted stages. It advances on
actual command/building/view/map counters or stage transitions, never a timer.
It is monotonic within an operation and reserves 88-94% for verification and
publication, then 94-100% for the new world's first playable load. Ordinary saved
world loading starts at zero. 100% requires the same terrain, collision, safe
spawn, model visuals, water and stable readiness gates that enable gameplay.
Failures and cancellation do not report success. A stale creation observation
cannot hide the coordinator's current verification/publication status.

Photograph preparation exposes each named viewpoint and its destination loading,
terrain/collision task counts, water surfaces and nearby vegetation counts before
capture/save. Map preparation exposes outstanding layers, saved-data verification
and per-layer cache writes. Progress detail is polled at 250 ms during those waits;
runtime data/meshing remain in existing native services. No continuous screenshot
readback, new rendering viewport or gameplay worker is introduced.

`loading_progress_ui` checks rendered placement/size, monotonic progress, reserved
completion, cancellation text and actual world-loading readiness. Browser progress
checks stale-stage rejection; actual browser generation checks publication and the
94% handoff argument. A fresh read-only generated-world reopen checks the 94-100%
transition, readiness and map caches. PNGs were inspected; the initial tall layout
and a clipped intermediate compact footer were corrected before acceptance.

The first detailed photo trace measured destination loading 10.543 s, vegetation
18.349 s and capture/save 1.194 s across three views. The per-view raw trace and
later final run are retained separately. This identifies the source of the long
wait; it does not claim to reduce it. Optimizing photograph readiness remains an
open streaming/vegetation task requiring equivalent visual coverage and new timing
evidence. Generated-world art acceptance, sustained performance, storage cleanup
and the failed mining-latency requirement remain open in WORLD_FOUNDATION_STATUS.

Final source workflow passed generation/publication, UI cancellation and fresh
read-only game reopening with all four map caches. Final photograph timings are
9.250 s destination loading, 15.133 s vegetation and 1.124 s capture/save; run-to-run
variation is not a controlled speedup claim. Inspected the final generation and
loading PNGs at 1920x1080. Native binaries were unchanged. The exported package was rebuilt (250,066,952
bytes) and its startup smoke check passed with 14 external native libraries. Full
generation/handoff qualification above ran from source; package startup is a
separate, narrower check.

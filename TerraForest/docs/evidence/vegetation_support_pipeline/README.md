# Bounded ground-support pipeline

2026-10-18. Four existing 64-point requests per wave, one owner in flight. Terrain API, native command limit, foreground admission, vegetation density, stone identity, meshes and render distances unchanged. Stable layer assembly handles out-of-order replies and partial admission. Failed results discard partial owner work and retry after outstanding replies drain.

128 targeted stream checks pass, including out-of-order replies, two-of-four admission, failure/recovery, authored support, persistent collection and teleport retirement. Integrated saved-world test uses the readonly southern_mixed_42_20261018 slot, forced invalidation before travel, fullscreen 1920x1080 at 60 FPS cap.

Vegetation settling after arrival: 5.533 seconds versus 22.033 seconds in the preceding sequential-request evidence. This is a shorter elapsed wait, not less total terrain sampling work or proof of CPU/thermal savings. Stationary frame median 16.694 ms, p95 17.943 ms, worst 34.472 ms, GPU median 8.575 ms. Screenshot readback excluded from timing. Still not locked 60 FPS.

Ground image inspected; coverage retained. Travel bounds/persistence checks pass; timings in travel.json are a short scripted 64 m camera route, not player or long-run qualification. No user saves modified.

The user's refined density direction is recorded in WORLD_BUILDING_STANDARD.md. Near/showcase density parity, subtle distant thinning, zoom-aware coverage, far transition acceptance and consistent frame times remain open. No density reduction was applied here.

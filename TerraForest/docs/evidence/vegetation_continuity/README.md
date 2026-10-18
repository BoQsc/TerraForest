# Vegetation continuity — 2026-10-18

Saved source: northern_common_42_20261018, seed 42 / generator 13, readonly.
1920x1080 fullscreen, cap 60, RTX 4050 laptop, Godot 4.7.2 Steam.

## Corrections and evidence

- NativeStaticBatch opts into a 64-byte instance format with an arrival timestamp.
  Default props retain the existing 48-byte layout. Rebuilding a page retains
  surviving identities' arrival times. Removed records are released; authoritative
  snapshots do not contain presentation state. Per-tick byte accounting includes
  the additional packet. Real-renderer test verifies these properties.
- Production woodland shader uses opaque coverage dithering over 0.65 seconds and
  distance. No transparent sorting or additional textures. Graphical pixel counts
  verify zero/partial/full coverage and the distance fade; images inspected.
- Grass fades from 36 to 56 m. Twenty-five nearby owners preload detail, before
  that visibility edge. Previously loaded layers remain until owner retirement;
  the 49-owner residency bound and 64-point sampling batch remain unchanged.
- Old 200,000-byte grass budget admitted only 3,123 of 11,298 indexed clumps in
  the first diagnostic. Grass now allows 512 pages / 4.1 MB, sufficient for the
  49-owner procedural plus authored record bound, allocated only as needed.
  Fern budget is 1 MB; other species retain 200 KB. Actual resident bytes and
  deferred page counts are in the reports. Final stationary/travel checks have
  zero budget-deferred candidate pages.
- Additional layers formerly forced all species to grass. Native deterministic
  packing now includes small fern pockets, occasional bushes/twigs and rare
  flowers without increasing candidate count or changing candidate IDs. Existing
  removed IDs and authored plants are retained. Existing procedural grass IDs can
  now represent an understory species; this is a deliberate distribution change.
- Stones, ferns, bushes and twigs cast shadows; grass and flowers do not. Existing
  tree LOD/shadow implementation is unchanged. Root AO is material shading, not a
  replacement for cast shadows. Models are unchanged.

## Checks and limits

Native scatter and ground-cover streaming/interaction checks pass, including
individual removal, collection/placement, teleport retirement and stale reply
rejection. Graphical fade test passes. The headless dummy renderer could not read
MultiMesh custom data; its failed attempt is retained and the test now explicitly
requires graphical rendering. The old density assertion failed after expanding
preload from nine to 25 dense owners; updated bounded count is 27,136 and passes.

Saved-world four-phase comparison (120 frames each, screenshot outside timing):
GPU median off 6.963 ms, understory shadows 7.796 ms, all cover shadows 10.338 ms,
off again 6.965 ms. Understory p95 frame 18.026 ms, worst 50.079 ms. There is no
claim of zero incremental cost or sustained 60 FPS. The isolated spike is retained;
this check does not attribute it to a specific subsystem.

A subsequent 64 m camera traversal at 6.4 m/s across owner boundaries preserves
saved vegetation bytes, settles with zero rejected publications and zero deferred
candidate pages. Frame p95 17.823 ms, worst 19.934 ms. This tests streaming/rendering,
not player navigation. Both tests use the actual combined saved world.

Inspected daylight images show continuous cover and more varied understory, but
open areas still have obvious repeated clumps and the overall landscape needs
human review. Tree shading, horizon ecology, final art, large-city coverage,
long-run/old-laptop thermal headroom and strict 60 FPS remain unqualified. The
existing Regional World Review launcher uses these updates without rebaking saves.

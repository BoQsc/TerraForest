# Prepared cartography - 2026-10-20

Native survey cache now includes version/seed/generator/resolution identity covered
by its digest. Corrupt and wrong-seed substituted cache tests pass. Disposable v1
cache files are ignored; authoritative world formats are unchanged. Preparation
requires disk persistence/readback, while runtime may still display freshly built
pixels when cache writing is unavailable.

Existing southern_mixed_42_20261018 was prepared read-only then verified in a fresh
1080p process. Canonical SHA256 unchanged. Cold map generation 17.799 ms, total
worker 33.675 ms; fresh-process cached worker 3.729 ms, native generation 0 ms.
These timings describe the 256x256 map, not world startup or sustained performance.

The actual world M-map interaction test passes, and its profile confirms cache_hit.
Overview image inspected: roads/public locations visible, controls and labels
readable. No live terrain-edit raster is claimed. Existing region streets are
included. The map is cartography, not the terrain/structure streaming representation.

The new-world preparation script now invokes the same verified helper on its
worker before continuing and passed Godot parsing. Full multi-minute new-world
composition was not rerun for this hook; existing-world preparation and production
map integration were executed. Whole-world preparation remains unqualified.

Next foundation gate: bounded default static-model residency through actual
populated-world travel/edit/save/reopen, preserving distant correctness.

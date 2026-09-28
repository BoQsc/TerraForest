# Dense model render pages

The first static-render residency implementation admitted an entire 32-unit
origin group as one MultiMesh. A group larger than the per-tick upload budget
could remain invisible indefinitely. Native rendering now divides each group
into draw pages. Authored IDs, group coordinates, collision/exclusion data and
the snapshot format remain unchanged.

Page capacity is the minimum of 1,024, resident-payload budget divided by 48,
and upload-payload budget divided by 48. Each page therefore fits both budgets
on its own. Page and payload limits still constrain total residency. The native
collection keeps a sorted ID vector for each authored group, allowing direct
page indexing without repeatedly walking a large ordered set during upload.
The vector adds eight bytes of ID payload per authored record; allocated vector
capacity is reported separately as `index_capacity_bytes`. It remains resident
alongside authored placement data even when draw pages are evicted.

Selection sorts at most 4,096 group bounds by distance, then admits their pages
in sorted-ID order. Groups retain conservative bounds covering all their meshes;
page order does not claim nearest-individual-object priority. The algorithm
skips unaffordable full-page ranges arithmetically and checks the final partial
page for remaining space. It does not allocate a candidate object for every
possible page. A one-record page capacity with 100,000 authored records can
therefore retain just the configured few draw pages and pending entries.

Existing batch-count statistics and limits now count render pages. In eager
mode, one page still covers the complete group and the previous immediate slot
updates remain available. Streaming transform edits within a group invalidate
only the pages containing the edited IDs; unaffected nodes and buffers remain
resident. These edits also retain the ordered index allocation. Inserts,
removals, cross-group moves and restores rebuild affected groups' indexes and
pages because sorted membership can change. Bounds refresh for an edited group
still scans that group's authored records; incremental extrema maintenance is
not implemented. Queued edited pages may briefly be invisible.

## Validation

The native placement suite passes 233 checks with real GPU readback at
1920x1080 fullscreen and 225 checks in an isolated release-DLL project. The new
fixture places 100,000 records with IDs above 32-bit range inside one authored
group. All records become resident over 98 process frames as 97 full pages and
one 672-record page, under a 49,152-byte-per-tick upload budget. GPU readback
compares the first and last record of every page with authored transforms.
The snapshot remains byte-identical.

A same-group transform edit evicts only its 1,024-record page, preserves the
other 97 render nodes and republishes with one buffer upload. Reversing it
restores the original snapshot. A 130,560-byte residency budget admits two full
pages plus the final partial page; GPU readback confirms the skipped-range
offset. A 48-byte upload budget admits five one-record pages under a 240-byte
residency budget without allocating the remaining 99,995 potential draw pages.

Further checks cover removal while old pages are pending, snapshot restoration,
a move across a negative group boundary, complete travel eviction/return, and
release of all index capacity, nodes and slots after clearing the population.
Reports and final native build hashes are in `evidence/dense_model_pages/`.
The toolchain uses pinned Zig and prebuilt godot-cpp with zero SDK sources rebuilt.
The integrated main-world regression passes 148 checks at 1920x1080 fullscreen,
including editor transforms/history, world persistence and model travel. Core
addon isolation and resource-boundary checks also pass.
The exported pack starts with eight external native libraries. Its headless
startup log includes a 101.09 ms terrain LOD scheduling/cut/eviction event;
terrain scheduling remains a separate unresolved performance issue. This is
not a graphical frame-time measurement and is retained in `pack_smoke.log`.

This is renderer residency and GPU-buffer correctness evidence. The test does
not establish frame-rate performance for 100,000 simultaneously visible models,
a detailed city, total RAM/VRAM budgets or long-run headroom. Authored data remains
in RAM; aggregate limits across assets, disk regions, model LOD and dense-scene
visual/performance evaluation remain outstanding.

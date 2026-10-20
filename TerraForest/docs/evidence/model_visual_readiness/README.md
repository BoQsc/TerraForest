# Native model visual readiness - 2026-10-20

The loading gate now checks actual native model residency and published pages
within a 128 m axis-aligned arrival extent in all dimensions. It no longer assumes
that an empty upload queue means all content is available. Unloaded regions are
queried through the existing bounds hierarchy; resident intersecting groups must
have their expected pages published. Work is per bounded group/page, not per model
instance. Conservative full-group readiness also covers group-edge pages.

The native regression covers authored-but-unpublished records, distant records,
invalid bounds, transformed collections, unloaded metadata with no queued upload,
restoration and subsequent page publication. Debug execution passes. Both debug
and release extensions built against the pinned prebuilt SDK; release execution
was not separately tested in this turn.

Actual saved-world test: 995-model manifest, central/north/south/central travel.
All four arrivals have zero missing nearby records, published native render pages,
and local collision at loading release. No failed transfers; distant data retires.
Read-only disposable clone; no player saves changed. An independent capture replay
and normal non-paged startup pass. Northern overview inspected: buildings/windows
and surrounding objects appear; this is not general landscape/art acceptance.
Capture occurs after measurement and uses an elevated overview, not a human walk.

| Arrival | Loading ms | Missing records at release | Post-admission frame p95 ms |
|---|---:|---:|---:|
| Central | 46.881 | 0 | 16.703 |
| North | 1744.749 | 0 | 16.703 |
| South | 1249.421 | 0 | 16.711 |
| Return | 748.122 | 0 | 16.691 |

Frame samples are 120 frames after admission, not travel/loading frame tails.
North and south exceed the earlier 1000 ms arrival gate; performance acceptance
remains FAILED for that bound. Do not shorten loading by removing correctness.
Paging remains opt-in. Next: attribute metadata read/transfer/publication latency
and reduce it within existing bounded native budgets, then verify the normal
populated world again. Whole visible world, distant edit correctness, high-speed
travel, arbitrary dense cities and thermal endurance remain separate open gates.

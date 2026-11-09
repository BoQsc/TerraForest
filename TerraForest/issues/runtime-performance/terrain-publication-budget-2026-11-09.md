# Terrain publication at an exhausted build boundary

Status: source correction and scoped functional checks pass; not exported or
qualified by a new whole-world FPS comparison. Stable 60 FPS remains open.
New changes are original AI-assisted 0BSD maintenance, without imported material.

The retained installed owner-index capture
`20261109T210342400008Z_destruction_index_pack`, frame 8350, reports 10.120 ms
terrain staging including 5.072 ms atomic publication. The staging budget is
2.500 ms. These are nested scopes: roughly 5.048 ms had already been spent before
the final swap. The production loop checked the budget before preparing a piece,
then immediately committed the complete batch when that piece finished. A slow
indivisible collision preparation could therefore be followed by another expensive
indivisible operation without a budget check between them.

[The staging loop](../../addons/volumetric_terrain/terrain_stream.gd) now treats a
ready atomic publication as its next unit. If preparation exhausted the slice,
publication waits for the next available slice. The complete old visual/collision
surface remains active. If budget remains, publication still happens during the
same drain call. No new queue, epoch ownership, geometry format, collision size,
quality setting or per-frame limit was introduced. Worker completion received
after preparation still follows the existing direct publication path.

This avoids stacking two expensive units after the first already exhausted the
budget. It does not make either unit interruptible or guarantee a 2.5 ms ceiling.
It can add one process frame of publication latency after an overrun; that tradeoff
must be measured in the populated world. The previous direct completion paths,
provider callbacks and collision preparation remain separate work to assess.

## Reproduction and verification

The [publication fixture](../../tests/terrain_publication_probe.gd) uses four real
native 16 m terrain meshes, live colliders and physics raycasts. The added case
finishes worker results early, then injects a delay into the last completed
preparation unit. The delay exceeds its configured slice and is not a performance
benchmark. All original publication assertions remain.

- Old source plus new regression: 6 of 50 assertions fail, reproducing premature
  publication relative to the exhausted budget. This does **not** mean the old
  code switched only part of the surface; it switched the complete surface too soon
  for the new scheduling expectation.
- Corrected source: all 50 pass. The prepared batch remains pending; every old
  collider still answers physics queries. The following slice switches all four
  regions and increments the revision once. An ample-budget batch publishes in
  the same call, and later drains cannot publish it again.
- Existing stream coverage and edit recovery checks pass, including real boundary
  coverage, rejection recovery and continued edits. No error or leak diagnostics
  appear in the successful logs.

[Exact receipts and hashes](terrain-publication-budget-2026-11-09.json).
The short headless checks used below-normal process priority while user gameplay
was open. Their timings are not uncontended FPS evidence. No rendered capture was
made for this change; visibility flags and real physics queries establish only the
scoped atomicity contract, not visual-quality or whole-world acceptance.

## Resume and remaining work

At the original capture this correction was not installed. The later player trial
was committed separately as `dd78a924`; the subsequent export after `17ef0690`
includes this correction and the animation-cache fix. The installed PCK is
`914a3acb700d8cad18bffb7b6d64c5a305868c09a069bf9520c044686bca0ebe`.
The capped grounded-walking/three-barrel/save/shutdown fixture passes in
`reports/performance_changes/20261109T222259936532Z_animation_guard_installed_capped`.
This does not isolate the terrain correction's timing or close its remaining gates.

When an uncontended test window and a package containing only authorized changes
are available, repeat the default-world three-barrel and normal movement captures.
Measure atomic/staging frame tails, edit-to-visible latency, damage, terrain/cover
continuity, save/shutdown and recorder-off pacing before claiming a frame-time win.
Also run the populated vegetation-edit fixture. This is deferred verification, not
completion. Rendering waits, physics catch-up, collision cold work, collapse,
pursuit, water boundaries and memory endurance remain open.

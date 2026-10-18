# Regional road travel, 2026-10-18

The saved 23-building profile-12 world completed a continuous player sprint from
100 m west of the central site to 85 m east of the western site. Initial staging
uses one teleport; the approximately 572 m journey then uses ordinary player
movement. No position corrections during travel. Save writes disabled.

Actual graphical check: 78.87 s including loading/shutdown, 1920x1080 fullscreen,
60 FPS cap, vegetation/ground cover/actors enabled. 115 half-second samples:
zero loading, zero terrain collision-not-ready; one initially airborne sample.
Frame p95 17.543 ms, maximum 19.169 ms. Arrival screenshot inspected.
This is not strict 60 FPS qualification, all-route coverage, vehicle validation,
a long-run thermal test or proof the intermittent frame issue is resolved.

The separate generated-field check covers four seeds, four roads per seed, three
lanes at two-metre spacing: 18,546 samples, maximum grade 0.2131. All samples paved.
It excludes authored edits, actual collision meshes and streaming. An initial
harness attempt exceeded the 64-point query limit and was corrected to batch queries.

Reproduce with `python tools/check_regional_travel.py` after closing competing games.
The prepared regional_districts_20261018 save is required. The arrival marker alone
asserts reaching the approach; inspect telemetry separately for frame/loading quality.

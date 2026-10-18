# Settlement road foundations — 2026-10-18

Newly authored settlement roads use a one-metre asphalt bed over mineral support
that extends one metre beyond the pavement and tapers over a twelve-metre shoulder.
Support edits are additive only and are inserted before every asphalt edit. Existing
building foundation cuts and road-core clearance remain responsible for excavation.
The combined protection bounds include wider support and slope-cap elevation.
Paving counts retain their meaning; support sections count as foundation segments.
The 256-section/world-boundary limits still reject oversized authoring plans.

Regional placement now accounts for the actual eastern street edge. It reserves the
connector's four-metre half-width plus two metres separation, while preserving at
least the prior twelve-metre building setback. Previously the northern cross-street
was only two metres from a parallel arterial connection at a different grade;
excavation overlapped. Ordinary one-street building layouts retain their setback.

Native overlap regression checks two nearby roads at different heights: the lower
road must not excavate the upper bed. Native paving/material tests pass for four
rotations and wide streets. Regional connection/placement tests pass.

Visual review rejected two intermediate layouts, despite their centerline walking
checks passing: broad support clearance cut a neighboring bed, then the overlapping
parallel road cores remained visible after support became additive. The final
implementation addresses both causes. Intermediate embanked_district and
road_shoulders saves are diagnostic drafts, not the recommended review world.

No additional runtime processor or renderer: these are offline plans executed through
native terrain edits and persisted as normal terrain pages. Larger edited footprints
and additional preparation work are expected; no broad performance or thermal claim.

Final integrated evidence: connected_district_42_20261018 created and reopened
successfully. Graphical 1920x1080 review passed and north.png was inspected. All eight
northern street waypoints then passed on foot, including return to the arterial;
55.27 seconds including startup, movement p95 16.904 ms, maximum 18.434 ms. The roads
are separated; the height difference still produces an excavated lower connector
beside the higher district. The raised pad, repetitive buildings and unfinished
landscaping remain visible. This does not qualify all routes, seeds or long runs.

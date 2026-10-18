# Northern neighborhood planting — 2026-10-18

Review source: planted_neighborhood_42_20261018, generator 13, seed 42.
Play Regional World Review.cmd now creates a separate editable v7 copy. Existing
v1–v6 review saves and the source remain intact.

The native candidate generator now supports up to 32 authored grove regions.
They use the same stable candidate IDs, tree streaming, LODs, terrain/structure/
water exclusions, trunk collisions and harvest state as the existing forest.
The default remains unchanged; older archives restore an empty grove component.
The small region configuration is saved with the world through a pure native
validator. No per-tree script nodes or separate decorative-tree implementation.

Four 16 m-radius groves flank the northern streets. The actual saved world
restores 20 accepted trees (6/5/5/4). Two planted beds retain 196 and 211 native
authored ground-cover instances, including existing bush/flower/dry-wood species.
Their spacing is unchanged from the woodland review. An initial 32-by-32 proposal
exceeded the 256 authored-instance per-cell bound; that failed staged world was
not published. The northern beds now use 16-by-16 candidates (roughly 7.2 m square).
The global 100,000 and per-cell 256 authored limits remain unchanged. This does
not qualify arbitrarily dense city landscaping or solve vegetation region paging.

Native deterministic/invalid-input checks pass. Full generation and a separate
process compare saved component signatures, including grove configuration.
Actual-world checks restore the four exact regions and both beds, harvest one
live grove tree for four wood, stream its owner again and reject duplicate harvest.
The separate disk-harvest test restores grove configuration and harvested exclusions
and verifies removed trunk collision. An older pre-grove save loads unchanged.
Harvest calls exercise the production coordinator, not mouse targeting/combat.

Overview, bed and roadside grove images were inspected. Trees flank the roads,
and the bed has dense mixed plants near the buildings. An initial bed view looked
at a wall; the corrected view is retained here. The location still needs intentional
public-space design and broader landscape continuity. It is not overall world-quality
acceptance, and no new vegetation art quality claim is made.

The normal-input continuous sidewalk loop reaches all seven waypoints at fullscreen
1920x1080, cap 60: p95 17.14 ms, worst 19.63 ms. Whole run 60.49 s includes loading.
This is a short route, not sustained 60 FPS, GPU headroom, thermal or vehicle-turning
qualification. Screenshot HUD readings include camera changes/readback; they are
not the timed traversal measurement. Earlier entrance tests remain evidence for
building geometry; entrances were not all rerun in this planting pass.

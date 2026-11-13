# Terrain-reactive volumetric water implementation plan

Started 2026-11-13. Status: active. User authorized completion, including major
changes where required. [Diagnosis and acceptance contract](water-assessment-2026-11-13.md).

## Milestones

- [ ] M1: Replace lossy density sampling with occupied-volume boundaries;
  qualify thin films, joined cells, sides/undersides, terrain/building clipping,
  stacked spaces, region seams and mesh/query agreement.
- [ ] M2: Complete conservative terrain-edit response, displacement and wake
  propagation; mining, blasts and solids use the water service.
- [ ] M3: Verify bounded scheduling/publication, idle work, pause, concurrency,
  interrupted saves, reload, unavailable regions and ocean edges.
- [ ] M4: Inspect actual barrel/lake and mining/deposition imagery; measure
  settling latency and frame tails in the real world, including combat.
- [ ] M5: Build matching configurations, package and verify default behavior;
  preserve saves and present evidence plus any remaining human-review limits.

## Working record

M1 in progress. Reuse existing convex clipping primitives where their geometry
matches authoritative capacity; do not increase lattice resolution or thicken
water to hide missing surfaces. Preserve existing failures as baseline evidence.
No runtime acceptance claimed yet. Work remains on master in the main checkout;
unrelated hub UID files remain untouched. No parallel agents requested.

### M1 development evidence

The candidate now extracts convex occupied boundaries, removes shared wet faces
and buried terrain/structure contacts, and splits unequal-height boundary edges.
Source debug library only; installed package is unchanged.

- `reports/checks/20261113T095017755951Z`: material-surface regression passes,
  including 30 thin-film offsets, mesh/query publication and a real bucket pour.
  Fixtures now ignore empty packets when comparing visible geometry and use the
  current full 1 m3 bucket rather than the rejected legacy 10 L item.
- `reports/checks/20261113T095148806979Z`: continuity passes all 510 occupancy
  patterns plus cross-region/vertical cases. Directed-edge closure and triangle
  adjacency distinguish coincident edge/point contacts from open-face connections;
  vertex-position welding incorrectly merged the former. The old removed
  vertical-repair API was replaced by the current explicit settling API.
- `reports/checks/20261113T095044346611Z`: real native-terrain crater passes;
  7,619,860 ml retained, 38,868 us total settling, max solve call 675 us. Maximum
  mesh call is 12,746 us: performance acceptance remains open.
- Natural terrain contacts pass in `20261113T095215950930Z`; cached building
  occupancy passes in `20261113T095242678724Z`; analytic pyramid contact and
  canonical migrated save roundtrip pass in `20261113T095535348027Z`.
- Large captured-envelope topology remains **failed**, most recently
  `20261113T095522055875Z`. It exposes residual boundary conformity problems and
  a difference between stored quantity and reconstructed occupancy. Per-packet
  geometric-volume diagnostics are being added to locate the cause. Earlier
  rejected runs remain retained under their original check directories.

M1 is not complete. Next: close captured shoreline geometry and quantify legacy
over-capacity/zero-capacity quantities, inspect rendered evidence, then continue
M2. Do not enable default settling or claim a performance/visual pass yet.

Every milestone will record commits, checks, evidence paths, failures and the
next dependency here before advancing. Visual success requires inspected images;
performance success requires measured frame costs, not just a solver deadline.

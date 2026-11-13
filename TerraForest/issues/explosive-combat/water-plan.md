# Continuous volumetric water replacement

Status: active, restarted at the user's explicit request on 2026-11-13.
This document completely replaces the previous implementation plan. Historical
plans and failed experiments remain in Git history (through baff9588) and the
existing issue evidence; they are not acceptance evidence for this replacement.

## Required result

Water is a connected three-dimensional occupied volume with one continuous
triangulated boundary, matching the user's isosurface reference. Its visible
boundary must not expose individual storage-cell boxes or horizontal sheets.
A level lake surface is expected; unsupported sheets after excavation are not.
Ordinary barrels, mining and deposition must update water without opt-in flags.
Water must fit the authoritative terrain, including caves and overhangs, conserve
finite quantities, remain stable across save/reload, and have measured bounded cost.

## Architecture and exclusions

- Authoritative terrain density and solid geometry define available 3D space.
  Floor/ceiling-only approximations cannot be the general occupancy authority.
- Finite water quantities and connectivity are separate from surface extraction.
  A shared implicit field and the existing terrain surface infrastructure are the
  initial meshing direction. No visible per-storage-cell boundary renderer.
- Updates are edit-triggered equilibrium transactions with barrier/spill handling,
  not prolonged pairwise diffusion. Settled water performs no redistribution work.
- Changed geometry, surface queries and immersion publish a consistent revision.
  Worker jobs have explicit memory/work limits and retain valid prior state on failure.
- No full fluid dynamics, foam/splash feature expansion or microscopic-film
  topology project. Sub-render-resolution amounts remain conserved in storage;
  claiming every millilitre has independently visible geometry is not a requirement.
- Do not claim marching cubes alone supplies occupancy, connectivity or motion.

## Execution gates

- [ ] 1. Recover a coherent source baseline. Audit and remove the rejected boundary
  renderer and unqualified diffusion experiments; preserve unrelated work, saves,
  evidence, and only independently useful verified infrastructure. Rebuild matching
  source binaries. Do not silently reset the whole dirty checkout.
- [ ] 2. Prove a continuous implicit boundary. Native extraction must show a rounded
  volume, partial sloping contact, an exposed cut, and a cavity/overhang without
  cell terraces. Use the actual terrain density path for integrated contact tests.
  Inspect shaded and wireframe captures, seams and solid exclusion. A sphere-only
  demonstration does not close this gate.
- [ ] 3. Implement finite-volume terrain response. The actual barrel/lake case is
  primary: newly connected excavated space fills appropriately, solids exclude
  water, deposition displaces it, and isolated basins stay isolated. Verify breach,
  split, spill threshold, sealed cavity and blocked displacement cases. Preserve
  exact quantity; explicitly retain unresolved quantities instead of deleting them.
- [ ] 4. Qualify runtime behavior. Test interrupted edits/saves, reload, streaming,
  stale worker results, unavailable regions, region seams and ocean boundaries.
  Measure water CPU/GPU cost separately, peak memory, triangles, first visible
  response, final publication latency and frame tails against the same baseline.
  Initial targets: no idle solver work; <=1 ms main-thread water update budget;
  typical local barrel response within 250 ms after terrain publication. Report
  measured violations and fix their cause; do not silently relax these targets.
  The full scene must retain the project's 60 FPS frame budget (16.7 ms), including
  representative combat. A stationary HUD FPS reading is not proof.
- [ ] 5. Replace the default and deliver. Inspect actual gameplay above/below water
  before/after barrels, mining and deposition; verify ordinary launch behavior,
  existing-save migration, debug/release parity and the installed package. Commit
  focused verified changes and explain the remaining scope and human visual-review
  limits. Do not mark complete while required behavior or evidence is missing.

## Current state and next action

No replacement gate is complete; the installed package has not been updated.
The rejected cell-boundary mesher and horizontal diffusion accelerator have been
removed from the working source. The prior continuous extraction adapter is
restored, retaining immutable worker/publication infrastructure. The optional
legacy settling path still fails convergence and is not the replacement solver.

A new bounded native extractor uses the existing terrain surface infrastructure.
The closed-basin reference consumes actual TerrainCore density samples, preserves
an authoritative 40,000,000 ml quantity and recomputes its level after excavation
and deposition. It is not connected to LakeWorld gameplay. Open boundaries and
separate basins return unresolved status with quantity preserved; they are not
silently represented by artificial walls or a shared water level.

Next required implementation is the general basin connectivity/spill transaction
and its terrain-worker/LakeWorld integration. Keep the reference as a correctness
comparison, not a whole-world runtime design: repeatedly remeshing during a level
solve is not the final large-lake capacity evaluator. Then qualify the actual
barrel case, consistent immersion/query publication, saves and runtime costs.
There is no evidence yet that the user's ordinary gameplay problem is fixed.

### Replacement evidence, 2026-11-13

- `reports/checks/20261113T130056209004Z`: `water_implicit_proof` passes.
  Sphere, native basin, excavation and overhang use continuous triangulated
  boundaries. Agent inspected shaded cutaway and overhang wireframe captures.
  Cutaways hide half the terrain only for inspection; water occupancy uses the
  complete terrain. This is opaque geometry inspection, not water-material approval.
- Closed basin at 40 m3: level 4.228893 m; excavation 4.190556 m; added overhang
  4.301048 m. Integer quantity stays 40,000,000 ml. Rendered boundary volume is
  within 0.00014 m3 of 40 m3 in these cases. Reference solve was about 22-25 ms;
  field extraction about 1 ms. These exclude terrain sampling and GPU cost.
- Initial transparent proof `20261113T124818815446Z` exposed contact/shading
  artifacts. Opaque captures do not resolve that presentation requirement.
- Cutaway capture attempt `20261113T130004883781Z` failed due to a freed scene
  node retained in the fixture list; corrected in the later passing run.
- Worker publication `20261113T131116560844Z` passes with the rebuilt source and resolved water geometry;
  the earlier 1-litre fixture produced empty geometry and failed picking. Small
  unresolved films remain explicit rather than silently claiming full coverage.
- Legacy settling `20261113T130640190896Z` fails convergence and connected-layer
  distribution. Preserve that failure; no default rollout or performance claim.
- Remaining gate-2 work: integrated region seams, quantitative solid exclusion/
  contact-gap checks and the ordinary transparent water material. Gates 3-5
  remain open, including actual barrel response and measured gameplay performance.

## Evidence rules

Use the existing checkout and bounded artifact lifecycle. Preserve failed images
and logs. Compare identical cameras/resolution and separate algorithm timings
from rendering timings. Record actual command, revision, scene and acceptance
scope. Test passes never override visibly broken water. Existing failed evidence:
20261113T121519182354Z (120-second unsettled barrel water),
20261113T122134864331Z and 20261113T122628097255Z (60-second settling failures).

Native convex occupancy probe also passes after recovery. Godot editor import
`20261113T130408650844Z` generated the new script UIDs. Debug DLL SHA-256:
`3fc9087fc90b06e6f779e655f03455ab789f141b3cdef59d5a4d13be534f1daa`.
New native reference code and proof fixture are original 0BSD work; existing
terrain code and development screenshot provenance are preserved.

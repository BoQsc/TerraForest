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

No replacement gate is complete. The checkout still contains rejected experiments;
source debug is experimental and the installed package has not been updated.
First audit the runtime diff, restore the previous coherent extraction adapter,
and build a small continuous-field proof before integrating a new equilibrium
service. Stop and reassess if the proof exposes cell-shaped water or fails contact.

## Evidence rules

Use the existing checkout and bounded artifact lifecycle. Preserve failed images
and logs. Compare identical cameras/resolution and separate algorithm timings
from rendering timings. Record actual command, revision, scene and acceptance
scope. Test passes never override visibly broken water. Existing failed evidence:
20261113T121519182354Z (120-second unsettled barrel water),
20261113T122134864331Z and 20261113T122628097255Z (60-second settling failures).

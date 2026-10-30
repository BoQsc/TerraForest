# FPS / overview rendering and modular runtime

Status: **partial implementation; the requested whole-project overhaul is open**.
2026-10-30. Preserve authored/save data; improve representation, not world rules.

## Required architecture

- One canonical editable world. Far meshes are derived views, never separate
  terrain, non-destructible replacement buildings or authoritative entities.
- Separate view detail from physics, interaction and navigation residency.
  Zoom must not hydrate the entire world into live bodies or editable regions.
- Native bounded selection, hysteresis, old coverage until replacements are ready,
  immutable worker inputs and revision-checked publication. No main-thread waits
  for streaming work during normal movement.
- Persist/cache canonical versioned identities; invalidate only changed owners.
  Explicit failure and resource ceilings, not silently missing silhouettes.
- Versioned module contracts. Native/compute implementations may change behind
  them; save identity, readiness and mutation rules remain host-owned.
- Keep the 4 GiB GPU, provisional 6 GiB private RAM, 5 GB distribution and 3 GiB
  terrain-cache targets. A higher view does not lift these ceilings.

## Implemented foundation

- Native terrain planner accepts an independent render position/projection scale;
  existing physical/travel/interaction requests and activation priority remain.
  All 64 root regions stay requested, and incomplete refinements retain old cuts.
- ESC → Player → optional World overview preview: collision-swept orbit camera,
  exponential wheel zoom, 3.4–1800 m; movement still controls the real player.
  No remote editing. Camera-specific atmosphere avoids distant fog washout without
  changing the normal environment. Existing third-person view remains available.
- Loaded trees use their existing native pixel-based LODs from the overview camera;
  trunk collision and procedural ownership stay near the player. This does not
  generate never-visited forests or extend every medium object's representation.
- Prior native building horizon (`083917a7`) supplies real, compacted, destructible
  block geometry across the saved world without loading its far editable regions.
- Explicit trusted module registry and independent vehicle adapters, typed binary
  fleet state and per-kind parked rendering: [vehicle API](VEHICLE_PACKS.md).
- Generation verification uses the native occupied-region index rather than
  serializing the full resident world plus scanning 4,096 possible regions.
  Existing digests remain identical for the previous generated-world domain.

## Open milestones / return criteria

1. **World-wide trees and medium objects.** Canonical deterministic far-instance
   pages, exact road/lot/water/harvest exclusions and edit invalidation are missing.
   Build this before claiming strategy-scale forest coverage. Require cold/warm,
   never-visited, fast driving, harvest/mine/place, save/reload and budget evidence.
2. **Seamless terrain/mesh transitions.** Current coarse terrain and residency
   boundaries remain visible from overview, including large flat grey patches in
   the populated fixture. Diagnose actual geometry/material coverage independently
   of the planner's root-count assertions. Requires a compatible volumetric
   transition solution (including edited caves), not a heightmap covering edits.
   Require continuous zoom/orbit recordings, seam/error checks, and user review.
3. **Medium props/vehicles.** Furniture, parked vehicles and boulders still have
   local representation limits. Add exact lightweight render-only tiers before
   advertising all medium/large objects at arbitrary distance. Measure dense worlds.
4. **General module host.** Only vehicle providers are integrated. Generator,
   biome, terrain, vegetation and other service providers, dependency negotiation,
   migrations and native-pack deployment are not implemented. Reuse host ownership
   and version/cache identities when adding them; no arbitrary automatic code scan.
5. **Generation/loading architecture.** Indexed verification is one measured
   improvement, not a pipeline rewrite. Existing native baking/worker stages remain.
   Next: cold creation → save → first play traces, parallel task dependencies and
   versioned derived-asset publication/cancellation. Require whole-workflow timings,
   determinism, unchanged save bytes and no new cursor capture.
6. **Qualification.** Dense cities, maximum terrain edits, long-session travel,
   4 GiB hardware, high-refresh/4K, camera sweeps near unloaded geometry and custom
   vehicle movement envelopes remain open. Microbenchmarks and one fixture cannot
   establish perfect frame times, universal LOD continuity or visual acceptance.

The preview is intentionally opt-in until these gaps are addressed. Continue at
milestone 1; do not close this contract because the current engineering tests pass.

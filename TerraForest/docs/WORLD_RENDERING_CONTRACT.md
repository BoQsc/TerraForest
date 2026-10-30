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
- Actual coverage is now a play gate: all 64 roots must have published geometry.
  Missing coverage takes precedence over optional refinement after local physical
  activation. Coarse 64 m owners drop only nonexistent internal slab boundaries;
  exact outer seams, excavations and fine collision remain protected. Derived
  cache version changes without migrating canonical world data. See issue evidence.
- ESC → Player → optional World overview preview: collision-swept orbit camera,
  exponential wheel zoom, 3.4–1800 m; movement still controls the real player.
  No remote editing. Camera-specific atmosphere avoids distant fog washout without
  changing the normal environment. Existing third-person view remains available.
- Natural tree ownership now covers all 1,024 world owners before play. Stable
  identities use the existing native pixel LOD selection and 12-triangle far tier,
  with at least 3,500 m visual range; the host's coverage bounds extend it in 512 m
  bands when an edge/outside-world view needs more, before the shader fade band.
  Trunk bodies remain bounded to 256 within 96 m of the
  physical player. Movement no longer evicts or resamples accepted forest owners.
- Native surface pages use the existing checked, quota-controlled binary cache.
  Keys include exact candidate coordinates and local terrain dependencies; unrelated
  edits reuse them, local edits invalidate them, active input bypasses optional disk
  work. At most two surface requests are in flight and eight owners admitted per
  frame. Harvest and per-root edit exclusions remain authoritative.
- Prior native building horizon (`083917a7`) supplies real, compacted, destructible
  block geometry across the saved world without loading its far editable regions.
- Natural boulders now have independent whole-world ownership, native near/far
  fracture tiers and complementary shader blending. The active render camera is
  separate from player-local collision and grass focus. Existing harvesting,
  support removal, damage and save identities remain shared. Forest and boulder
  support probes share bounded cached requests instead of duplicating dispatch.
- Forest exclusion now uses native read-only archived occupancy, not whole unloaded
  building regions. Worker-decoded column masks and compound-model BVHs share the
  existing bounded archive reader; a 32 MiB / 256-page LRU admits at most two reads.
  Missing pages retain the previous accepted forest; no far physics or editable
  record hydration. Direct construction checks remain fail-closed.
- Explicit trusted module registry and independent vehicle adapters, typed binary
  fleet state and per-kind parked rendering: [vehicle API](VEHICLE_PACKS.md).
- Native parked-vehicle horizon retains all known fleet records in 256 m cells,
  with 128-instance pages and existing imported geometry LODs. Changed identities
  drive bounded uploads; near/body handoff publishes complementary ownership in
  the same frame. Physics remains local, far shadows are disabled. Known saved
  prototypes/coverage are part of the play gate, including never-near vehicles.
- Ranger's far prototype now consolidates its 32 source parts into one opaque
  material group offline. Exact base attributes/topology and all distinct imported
  LOD thresholds are retained in a checked binary resource, refreshed before
  export. Near/physics meshes remain unchanged. The optional adapter hook keeps
  original parts for other providers; no gameplay GPU readback/rebake is added.
- Generation verification uses the native occupied-region index rather than
  serializing the full resident world plus scanning 4,096 possible regions.
  Existing digests remain identical for the previous generated-world domain.

## Open milestones / return criteria

1. **Forest continuity and medium objects.** Exact read-only far exclusion pages
   replace the unloaded-region shortcut. Native debug/release fixtures cover
   same-region openings, negative boundaries, transforms, incremental admission,
   edits, cancellation and pressure (100,000 model instances / 270 sparse owners).
   The populated installed world retains all 8,742 tree identities through actual
   block-region admission/retirement, reload, harvesting and excavation. This is
   parity with resident occupied cells/proxy AABBs, not exact mesh intersections.
   Dense mixed model-streaming/water-change endurance, visual transitions and
   arbitrary oversized query batches remain unqualified. Repeated teardown exposed
   a retained exclusion payload in the worker-to-query handoff. That path now uses
   owned native data instead of a Godot object inside a cross-thread Variant.
   Twenty-four cancellation/consumption cycles per native configuration and two
   consecutive installed cold/warm runs release all pages without ObjectDB warnings;
   this does not qualify arbitrary mixed-world lifetime endurance.
   Boulders now have independent far representations; other medium props remain.
2. **Seamless terrain/mesh transitions.** The large grey patches were mostly
   absent geometry, not simply bad transition surfaces: only 37/64 roots existed
   after 30 seconds in the previous fixture. Whole-world readiness and cheaper
   coarse owners address that demonstrated failure. Continuous transition quality,
   dense edited-world budgets and physical held-input/endurance still require
   qualification. Requires a compatible volumetric
   transition solution (including edited caves), not a heightmap covering edits.
   Require continuous zoom/orbit recordings, seam/error checks, and user review.
3. **Medium props/vehicles.** Furniture/other props still have local representation
   limits. The native read-only model-render page primitive is now implemented:
   exact checkpoint reads decode compact ordered transforms on the shared archive
   worker; the main thread can publish at most 1,024 instances per page using the
   original mesh, materials and imported LODs. No far canonical/physics hydration.
   Synthetic debug/release checks cover 100,000 records, affine transforms,
   historical versions, cancellation and destruction. This is not yet connected
   to main-world prop rendering. Next integrate one visual ownership policy,
   global memory/upload budgets, authored-change invalidation, collection resets
   and a real coverage play gate; then prove save/reload, dense-world cost and
   uninterrupted travel/zoom. Do not substitute successful primitive tests for
   those missing integrations. Details: issue `model-render-pages-verification.json`.
   Parked vehicles now retain world-wide render ownership; debug/release
   native pressure and installed four-Ranger loading/handoff checks pass. The
   65,536-record test uses one box, not 65,536 full cars. Ranger's far prototype
   is now consolidated from 32 parts to one; a same-process actual-car A/B retains
   4,096 instances with 64 rather than 2,048 draw calls, and 0.375 rather than
   12 MiB transform capacity. This is not total GPU memory: the shared derived
   mesh adds its own fixed cost. Near handoff bursts, mixed-world GPU cost and
   shadow/geometry transition continuity still require qualification. Return with
   full-prototype pressure, continuous drive/zoom evidence and sampled budgets
   before claiming cheap seamless fleets. No automatic custom-pack LOD baker.
   Isolated actual-car baseline now covers 64/1,024/4,096 Rangers: the 4,096-car
   overview costs 2,048 draw calls, GPU/render-CPU p95 4.96/3.48 ms; a close
   1,024-car frame reaches 76.60 ms. Not populated-world performance acceptance.
   The first consolidation candidate regressed GPU work by double-applying local
   scale to LOD thresholds; it was rejected. The corrected baker keeps the
   MultiMesh parent-scale policy and all distinct imported thresholds. Evidence,
   rejected runs and final packaged comparisons are retained in the issue's
   `vehicle-consolidation-verification.json`; no universal GPU speedup claim.
   Add the remaining exact lightweight prop tiers before advertising all
   medium/large objects at arbitrary distance. Boulders no longer
   share local grass ownership. The earlier 100 km/h sweep reported up to eight near
   and 33 visible ground owners missing; grass continuity remains unresolved.
   Extend independent medium-object visibility without expanding full grass/physics globally.
   Measure dense worlds and require continuous driving/zoom/edit/reload evidence.
4. **General module host.** Vehicle providers and a narrow data-only
   [door-content contract](DOOR_CONTENT.md) are integrated. Generator,
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

The overview camera is intentionally opt-in until these gaps are addressed; natural
forest, boulder and known parked-vehicle coverage are enabled in ordinary world
launches. Continue with medium-object
coverage and transition qualification; do not close
this contract because the current engineering tests pass.

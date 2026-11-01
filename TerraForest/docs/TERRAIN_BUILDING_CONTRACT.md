# Terrain and building contact contract

2026-10-30. Required for generated and authored sites. This complements
[world quality](WORLD_BUILDING_STANDARD.md) and [the preserved lattice and free
player building rules](PLACEMENT_STANDARD.md). Engineering validation and human
visual approval remain distinct. No existing save is regraded.

## Failure mechanism

The former foundation check sampled support below the lowest cell and room air
half a metre above a cell. A one-cell apron could have no room-clearance samples.
Both tests could pass with soil crossing the visible surface. Road-style capsule
ends also extrapolated driveway grades backward underneath level aprons.
Material-based edit ordering could place paving after underground excavation.
These are independent causes; a different soil offset alone is insufficient.

## Shared rules

1. Blocks keep their exact integer coordinates and native shape/orientation.
   `terrain_contact.gd` owns the soil datum: declared at-grade floors receive a
   0.125 m reveal. Ground/base/sample datums must agree. A recipe cannot override
   this with a private inset. Underground floors require explicit excavation.
2. Survey the entire occupied footprint and apron before mutation. Use the
   prepared soil height in the existing 2 m fill / 3 m cut budget. Survey the full
   pedestrian and vehicle approach width at half-metre intervals, including the
   changed endpoint height. Reject/relocate failures; do not increase the budgets.
3. Building approaches use level capsule ends. Their slopes stop at the declared
   endpoints, preventing backward slope extension into floors. Existing road
   packets retain their original through-join behavior. New native profile bits
   are explicit: 1 rectangular, 2 level ends, 4 subtractive clearance, 8 arched.
   An arched cut is exactly profile 12 with no shoulder or curve coefficients;
   its rounded roof is clipped at the authored floor, including exact voxel-cube
   removal. Width is at least 1.5 m; clearance is between one and 1.75 widths.
   Unknown bits and invalid geometry fail before edits. Arches are excavation,
   never support/fill operations or a different floor-grid datum.
4. Native block convex geometry supplies exposed surface probes, including
   half-slabs, plates, stairs and all supported shape mounts. Fully covered joins
   are excluded. Full flat cells receive nine corner/edge/centre probes; other
   shapes receive a bounded eighth-cell grid. There is no separate test-only
   floor outline or civic exemption.
5. Compile the lowest exposed top in each column into bounded rectangular
   clearance runs, with 0.125 m lateral overlap and soil reveal. These are
   **subtraction only**: they cannot refill a void or repaint the remaining soil.
   Apply them as part of the generation plan, before any building publication.
   Covered lattice corners retain the vertical clearance plane; their air values
   must not be clipped to the distance from a narrow mask edge, which would move
   the interpolated zero surface upward. These operations do not run when a
   player places individual blocks or opens a save.
6. Apply soil/support beds, paving, underground excavation, then exposed-surface
   clearance. No later material pass may refill an earlier protected interior.
   Cache identity must change when geometry, these rules or the native binaries
   change. Save the resulting authoritative terrain; never repair on load.
7. Before publication, require foundation support and bounded deep continuity,
   clear interior samples, and nonnegative interpolated density 0.02 m **below**
   exposed tops. Sidewalk plates use the same surface gate. Report a failing world
   coordinate. A failure prevents publication; an absent, stale, timed-out or
   oversized scan is not a pass. Existing epoch/revision ownership remains.

The surface cache is bounded at 1,048,576 points per prefab; native pages contain
at most 512 points and asynchronous scans at most 4,096. Clearance authoring is
bounded at 4,096 runs per asset and the existing 16,384 master-edit limit. This is
offline/placement work, not a new frame-loop scan or terrain deformation system.

Grounded standalone props use `NativePrefabPlacement.ground_model_samples` through
`foundation_check.begin_ground_models`: real transformed visual/collision bounds,
half-metre support and interior grids, the same deep-support/epoch/revision gate.
The API bounds 64 attachments, 256 model collections and 4,096 probes; unsupported
frames or oversized geometry reject. It is not a foundation rule for furniture
attached to upper floors. Model-only prefabs are atomic native transactions;
empty prefabs still reject. Existing overlap, envelope and admission rules apply.

Upper-floor props can use `foundation_check.block_model_support`: the same native
transformed-bound sampler at 0.02 m below the base, checked against actual native
block solids plus clear interior samples. The default terrain-support depth stays
0.25 m. Invalid depth, missing support or intersecting blocks reject publication;
thin deck plates are not replaced with thicker floors to bypass this check.

## Verification and approval

`tools/export_pack.py` requires `tools/check_building_standards.py` to pass.
That gate runs `terrain_block_contract` in source and an isolated release-only
project, then `terrain_block_catalog` against the current native final field.
For individual diagnosis, use `tools/run_godot_check.py`. The former deliberately reproduces coplanar soil,
checks rejection and valid contact, shape mounts, grade caps and edit ordering.
The latter exercises the production foundation state machine over the real
native final field for civic, approved city and neighborhood recipes on seeds
1703 and 42, including sidewalks. Run affected preparation, terrain, placement
and package regressions after native changes.

Then generate a fresh complete world, restore it in another process and walk
street → threshold → interior → basement/upper floor → street. Drive each distinct
vehicle approach. Inspect actual rendered floor edges, aprons, doors, stair
landings, vegetation and terrain transitions from player height and an overview.
Measure populated travel and interaction separately from screenshots. Retain
failed attempts and provenance with the review packet.

Finite density probes do not prove continuous mesh separation at every LOD or
arbitrary slope. They close the former missing gate; rendered and traversal
evidence is still required. Do not turn a numerical pass into universal world
quality approval, or introduce a ban on intentional player floating builds.

Scoped source/release, catalog and complete-world checks now pass. See the
[final review](CIVIC_FINAL_REVIEW.md) and [retained failures and passing runs](evidence/terrain_building_contract/README.md).
Human design approval and broader world-quality/performance acceptance remain separate.

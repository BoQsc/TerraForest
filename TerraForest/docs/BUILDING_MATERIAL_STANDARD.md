# Building material acceptance contract

2026-10-31. This supplements `WORLD_BUILDING_STANDARD.md` and the terrain/block
contact contract. It responds to the rejected E1 expansion: clean procedural
patterns changed the established atmosphere, and generic UV projection turned
roof courses sideways. A passing build did not establish suitable artwork.

## Authoring and pattern rules

- Match the existing grim, weathered TerraForest art direction: restrained earthy
  colors, readable age and material detail. Clean pastel substitutions require an
  explicit art-direction decision. Use imagegen for new raster building materials
  under the user's present instruction; deterministic code may normalize size,
  generate mipmaps and inspect output, but must not substitute schematic artwork.
- Generate and retain each material separately, with exact prompts, generation
  and edit lineage, hashes, physical repeat dimensions, source inputs and terms.
  Keep rejected trials and approved originals. A prompt's requested pattern is
  not proof that the generated image follows it.
- Verify brick running bond, stone courses, timber grain, slate/clay overlaps and
  standing metal seams. Image +V means down the wall or down the roof. Roof
  courses run across the slope; standing seams run down it. Do not use wall
  brick joints as a roof pattern or introduce mortar between roof tiles.
- E2 repeats once per metre projected onto the building grid. Brick has twelve
  courses/four lengths; limestone four courses/two nominal lengths; timber four
  boards; slate/clay six courses/four widths; zinc two pans. Roof slope stretches
  this projected repeat by its geometric pitch (1.118 at 1:2, 1.414 at 1:1).
  This explicit convention preserves phase across integer cells and chunks.
- Keep albedo opaque, evenly lit and free of perspective, vignettes and strong
  painted lighting. Inspect close and distant repeats; small material crevices
  must not become large baked shadows. Exact seam continuity and conspicuous
  repeated stains need visual review in addition to edge diagnostics.

## Geometry and renderer rules

One cell remains one addressable/destructible native part. Meshes, collision,
picking, rotated previews and terrain-clearance hulls describe the same geometry.
Roof shells and closed ends use structural undersides/ends and a roof finish in the same
shared mesh, without separate per-cell shader instances. Preserve old block words,
crafting/salvage material identities and old archive decoding. Reject unsupported
versions atomically. Never repaint approved saves to present a new candidate.

Joined surfaces must remain valid collision meshes. Native boundary clipping snaps
plane residuals within 10 micrometres to coplanar before splitting; zero-area and
microscopic output slivers are rejected. Test adjoining pieces at chunk boundaries,
not only isolated shape previews. Every candidate mesh is checked before export.

New appearances use a shared lazy eight-layer array, mipmaps and anisotropic
sampling. Include actual memory measurements and a matched 512/1024 comparison
before raising resolution. Normal maps, parallax and displacement are separate
measured proposals. A texture's size or generation method is not a quality claim.

## Required evidence and enforcement

`tools/check_building_standards.py` is mandatory before export. It exercises
source and release native contact/shape/persistence contracts; the expansion test
derives UV gradients from published meshes and checks course/drain direction
through every supported roof mount. `tests/building_materials.gd` checks image
identity/dimensions and emits 3×3 repeats and edge diagnostics for inspection.
The candidate-asset check also verifies all nine joined building meshes and the
actual warehouse roof finish and town-hall coping continuity before export.
These engineering checks cannot approve atmosphere or artistic quality.

For a candidate, inspect matching player-height arrivals, interiors, roof joins,
undersides, near/far views and at least one local damaged/restored assembly in
the populated world. Exercise actual doors/stairs/basements and fresh-process
restoration. Preserve comparable camera, seed, lighting, quality and resolution;
label any difference, including incremental neighbor replacement. No foliage or
terrain defect may be hidden by reframing only one side of the comparison.

Track each rejected/partial result in `issues/building-expansion/`, update
`WORLD_FOUNDATION_STATUS.md`, and identify the precise build/assets being reviewed.
Approval of an implementation direction does not approve revised buildings or
make them generation defaults. A family without demonstrated real-world benefit
stays an optional prototype, or is removed from the proposed promotion.

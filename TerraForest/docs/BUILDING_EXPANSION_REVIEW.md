# Building shapes, display and materials review — 2026-10-30

This is a proposal grounded in the current native implementation and the new
[civic review set](../reviews/civic_buildings/README.md). It does not approve a
house replacement, change saves, or promise an unmeasured performance result.

## What the new buildings expose

The town hall, church, school and warehouse have different silhouettes and useful
interiors with 81–99 m² partial basements. They still share a narrow material
vocabulary. Concrete is visually noisy on civic walls; timber roofing gives all
five buildings a similar color. Tall 45-degree roofs make a broad school wing
hard to join to a two-storey flat-roof wing. Corners and cornices need finer
profiles. Those are higher-value targets than increasing the number of full cubes.

The first render caught a disconnected cross and low annex geometry replacing a
tall shared wall. The authoring fix restores the shared wall after roof placement
and gives the cross a supported base. This is evidence for checking assemblies,
not just whether every individual shape is valid.

## Current constraints

- `shape_catalog.gd` and `native/block_word.hpp` define 18 shapes. Shapes 1–8
  support four yaw orientations; extended shapes use 24 orientations. The extended
  word has five shape-index bits, leaving IDs 19–40 representable without widening
  the word. This is encoding space, not automatic support in every consumer.
- Each authoritative cell still owns one shape and one of four material IDs.
  A pack must not reinterpret existing IDs or stretch a cell over an opening.
  Multi-cell arches, frames, gutters and roof assemblies remain separate parts.
- `block_world.cpp` uses one shared array material, repeatable UVs, mipmaps and
  anisotropic filtering. It loads four equal-sized power-of-two RGB albedo tiles,
  128–2048 px, from the `original` or `terraforest` set. Roughness is currently
  per material family; there are no material normal/roughness texture arrays.
- `block_lod.cpp` and `block_horizon.cpp` already preserve material/UV data in
  their derived representations. Every new part needs the same near/far identity,
  culling, picking, collision, damage, preview and save behavior.
- Another active chat is modifying distant prop coverage. Rebase and inspect that
  work before changing structures rendering. These civic assets do not alter it.

## First expansion pack: architectural joints

| Priority | Part family | Intended benefit | Assembly rule |
| --- | --- | --- | --- |
| 1 | Thin 1:2 roof slope, low/high half-cell phases and their seam pieces | Shallower roofs on wide schools, halls and houses | Two horizontal cells per metre of rise; matching ridge/eave fixtures before adoption |
| 1 | Thin roof hip/valley and end caps | Clean L/T junctions and intersecting roofs | Separate corner, straight and termination cells; no house-sized cap |
| 1 | Coping/cornice straight and outside corner | Finish flat roofs, parapets and civic frontages | Repeating one-cell trims with complete corner joins |
| 2 | Narrow beam, angled brace and post cap | Porches, counters, trusses and exposed supports | Connections remain in the lattice and locally removable |
| 2 | Chamfered edge and three-way corner | Reduce harsh full-cube corners at close range | Matching collision and damage surfaces, not a cosmetic overlay |
| 3 | Thick arch quarter, springer and keystone | Church/municipal openings with more weight | Compose complete openings from several blocks; retain a clear capsule passage |

Prototype the first three families before assigning permanent IDs. Count the
actual unique geometries and reserve the remaining IDs; do not fill all 22 spare
slots with cosmetic variants. A different material is not a new shape.

## Display improvements to try first

1. Add joint fixtures to the review viewer: exterior, underside, oblique grazing
   light, collision wireframe, one-cell removal and a 30–150 m camera sweep.
   Show dimensions and local cell axes in authoring mode only.
2. Group the construction palette by structure/roof/trim/opening, with a searchable
   name, a clear orientation thumbnail and an assembly preview. Bake thumbnails;
   do not generate them during player interaction.
3. Audit UV direction and scale on rotated roof and trim parts. Preserve continuous
   planks/brick courses across a join. The screenshot set shows repetition is
   more visible than a lack of polygon detail on these broad walls.
4. Evaluate a shared normal map and material roughness array behind a reversible
   quality option. Keep silhouettes and collision identical at every setting.
   Avoid shader displacement, per-block materials, transparent trim layers and
   geometry that exists only near the camera.

## General texture pack

Start with eight authored appearances: warm brick, pale plaster, dressed stone,
rough foundation stone, timber boards, dark slate, oxidized sheet metal and
concrete. Use a consistent physical scale, neutral albedo and restrained detail.
Keep original editable generation sources and asset-specific CC0 provenance.
Do not import unknown-license texture collections or infer rights from an image.

The current **two material bits cannot represent eight independently selectable
materials**. A global four-tile replacement would also repaint existing approved
buildings. The preferred next design is a versioned material/style mapping with
legacy IDs preserved, plus native counts/crafting/salvage and archive validation.
Prototype a four-slot alternate review palette first; adopt broader selection
only after its save/migration contract is designed. Normal and roughness maps
are separate from adding new material identities.

Bake mip chains and measure actual GPU texture memory. Compare 512 and 1024 px
at player distance before choosing larger assets. Material variants must share
arrays and shader state; decorative uniqueness should not multiply draw calls.

## Acceptance and updating existing buildings

Run native debug/release validity, all rotations, precise picking, capsule stairs
and doorways, independent removal, archive roundtrip and fresh-process restoration.
Inspect seams, underside, eaves, shadows, silhouettes and damaged assemblies.
Compare the same populated route at 1920×1080, including p95/worst frame, geometry,
draw calls, memory, publication time and near/far transitions. Keep screenshots
outside timed samples. Revert or gate an option if its cost is unjustified.

Create A/B revisions for each existing house. Exact house/revision approval is
required by `WORLD_BUILDING_STANDARD.md` before changing its generation default.
Keep saved cells intact; no automatic repainting, shape-ID reuse or save migration.
The new civic proposals also need individual visual decisions before production
generation. The partial basements then need surveyed lots and excavation in the
native master plan before blocks are published, followed by actual-world routes,
reload and populated performance evidence.

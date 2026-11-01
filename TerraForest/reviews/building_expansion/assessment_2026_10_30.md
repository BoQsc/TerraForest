# Building shapes, display and materials review — 2026-10-30

**2026-10-31 implementation update:** the initial E1 procedural materials were
rejected for their bright, clean appearance. E2 uses eight separate imagegen
materials and corrected roof UV direction. Eighteen new native shapes, versioned
cell appearances and construction display changes are implemented; source/release
checks pass. Matched world verification and final approval remain in progress.
See the [stable issue](../issues/building-expansion/README.md) for current evidence,
rejected trials and remaining work, and the [material contract](BUILDING_MATERIAL_STANDARD.md).
The sections below retain the approved assessment and original implementation
sequence; their descriptions of the 18-shape baseline are historical, not a claim
that the implementation is still missing. E2's palette replaces the earlier
warm/pale suggestion with the user's grim, weathered direction.

The user approved this expansion direction on 2026-10-30, together with the five
exact civic R1 designs. The finished expansion requires its own review and
approval, supported by justified improvements in real-world situations. This
direction does not automatically approve changed house revisions or save migration.

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
- Completed distant-prop work from `19fef843` is merged into this isolated branch.
  Further work continues in the original checkout. The shape-pack proposal does
  not change those render paths.

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
All five civic R1 designs were explicitly approved on 2026-10-30 following their
complete-world review. Their exact geometry is the approved comparison baseline.
Normal-generator integration is a separate implementation step; do not request
the same design approval again. Expansion changes to those designs are new revisions.


## Required real-world review

User condition, 2026-10-30: the expansion must show justified improvements in
real-world situations when it is ready for review and approval. Apply these
requirements to the finished expansion; a component showroom alone is insufficient.

1. State the existing problem and the expected player-visible benefit for every
   addition. Demonstrate shallow-roof proportions and junctions on the school,
   facade/cornice and material readability on the town hall/church, and roof or
   material identity on the warehouse. Include an existing house/POI revision
   when proposing updates to that family. A larger catalog is not itself a benefit.
2. Capture before/after versions in the same populated, playable generated world,
   with matching seed, lot, camera, lighting, weather, resolution and quality.
   Preserve the approved R1 baseline and identify every tested revision/hash.
   Show player-height arrival, interiors, roof underside/joins, overview and
   near/far travel. Label unavoidable differences; do not hide terrain or foliage
   defects by changing the comparison view.
3. Exercise normal construction selection, rotation and placement for the display
   changes, and actual movement through doors, stairs and basement routes.
   Verify terrain contact, locally removed/damaged assemblies, save/reopen and
   LOD transitions. Better appearance must preserve usable, destructible geometry.
4. Measure matching populated routes and interactions: frame p95/worst, CPU/GPU
   cost where available, memory, geometry/draw calls and publication/loading cost.
   Keep screenshot readback outside timing. Use a stable merged build baseline;
   unrelated concurrent changes or workloads must not be attributed to the pack.
   Report regressions and uncertainty and explain why any added cost is justified.
   Keep the current full-world frame-pacing gap visible; do not lower quality to
   manufacture a passing comparison.
5. Present a concise benefit/cost/remaining-defect decision for each addition.
   Revise, remove or keep optional anything whose practical gain is unsupported.
   Submit the finished pack and exact affected building revisions for explicit
   user approval before adopting those changes as defaults. Approval of this
   direction is already recorded and must not be requested again.

## Approved implementation direction

The assessment and direction are approved. New shape IDs, textures and the
versioned material renderer still need implementation and the review above.

| Review decision | Concrete first deliverable | Cost/control | Exit evidence |
| --- | --- | --- | --- |
| Shape pack A | A 4×4-cell shallow-roof joint fixture: low/high slope phases, ridge, eave and valley; a four-cell cornice corner | Reserve IDs only after fixture geometry is settled; native mesh/convex and lattice caches; shared material | All 24 orientations, underside, joined UVs, one-cell damage/removal, floor-to-eave capsule clearance, near/far sweep and save restore |
| Construction display | Searchable family tabs and baked orientation/assembly thumbnails in the existing palette | Event-driven filtering; no preview viewport per tile; retain numeric/native identities | Keyboard/mouse placement, rotate/tilt shortcuts and old prefab selection behave identically |
| Texture study A | Four-slot **review-only** comparison: warm brick, pale plaster, timber, dark slate on the same hall and school | Begin at 512 px; compare 1024 only at player distance; same lighting and camera; no automatic world repaint | Side-by-side wall, roof, grazing light, repeat seams, mip transitions and GPU memory/frame results |
| Material system B | Versioned per-cell appearance identity with eight authored appearances and legacy four-material decoding | Preserve structural/crafting material separately from appearance; atomic snapshot validation; fail closed on unsupported versions | Old saves byte-stable, new saves roundtrip, counts/crafting/salvage correct, bounded batches and shared arrays |
| Existing buildings | One named A/B revision per approved house, then the civic set | New prefabs only until that exact revision is approved; no global texture substitution | Per-building approval plus all applicable roof, passage, support and damaged-assembly views |

Recommended order is the fixture and display work, then the four-slot texture
comparison, followed by the material format and individually reviewed building
updates. A shallow roof improves the school wing's proportions; plaster and stone
separate civic walls from warehouse walls. The warehouse benefits from a metal or
slate appearance without needing another structural shape.

Do not enable parallax/displacement, per-cell lights or transparent trim layers as
part of this pack. Their runtime and visual costs are not needed to solve the
observed joins and repeated surfaces. Normal/roughness arrays are an optional
measured follow-up to the albedo study, with a lower-cost quality setting retaining
the exact same collision and silhouette.

For budgeting only: eight uncompressed RGBA8 1024² layers with a full mip chain
are about 42.7 MiB per array (10.7 MiB at 512²). A second normal array doubles that;
an R8 roughness array adds about 10.7 MiB at 1024². Actual resident format,
compression, uploads and memory must come from the renderer on supported hardware;
these arithmetic estimates are not a measured allocation or performance promise.

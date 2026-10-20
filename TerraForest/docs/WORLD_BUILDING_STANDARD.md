# World-building acceptance standard

Version 1 — 2026-10-18. These are project acceptance rules, not a claim of an
industry certification. They apply to the integrated playable world and generator
recipes, not only to individual assets or isolated fixtures.

## What counts as complete

A successful build, saved-world roundtrip, collision test or 60 FPS screenshot does
not make a location accepted. Record three distinct outcomes:

- Engineering checks passed: generation, persistence, interactions and bounded work.
- World quality rejected or unreviewed: known design defects or missing evidence.
- World quality accepted: every applicable criterion below has direct evidence.

Unknown is not passed. Review images are evidence only after inspection. A passing
walk down the road center does not excuse holes at the side or unusable entrances.
Do not promote a draft as the finished foundation or silently relax a failed rule.

## Terrain fit comes before construction

Survey the full intended occupied footprint before edits. Include roads, entrances,
yards, transitions and the surrounding terrain in final validation; current native
foundation samples alone do not establish all of this coverage.

For ordinary inhabited sites, the initial project defaults are at most **2 m fill**
and **3 m cut** relative to the chosen finished grade. These are deliberately modest
design budgets, not the native edit maximum. A site exceeding them must be moved,
reoriented, reduced or divided into independently graded blocks/lots connected by
designed streets. Do not flatten the entire settlement bounding rectangle merely
because the edit system can support it. Do not enlarge a generator plateau to hide
a poorly fitted plan.

Exceptional quarries, dams, fortifications or retaining structures need an explicit
location design and review; they are not a global exception for ordinary housing.
Review transition slopes from the ground, outside the site and from an overview.
No floating foundation, unintended cliff, hole, unsupported road or raw repeated
capsule-shaped mound is acceptable. Road surfaces and building thresholds must meet
deliberately; slopes/steps/retaining walls must be intentional and traversable.

## Roads form a coherent network

Plan road corridors and grades before buildings. Account for road widths, turning
space, shoulders and elevation at crossings. Different elevations require a proper
connection or physical separation, never overlapping cut/fill stamps. Check on-foot
and vehicle approaches, entrances and departure, not only straight-line travel.
Parked vehicles and props must leave the full access corridor and pedestrian
clearance unobstructed. Validate their transformed collision bounds against planned
roads and paths; avoiding other objects alone is insufficient.
Road material must read as pavement over a supported surface, not a thick asphalt
wall. Footpaths and door approaches must connect to the street.

## Buildings create places worth entering

Each location needs a purpose, readable arrival, recognizable landmarks and useful
interiors. Adjacent repeated modules must vary meaningfully in massing, height,
roofline, frontage or use; tint changes alone do not establish variety. Repetition
can be intentional, but twelve identical office-like towers are not an accepted
default town. Keep shared meshes/materials and batched placement.

Provide working entrances/windows, circulation, stairs and relevant furnishings or
storage. Review a representative route from street to upper floors and back plus
every distinct entrance/stair topology. Basements, chambers and mineshafts belong
to specific POIs and remain rare and intentional; no ambient pipe-cave network as
a substitute for designed underground places.

Repeated floor modules must distinguish ground, intermediate and roof conditions.
An opening needed for stairs from the floor below must not leave exposed terrain
in a ground-floor interior. Verify the ground slab and upper stair clearance
separately. Access checks must start on a connected street and wait for destination
residency before enumerating nearby doors; teleporting beside a door proves only
that entrance, not the connection from the world.

## Landscape, vegetation and water belong together

Keep coherent transitions between settlement, paths, yards and surrounding biome.
Terrain edits must not indiscriminately erase broad vegetation areas. Populate
representative locations with the accepted grass/plant/bush/tree detail rather than
evaluating an empty site and assuming populated performance. Preserve access and
sightlines. Flowers and gatherable wood sources have intentional rarity/distribution.
Use the accepted static volumetric water system; do not reopen flow/spillage work.
Lakes must meet the ground without gaps, sheets or disconnected visual remnants.

## Runtime and persistence remain part of acceptance

Native hot paths; bounded streaming, collision and entity activation; shared/batched
assets; bake/cache static work. Save authoritative changes and verify fresh-process
restoration. Shutdown and offline preparation must report durable save failure even when edits
and addon transfers settled successfully. Every authored path width must survive
the same native persistence validation used by the complete world.
Loading must communicate progress and avoid exposing incomplete local
collision. World generation must produce one coherent playable result, not rely on
separate showcase scenes.

Measure representative populated travel and interaction at **1920×1080, 60 FPS**.
Keep screenshot readback outside timed samples. Report p95, worst frame, loading,
residency and test scope; 60 FPS caps do not prove spare GPU/CPU capacity. Hardware
changes require separate baselines. Long-run/thermal, larger world and multiplayer
readiness require their own evidence and must remain open until demonstrated.

## Check authoring primitives before a complete bake

Before an integrated bake, run short checks against the actual native placement API,
not only recipe counts or diagrams. Cover the occupied footprint, connected paths,
prop support, attachment envelopes and combined block/model publication. A mesh
attachment's collision parts must fit inside its declared placement envelope.

Survey the planned common spaces together with lots and roads before the related
earthworks. Natural-root sampling after grading is not an edited-surface survey.
Put all related ground preparation into the master plan, then publish paving,
buildings and attached models. Do not schedule new terrain cuts through blocks that
have already been placed, or bypass normal protection to make that ordering work.

Use a direct native or targeted saved-world reproduction for a publication failure
before repeating a complete world bake. Retain failed staging evidence and do not
publish those partial worlds as review saves. Native checks do not replace the
subsequent complete-world restore, traversal, interaction and image review.

## Required review evidence and current disposition

For each generator recipe/location, retain the seed/version, pre-edit survey and
grade, edit footprint, road layout, building archetypes, ground-level and overview
images, traversal result, save/reload result and scoped performance measurements.
At least one reviewer must inspect the images. Human review remains necessary for
the overall player experience; automation must not replace it with a numeric score.

The seed-42 northern district is **rejected for world quality**. Its recorded survey
spans 51.252861–63.855671 m and its selected grade is 58 m: maximum fill 6.747139 m,
maximum cut 5.855671 m. It also repeats one building archetype twelve times and has
unfinished landscape integration. Passing road/tower walks and save tests do not
override this disposition. Source: `evidence/settlement_road_embankments/create.log`
and `north.png`.

The next correction is a terrain-fitting block/lot layout with road grades planned
first, followed by meaningful building variants and landscape transitions. Do not
continue adding detail onto the rejected single-pad layout as though it were final.

`world_building_quality.gd` provides only the automated pre-edit earthworks check.
Preparation reports preserve that result and explicitly leave the remaining review
categories pending. Development saves can still be generated for inspection; this
is not a release/promotion gate and must not be described as full enforcement yet.

## Application to the first replacement layout

The new `northern_lots.gd` production recipe removes the single pad and checks
independent lot grades. Evidence: `evidence/northern_fitted_lots/`. Its earthworks
checks pass, but the inspected replacement is still rejected for overall design:
repeated facade family, missing trees/public-space landscape, exposed end cut and
raw road ends. These are required follow-up work, not optional polish. Passing
lot checks must not promote this recipe to accepted world quality.


## Vegetation continuity and shading

Review vegetation during travel and in open daylight, as well as the shaded
showcase. Ground detail must fade in on publication and across its distance band;
whole owner cells must not appear/disappear visibly at streaming boundaries.
Check native resident-page admission: a generated plant count is not proof that
those plants are actually rendered. Record deferred pages and upload/resident byte
budgets alongside images. Preload detail outside the visible band and retain it
until owner retirement to avoid repeated boundary regeneration.

Keep grass, understory, bushes and rare accents in ordinary world areas. Authored
showcase patches alone do not establish biome coverage. Preserve gathered IDs and
authored placements when changing presentation. Compare shadow options in the same
populated view; root ambient shading is not a cast shadow. Do not enable blanket
blade shadows or replace accepted models without evidence that the gain merits
the runtime cost. A short rendering check does not establish thermal headroom.

2026-10-19 density direction (supersedes the 2026-10-18 density requirement):
The user chose to retain current sparse production cover and improve its spatial
placement. Use deterministic irregular groups and openings at the existing candidate
budget. Preserve small stones, harvest identities, authored objects, LOD continuity
and near shadows. Do not increase density back to the old showcase reference without
new user direction. Sparse cover is intentional; missing resident owner patches,
popping and visibly absent middle-distance representation remain defects. Zoom must
extend useful detail with bounded loading and fading. Ground/elevated/travel views
and sustained performance still require evidence.

Near-player vegetation requires resolved cast shadows, not merely an enabled
shadow flag or root darkening. Inspect contact, silhouette, movement stability and
cascade transitions in daylight. Distant approximations must not replace near
cast shadows. The current correction reserves the first directional cascade for
roughly 9 m, uses blended splits and a 4096 atlas; runtime and atlas-memory costs
are explicit. Moving-view and broader terrain-acne review remain required.

2026-10-20 correction: earlier independent-lot checks measured generator-flattened
ground, not raw terrain. They do not establish earthworks acceptance. See the raw
terrain audit and native terrain-lot evidence in WORLD_FOUNDATION_STATUS.md.

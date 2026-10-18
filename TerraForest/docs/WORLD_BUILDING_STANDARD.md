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
restoration. Loading must communicate progress and avoid exposing incomplete local
collision. World generation must produce one coherent playable result, not rely on
separate showcase scenes.

Measure representative populated travel and interaction at **1920×1080, 60 FPS**.
Keep screenshot readback outside timed samples. Report p95, worst frame, loading,
residency and test scope; 60 FPS caps do not prove spare GPU/CPU capacity. Hardware
changes require separate baselines. Long-run/thermal, larger world and multiplayer
readiness require their own evidence and must remain open until demonstrated.

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

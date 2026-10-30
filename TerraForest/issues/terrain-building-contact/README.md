# Terrain crossing building surfaces

- Status: Shared correction and enforcement implemented; scoped native checks pass.
- Updated: 2026-10-30. Core commit `86fd2511`; final integration and footprint guard `79d38271`.
- User review: Pending. This is not universal terrain or world-quality acceptance.
- Symptom: Soil appears through building floors, narrow stairs or loading aprons
  even though the old foundation/support checks passed.

## Cause and correction

The old checks proved support below cells and air above rooms, leaving exposed
surfaces untested. Sloping approach ends could continue their grade beneath level
aprons; material ordering could also refill excavation. Narrow subtractive masks
clipped air density to their side edges, raising the interpolated zero surface.
A separate regression found that an attachment envelope could hide an elevated
block footprint.

The mandatory [terrain/building contract](../../docs/TERRAIN_BUILDING_CONTRACT.md)
centralizes soil height, surveys, level approach ends, ordered excavation and
native shape-derived subtractive clearance. Actual native block footprints must
reach the foundation band. Before publication, the same production validator
checks support, room air and density below exposed tops, including paving. Export
requires source and isolated release checks plus the current building catalog.
Player block placement remains free; opening a save never regrades it.

## Images

[Current and historical civic images](../civic-buildings/README.md) retain the
warehouse apron and trader approach before correction alongside final full-world
views. These are distinct review builds; the images are not pixel-aligned A/B
performance evidence. Captions, source runs and hashes are recorded there.

## Verification

[Retained engineering evidence](../../docs/evidence/terrain_building_contract/README.md)
includes rejected quarter-metre offsets, the narrow-mask reproduction, 30 native
contract checks in debug and release, and 64 catalog checks covering 46 buildings
and six sidewalk sets across seeds 1703 and 42. Existing approved large-house
geometry passes 56 checks. Full-world approval evidence is linked from the
[civic final review](../../docs/CIVIC_FINAL_REVIEW.md).

## Reproduce / future enforcement

From TerraForest: `python tools/check_building_standards.py --godot <engine>`.
Normal `tools/export_pack.py` runs this gate automatically. Generate a new civic
review world with `python tools/review_civic_world.py --create`; do not overwrite
an existing player save. A failed, stale, missing, oversized or timed-out scan
must refuse publication and report its coordinate.

Finite probes cannot prove every slope or LOD continuously. Reopen this same
issue for any recurrence, retaining the seed, exact prefab revision, coordinate,
view, native build hashes and a small failing density/shape fixture. Require that
fixture in the shared gate and a rendered/traversal rerun before claiming closure.
User visual acceptance and general frame pacing remain separate review items.

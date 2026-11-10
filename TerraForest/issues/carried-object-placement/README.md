# Carried objects and shoreline placement

- Status: Improved-partial; object placement package verified and installed.
- Updated: 2026-11-10. User visual review remains open.
- Request: shoreline barrel placement, actual object previews, occupied building
  cells, optional free placement and furniture in Dev Bag.

## Cause and implementation

Barrels had an independent single-ray normal cutoff of 0.8 and an overlap box
at the unadjusted hit point. This rejected otherwise supportable slopes. The
carried-object adapter now uses the existing native nine-sample footprint support
fit, then rechecks final collision readiness and obstruction clearance. Existing
support gap/offset rules, reach, player protection, model capacities and the
256-barrel limit remain. It does not make every shoreline position valid.

Default placement snaps X/Z to the building grid. H switches grid/free placement;
R rotates by 90 degrees; right mouse places. A tinted actual model and bounded
64-slot wire-cell preview show the full occupied footprint, including height.
Updates run at 20 Hz; mesh/shape/query resources are reused. G remains item drop.

Seven carried items expose existing table, chair, shelf, chest, ladder, fence and
window assets. Dev Bag has an Objects & furniture filter and shared search/icon
support. Existing native model owners, inventory transactions and save sections
remain authoritative. No new assets or per-object ticking scripts were added.

## Verification and evidence

- `reports/checks/20261110T153755965833Z`: actual read-only default world;
  40-degree support fixture, grid/free positions, real barrel preview, payment,
  rejected repeat, seven Dev Bag entries, source save unchanged.
- `20261110T154308887710Z`: catalog, inventory snapshot compatibility, footprint,
  native paid placement and unpaid rejection pass.
- `20261110T154325466793Z`: universal item drop/recollection/save checks pass.
- `20261110T154341282197Z`: 86 physical-drop checks pass.
- `20261110T154359480186Z`: 12 model-inventory checks pass.
- `20261110T154515460152Z`: G-input fixture still fails the same two real-input
  assertions already reproduced on the unchanged installed baseline during the
  pistol trial. Not counted as a passing gate.

All paths above are under `reports/checks/`. Tests reuse the existing world
read-only; no new saved world or checkout was created. Final fitted-obstruction
checks and rendered preview review are recorded below.

## Related shoreline reports / remaining

Water has volumetric storage, but automatic redistribution is disabled in the
installed build. The shared committed-edit wake now covers mining and explosions
in the opt-in prototype. Shallow mesh coverage and timing still block enabling it;
see [water qualification](../explosive-combat/distance-water-2026-11-10.md).

The reported distant tree loss is not reproduced yet. The full actual-barrel
audit `20261110T154430357586Z` covers 8,742 resident tree identities: one tree
rooted in the crater was destroyed; no distant saved or rendered identities
disappeared. Earlier terrain-only audit `20261110T154104092061Z` agrees. An
earlier concurrent fixture load failed; its report remains retained. This does
not establish correctness for every shoreline, chain, streamed owner or camera.
Retain the player's reported symptom; capture exact affected IDs/positions in
that world before changing damage or vegetation radius.

Return gates: user natural-shoreline playtest and visual review, then the water qualification
and specific tree-loss reproduction. Foreground FPS comparisons remain deferred.
No 60 FPS or next-tick explosion completion is claimed.

## Rendered preview review

![Barrel grid preview](../../reports/checks/20261110T154648732447Z_objects/barrel_grid.png)

Barrel model and occupied cells on a temporary white 40-degree support plane in
the existing read-only default world. Engineering fixture, not shoreline visual
acceptance; HUD selection was forced by the driver and is not representative.

![Chair free-placement preview](../../reports/checks/20261110T154648732447Z_objects/chair_free.png)

Chair model and occupied cells in free mode. Same fixture and camera session,
with a placed barrel nearby. Images reviewed for preview correspondence only.
Provenance/hashes: `images/manifest.json`. The final obstruction test passes in
`reports/checks/20261110T154846513894Z`: other solids still reject fitted placement.

## Packaged installation

`reports/checks/20261110T154953228782Z_objects_package` passes carried-object,
universal-drop and actual-world placement checks against installed native DLLs.
The PCK was installed; every native DLL hash stayed unchanged. The predecessor
was compressed and reconstructed/hash-verified before replacement. Staging was
removed; no saved world was created. Installed PCK SHA-256:
`abfdf4c9e77b50d303fdea3613f045827e16237d0117a31959cd10ab0c978258`. Rollback evidence: `previous_package.archive.json`.

The installed executable also passes headless startup smoke (`executable/run.json`).
This is not a foreground performance or natural-shoreline visual qualification.

# Durable edited ocean storage — implementation contract

Status: required, not complete. Native edited-coast scaling currently fails.
Native transfers, immutable storage, bounded I/O, checkpoint-backed gameplay
save/load, cloning and failure guards are implemented and tested. Selective
metadata queries are available, but gameplay still eagerly restores all edits.
Live eviction, deferred runtime ownership and retention/GC are not enabled.
See WORLD_FOUNDATION_STATUS.md for scoped evidence and remaining integration.
Evidence: `evidence/ocean_edited_scaling/result.json` and corresponding test.

The existing NativeBlockRegionStore/NativeRegionWorldArchive establish a local
pattern for checksummed immutable region blobs, checkpoint membership and worker
reads. Their packets and catalogs are block/model-specific; water must not be
encoded as fake blocks or published independently of its compound world save.

## Required ownership and transaction rules

- Keep one authoritative water store. Resident regions are a working set; an
  immutable region catalog retains unloaded edits. A fully removed ocean region
  must retain an explicit empty override so procedural sea cannot regenerate it.
- Preserve exact quantities, vacancies and ocean ownership. Derived density/contact
  caches can be regenerated against the matching terrain and structure revision.
  Old v1–v10 water snapshots must remain readable and migrate without changing water.
- Eviction must wait for successful durable region publication and verified identity.
  Failed or cancelled writes retain the dirty resident region. Do not silently
  discard edits on capacity pressure or raise the region limit.
- Save canonical terrain, structures, inventory and the water checkpoint together.
  Keep prior checkpoint blobs alive until canonical/backup references retire. An
  unsaved runtime eviction must not change what an older world save restores.
- Stream bounded native read/write jobs. Publish only matching world epoch, region
  generation and terrain/structure revision. Stale returns must not replace a newer
  edit. Account pending transfers, resident, cache and snapshot memory separately.
- Neighbor halos must be needed only for nearby reconstruction, not pinned forever
  by a distant edit. Resident retirement must remove stale picking and render data.
- Far ocean presentation must preserve visible modifications. Never replace an
  unloaded edited coast with an unmodified plane that fills holes visually.
- Map surveys must include unloaded edits with checkpoint-consistent data. Bucket,
  terrain and building operations must load required authoritative records before
  accepting an edit; unavailable data is not empty data.

## Acceptance before calling this complete

1. The edited-coast scaling probe passes without increasing the resident budget,
   and direct native tests verify quantities/empty overrides across unload/reload.
2. Actual-world scoop/pour, terrain and building replacements survive travel away,
   fresh-process save/reopen and return, with matching local surfaces and inventory.
3. Injected storage failure, stale worker completion and interrupted save retain
   the prior valid checkpoint and do not lose or duplicate water.
4. Map and far/near visuals retain edits; inspect coast and underwater transitions.
5. Run short 1080p/cap60 travel measurements with pending/resident/cache byte counts,
   frame percentiles and loading latency. Long-run thermal acceptance remains
   separately required; neither this policy probe nor a screenshot proves it.

This contract records the dependency rather than deferring it indefinitely. It is
not authorization to introduce flowing water or change fixed-unit bucket behavior.

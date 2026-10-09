# Model checkpoints in compound world saves

The existing `NativeRegionWorldArchive` now publishes registered static-model
collections to asset-specific region catalogs when saving the compound world.
No separate per-asset worker is spawned: these synchronous operations run on
the archive's existing save owner. The standard region-backed main world uses
this adapter, so subsequent saves use model checkpoints automatically.

For `world.trw`, model catalogs live under `world.trw.models/<asset SHA-256>/`.
Block regions remain in `world.trw.regions/`. The world root and its backup must
travel with both sidecar directories. The asset name is bound in each catalog
and in the checksummed TFMK reference stored inside the structures reference
bundle. Existing resident/inline-model save formats remain readable. Older
builds lacking TFMK support cannot read new reference-based model saves.

## Publication and recovery

1. Validate the incoming complete or partial structure/model captures and both existing
   roots before retiring unreferenced checkpoints.
2. Publish each model snapshot and pin its exact catalog; pin the block catalog.
3. Encode the compound root using the block checkpoint and asset-bound model
   references, then atomically publish that root through `NativeWorldArchive`.
4. Retain all checkpoints named by the actual current and backup roots. Retire
   other pins only after validating both roots. Inspect at most 32 garbage blob
   entries per open catalog after successful publication.

If root replacement fails after catalog updates, previous current/backup roots
retain their pinned versions. A retry retires safe orphan pins before creating
new ones. Cleanup failure after successful root publication does not turn a
successful save into a reported failure. Unopened orphan asset directories are
not automatically removed. The root lease and each store's lease prevent a
second writer; this is a serialized save protocol, not multiplayer authority.

On load, the adapter resolves model references and reconstructs full model
snapshots before returning the normal scene-compatible structure envelope.
Missing/corrupt catalogs or unresolved checkpoints reject restoration. An
existing reference cannot cause an absent model directory to be recreated as an
empty world on save. This stage still loads all authored model transforms;
metadata-first block loading does not imply metadata-first model loading.
The structures scene also captures partial model collections using a checksummed
TFMP storage envelope: resident records plus sorted unavailable region keys and
their exact digests. Publication preserves those regions from the active model
catalog while committing resident edits and demolition. Uncommitted or stale
unavailable references fail the save; this envelope does not carry an older
model checkpoint fallback. The archive resolves partial captures to normal
model checkpoint references on disk. Direct scene restoration rejects unresolved
partial model envelopes before mutating any scene state.

Automatic model admission/eviction, metadata bootstrap and distant proxies
remain unfinished. Partial publication still reads unavailable records to validate
collection-wide ID uniqueness on the save worker.

## Verification

`tests/region_world_archive.gd` now includes compound model publication,
reference type separation, 20 successive model versions with exact backups,
checkpoint retention, failed root replacement, retry, demolition, disk reopen
and missing-sidecar rejection/recovery. `tests/structure_persistence.gd
--region-storage` exercises the actual terrain/water/structures coordinator and
passes 76 checks, including model state restoration and invalid-load protection.
Evidence is retained in `docs/evidence/model_world_archive`.

The partial model extension passes 82 archive checks in debug and isolated
release, including actual scene capture, demolition with an unloaded region,
exact backup/reopen and invalid-envelope rejection. The integrated release
coordinator still passes 76 checks. Evidence: `docs/evidence/model_partial_world`.

Tests use isolated fixtures, not the user's world. They are short headless
correctness checks, not sustained FPS, disk-latency, power-loss-at-every-write
or memory qualification. Capturing and reconstructing full model snapshots is
still proportional to authored data. The change establishes correct compound
checkpoint ownership; it does not by itself lower runtime resident memory.

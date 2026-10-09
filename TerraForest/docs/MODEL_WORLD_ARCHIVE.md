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
4. Retain checkpoints named by current/backup roots, outstanding reads and
   explicit read leases. Retire other pins only after validating both roots. Inspect at most 32 garbage blob
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

## Background region reads

`request_model_region_read(asset, region, expected_digest, checkpoint, epoch)`
uses the archive's existing persistent region reader and leased catalogs.
Registered assets only are accepted. The worker lazily opens existing model
catalogs without creating missing sidecars; request/poll calls never perform disk
I/O. Reads require the exact digest from the active or explicitly pinned catalog.
Checkpoint-bearing requests now retain existing pins until their results are
polled. Explicit leases extend protection across scene/paging work; request
admission returns backpressure while cleanup selects removable pins. Already
retired versions still fail rather than substituting newer data. See
[checkpoint retention and lease handover](REGION_CHECKPOINT_RETENTION.md).

Blocks and models share FIFO submission, unique tickets and total request/byte
limits. `poll_model_region_reads` returns only model completions (with asset,
region, epoch and exact request digests); `poll_region_reads` remains block-only.
Both channels must be consumed. Reservations include active and unread completed
work: 2,097,248 bytes per block request and 5,600,328 per model request. A service
configured below the model reservation rejects model requests. Limits exclude
parser scratch, catalogs, containers and caller-owned results. There is no I/O
preemption or priority scheduling; these limits do not guarantee latency.

The lifecycle owner starts/stops this shared service once. Release drains and
joins it before closing any catalogs, and unread results prevent reacquisition.
The existing block pager still owns the service in the main scene; a future
combined paging coordinator must own lifecycle and poll both result channels.
This API does not yet enable automatic model eviction or metadata-first loading.

`request_model_metadata(asset, checkpoint, epoch)` now builds/loads the cached
checkpoint manifest on the same worker. Its completion has `operation="metadata"`
and can initialize a native collection without full transform reconstruction.
See [model metadata](MODEL_METADATA.md) for cache, bounds and validation details.
The main-world decoder has not switched to this bootstrap path yet.

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

The shared reader fixture passes 68 checks in debug and release, including 64
mixed reads during 16 compound saves, asset isolation, retained-version fallback,
stale restoration rejection, shared backpressure, missing/corrupt blobs and
shutdown/reopen. The release block pager passes its existing 29 checks. Evidence:
`docs/evidence/model_archive_reads`.

Tests use isolated fixtures, not the user's world. They are short headless
correctness checks, not sustained FPS, disk-latency, power-loss-at-every-write
or memory qualification. Capturing and reconstructing full model snapshots is
still proportional to authored data. The change establishes correct compound
checkpoint ownership; it does not by itself lower runtime resident memory.

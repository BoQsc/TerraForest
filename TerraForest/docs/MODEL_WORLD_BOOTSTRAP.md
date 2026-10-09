# Model metadata in world startup

The native world archive can now decode model checkpoint references into TFMD
metadata instead of reconstructing every placement transform. The existing scene
persistence coordinator can install that metadata and capture a valid partial
save afterward. This path is opt-in, not the current default game startup mode.

## Activation and representation

`NativeRegionWorldArchive.configure(raw_archive, structures_codec, true, true)`
enables block and model metadata startup. The equivalent persistence-glue option
is `enable_region_structures(true, true)` before attachment. The existing two/three
argument archive calls and zero/one argument persistence calls retain their
previous behavior. Model metadata startup requires block metadata startup.

The new TFSU v1 **in-memory startup envelope** uses the existing checkpoint-based
block residency payload plus validated TFMD model manifests. It is distinct from
resident TFSB and partial-save TFSP/TFSQ envelopes. `encode_bootstrap`,
`decode_bootstrap` and `validate_bootstrap` handle it. Only an opted-in archive's
component-load validator accepts it. Ordinary resident/save validators reject it,
and archive publication rejects it before changing a store or the canonical root.
Published world files retain their existing checkpoint-root format.

Legacy resident worlds and checkpoint roots containing inline model snapshots
remain readable: they use the existing resident-model path. A later ordinary save
can publish model checkpoints. Older roots may omit newly registered assets;
those collections restore empty instead of retaining unrelated previous objects.

Model metadata includes stable IDs, region checksums and conservative prototype
bounds. It does not include all placement transforms. The first uncached decode
validates source regions individually and persists derived manifests. Cached
loads reuse those manifests without reading the model region payloads. Decode
returns diagnostic `model_bootstrap` fields: asset count, metadata bytes, cache
hits and region packets read. Checksums and schema validation still run.

## Scene transaction and selective loading

`NativeStructuresSnapshot.restore_bootstrap(bytes, blocks, collections)` validates
the complete envelope, collection identities, active-transfer/scheduler guards and
prototype-dependent bounds before replacing blocks or any model collection. It
prepares every model residency map, installs the maps with change signals blocked,
then publishes changes. Observers see the complete new scene state. Recursive
bootstrap is rejected, and weak node identities are resolved for notifications.
Existing signal-blocking states are preserved. This is a scene-owner startup/world
replacement operation; its parsing, ID allocation and resource cleanup are not
frame-budgeted runtime work.

`structures_world.gd` retains block/model checkpoint identities, invalidates old
snapshot caches, and delegates the transaction to native code. It restores its
previous bookkeeping if validation fails. Runtime storage and validation remain
C++; the added GDScript is persistence glue. A live registered model scheduler
blocks replacement; stop/drain and unregister it before replacing the world.

After startup the owner must start/borrow the archive read service, register the
collections and checkpoint identities with `NativeModelTransferScheduler`, then
request needed regions. Retain every required checkpoint before subsequent saves
can rotate its root references. Unavailable model regions remain unavailable for
collision/interaction until successfully admitted. The integration test requests
one region while the other regions remain unloaded.

`capture_storage_snapshot()` produces the existing partial-save representation;
it never republishes TFSU. The test covers metadata-only and mixed-residency saves,
reload, and reopening through the default loader that reconstructs full models.
Historical-checkpoint handover after edits/saves remains coordinator work; enabling
metadata startup alone does not supply automatic focus selection or all lifetime
management. Keep the default game path unchanged until those are connected.

## Evidence and limitations

[Raw reports and binary hashes](evidence/model_world_bootstrap/): debug and release
each pass 25 targeted checks. The 12,000-placement fixture has a 672,268-byte full
structure bundle and a 97,428-byte startup bundle. Both model collections start
with zero resident transforms. Cold decode reads 12 region packets; the next
cached decode reports two metadata cache hits and zero region packets read.
Selective scheduler admission restores one exact 1,000-placement packet and
leaves 11,000 placements unloaded.

Tests also cover corrupt bytes, wrong-asset metadata, a failing second prototype
without partial scene replacement, observers/reentrancy, absent newly registered
assets, active scheduler rejection, legacy roots and partial-save compatibility.
Existing release regressions pass 82 compound archive checks, 27 model metadata
checks and 42 shared scheduler checks.

Payload size is not process RSS. Metadata installation still allocates ID/index
containers and performs work proportional to metadata size. This fixture does not
measure load latency, rendered frame time, GPU usage, power or thermal stability.
The earlier dense-transfer timing and arrival-latency gates remain unresolved.
Automatic focus-driven game paging is not yet enabled. The implementation remains
project-owned 0BSD and uses the existing Zig/prebuilt Godot C++ toolchain.

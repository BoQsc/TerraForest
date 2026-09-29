# Loading checkpoint availability without loading cell chunks

`NativeBlockWorld.initialize_region_index(keys, checksums)` establishes the saved
region availability map in an empty block world. It accepts sorted packed xyz
triples and corresponding concatenated 32-byte region packet digests. The method
is a scene-owner operation; it performs no disk access and allocates no cell chunks.

The index is bounded to 65,536 regions. Noncanonical ordering, duplicate/out-of-range
keys, mismatched checksum lengths and capacity overflow reject the entire index.
Existing authored chunks or an existing unavailable-region map prevent initialization;
the call cannot implicitly replace live state. Empty input is a successful no-op.
Nonempty initialization clears editor history and emits one change signal so
save caches and exclusion consumers observe the availability change.

Every indexed region starts unavailable. The existing readiness, editing, prefab,
exclusion and save guards apply: missing regions block walking readiness, cannot
be edited as air, reserve vegetation space and prevent incomplete whole-world
snapshots. Regions absent from the index remain known empty. The index is trusted
checkpoint metadata, not an authentication mechanism: raw checksum bytes alone
do not prove that a matching file exists.

Read one packet with `read_checkpoint_region`, then call the existing
`restore_region(packet, PackedByteArray())`. The saved digest must match before
cells become resident; a wrong-version packet leaves the region unavailable.
Each successful restore removes that unavailable entry. Whole-world capture only
becomes available after every indexed region is restored, and resident admission
still enforces the 2,048-chunk capacity.

`NativeBlockRegionStore.checkpoint_regions(id)` now returns `checksums` alongside
`keys` and `generation`. Both arrays follow identical sorted order. Its queued
equivalent reserves the maximum xyz-plus-digest output and input identity:
2,883,616 bytes. A queue configured with only 2 MiB therefore rejects this request;
use a sufficient budget, such as 4 MiB. Ordinary active-catalog key listings are
unchanged. Index/container/allocator overhead remains outside payload accounting.

This API prepares a fresh world for selective admission; it does not yet select
regions by camera/player position or permit partial-world saving. The main world
continues to use full-resident restoration until a residency manager and save
representation can preserve unloaded regions together with live edits.

The dedicated test covers a real checkpoint manifest and individual reads,
wrong-version rejection, editing/readiness/exclusion/save guards, malformed input,
the full metadata capacity, and background result reservations. Maximum-index
testing is a structural capacity check, not a measured memory or startup-latency
guarantee. Retained checksum payload at maximum capacity is 2 MiB, plus map and
per-array allocation overhead.

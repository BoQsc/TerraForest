# Native building region paging

The persistent main world now opens building availability metadata and uses
`NativeBlockPager` to bring nearby authored cells into memory. Travel can retire
distant committed cells while retaining their exact archive versions. Terrain,
static-model records and vegetation retain their existing residency systems.

## Ownership and bounds

The structures addon owns the pager on the scene thread. Its archive owns one
persistent C++ disk reader. The scene step never waits for disk I/O. Shutdown
joins and drains the reader before releasing the archive lease.

Default loading distance is 384 cells; normal eviction starts beyond 512 cells.
The scene step probes at most 128 region coordinates, submits at most two reads,
keeps at most four reads outstanding, polls one completion, and performs at most
one cell-region admission or eviction. Requests reserve 64 chunks each against
a soft limit of 1,536 resident chunks. The existing hard block-world limit is
2,048 chunks. Each read reserves 2 MiB plus 96 bytes through the archive queue.
These limits do not include all process, physics, rendering or allocator memory.

When the soft budget is full, a nearer missing region can displace a farther
committed region outside the protected radius. Stable-focus tests cover a
192-chunk fixture with a 128-chunk limit and reject repeated residency thrashing.
The queue has separate bounded retry and provenance maps. Selection, admission,
history protection and eviction run in C++; GDScript only connects lifecycle,
focus, save callbacks and UI.

## Data safety

Eviction requires the current region packet's exact digest to match a committed
version, and no undo or redo record may refer to that region. Uncommitted edits
and history-pinned cells remain resident. Unrelated history survives paging.
Consequently the soft limit can stall further loading rather than discard edits.
External authoring can exceed that soft limit up to the existing hard limit.

A publication notice becomes visible only after the compound world root is
successfully replaced. Failed publication never makes candidate versions safe
to evict. After metadata restore, admitted packets establish provenance until a
new successful save supplies the current index. Whole-world replacement changes
the storage epoch; old read completions are discarded before scene admission.

The main world uses storage snapshots, preserving unloaded region references
and checkpoint identity. Legacy complete snapshots remain unavailable while
regions are unloaded. Keep the world root, backup and `.regions` directory
together when copying a saved world. See [archive reads](ARCHIVE_REGION_READS.md)
and [metadata loading](METADATA_WORLD_LOADING.md) for their formats and contracts.

## Validation and remaining work

`tests/block_pager.gd` covers exact positive and negative region admission,
committed eviction, unsaved/undo/redo retention, failed-root publication, later
successful publication, stale epochs, dense budget pressure and reader shutdown.
Debug and isolated release runs each passed 29 checks.

`tests/block_pager_world.gd` exercises the real persistent terrain scene with two
separated textured cottages: travel, edits, partial saves, hot reload, shutdown
and a new scene instance. Its graphical path requires 1920×1080 fullscreen and
waits for a visible cottage mesh. `tests/structure_world.gd` covers the broader
building, model, vegetation and player integration. Retained results belong in
`evidence/native_region_paging`; package verification repeats the native pager
and persistent-world test from a clean extraction.

The retained graphical runs passed 21 persistent-paging checks and 167 broader
building checks. Across 417 sampled scene steps during the two-cottage waits,
pager time was 0.006 ms median, 0.018 ms p95 and 0.195 ms maximum. These samples
exclude disk-worker time, are not full-frame timing, and do not cover every
frame or every later scene operation. Both graphical runs used Godot 4.7.2,
Vulkan Forward+, GTX 1060 Max-Q, 1920×1080 fullscreen at full rendering scale.

Count bounds are not elapsed-time guarantees. Region capture, validation,
history lookup and scene notifications can still cause a long scene step. The
two-cottage fixture is functional evidence, not a city, high-speed travel or
multi-hour endurance benchmark. Authored static-model region storage, building
LOD, sustained memory/latency measurements and vehicle readiness remain open.
The project as a whole is not yet game-ready.

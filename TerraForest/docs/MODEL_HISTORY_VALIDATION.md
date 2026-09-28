# Native static-model history

`NativeStaticHistory` supplies bounded local editor undo/redo across registered
model collections. It records insertions, removals and transform updates as
120-byte deltas on the pinned Windows x86-64 build. History is ephemeral; it is
not another world snapshot, save journal or multiplayer authority layer.

The main model editor now routes placement/removal through this native journal.
Ctrl+Z undoes; Ctrl+Y and Ctrl+Shift+Z redo. Block mode retains its independent
block journal. Interactive model move/scale handles and unified cross-addon
history remain unfinished, although native transform update/replay is tested.

The debug and release GDExtensions were compiled with Zig 0.16.0 against the
pinned prebuilt godot-cpp 4.7 SDK, commit d7b6162249ed52796a8301d216c24ee71d68c2bf.
No godot-cpp source was rebuilt. Validation uses Godot 4.7.2 Steam on Windows.

## Native checks

Both debug and isolated release runs of `tests/static_placements.gd` passed all
170 checks. Coverage includes the earlier placement, spatial rendering, compound
collision, snapshot and vegetation-exclusion behavior, plus:

- Chronological edits across multiple asset collections; exact full undo/redo
  snapshots; restoration of stable IDs above 32-bit range.
- Signed-group moves, same-group incremental GPU-slot updates, native transform
  update replay, collision release/recreation and restored exclusion bounds.
- Player protection for both undoing deletion and redoing insertion; transformed
  collections and traversable compound openings; blocked commands remain retryable.
- Shared byte/step caps, eviction of oldest commands, no-op and rejected edits,
  new redo branches, undersized budgets and invalid configuration.
- Invalidation after external edits, mesh replacement, bulk replacement,
  identical snapshot restore and destruction of registered nodes.
- Committed history visible to signal listeners, rejection of reentrant journal
  commands, callback mutations and callbacks destroying another collection.
  Asset replacement invalidates history before exclusion notifications.

In the existing 100,000-placement API fixture, one model update retained exactly
one 120-byte record and updated one GPU slot with zero additional batch uploads.
Undo and redo restored its exact transform. This demonstrates incremental work
and bounded retained records; it is not a frame-rate or city-rendering benchmark.
Record-byte accounting excludes deque allocator overhead, which remains bounded
by the independent 1,024-step hard cap and 256-collection registry cap.

Commands are scene-thread authoring operations. External edits conservatively
clear the whole registered timeline, even if they affect an unrelated model.
Collection-frame changes do not invalidate local transform records; replay uses
the current frame and current proxy geometry for player protection.

## Main-world verification

`tests/structure_world.gd --gpu` passed 98 checks at 1920×1080 fullscreen and full
render scale on the GTX 1060 Max-Q. Real input events exercised model placement,
removal, Ctrl+Z, Ctrl+Y and Ctrl+Shift+Z. Undo restored exact IDs/transforms and
nearby collision. Player-overlapping restoration was rejected and successfully
retried after moving clear. The complete redo chain reproduced the original
authored snapshot. Compound world restoration cleared model and block history.
The existing cottage/tower, block collision, forest exclusion and building
streaming checks also passed. This short integration run does not establish
multi-hour endurance or dense-city performance.

The model-tool screenshot was inspected: history counts and shortcut hints fit
the panel without clipping. Evidence, logs and exact native build hashes are
retained in `evidence/model_history/`. Structures, terrain, water and vegetation
also passed isolated-addon startup, and the resource-boundary audit passed.

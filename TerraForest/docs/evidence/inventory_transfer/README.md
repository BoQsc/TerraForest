# Native cross-inventory transfer — 2026-10-11

`NativePlayerInventory.transfer_to(destination, slot, count, source_revision,
destination_revision)` transfers the requested quantity to available destination
stacks. It fills existing matching stacks before empty slots, using the
destination's catalog and stack limits. Source and destination may have different
stack limits. Self-transfers are rejected; use the existing `transfer` for local
slot movement.

Both revisions must match. Failure preserves both inventories and their revisions.
Success returns `item`, `count`, the new source `revision` and
`destination_revision`. Mutation is main-thread only; no callbacks or signals run
between commits. Callers should notify observers and mark the world dirty only
after success. This is not a thread-safe or network-authorized API.

## Verification

- Debug: 29 checks pass, with commands, source identity and DLL hashes in `debug/`.
- Release: 29 checks pass in a clean temporary project using the release DLL.
- Existing player-inventory regression passes in `inventory_regression/`.
- Includes stale/replayed requests, partial capacity, full destination, unknown
  items, invalid slot/count, null/self destination, different stack limits,
  successful transfers in both directions, binary restoration and 1,000 complete
  deposit/withdraw cycles with exact conservation and revision counts.

This checks a bounded transaction primitive, not a storage interface, paired world
save, concurrent multiplayer, scalability benchmark or sustained performance.
It does not change the inventory save format or add per-item scene objects.

## Required integration work

Container data needs stable placement ownership and joint world persistence.
The model history currently removes placements through `remove_instances`, and
placement identity can otherwise outlive or be reused independently of contents.
Guard nonempty removal, including undo/redo, before enabling a storage interface.
Region retirement must remain distinct from destruction: an unloaded container
must retain contents, and editing another region must not recreate or reassign it.
Reach/occlusion and current world readiness must be rechecked on each transfer.

Run `tools/run_godot_check.py inventory_transfer --headless --require INVENTORY_TRANSFER`.
For release use `tools/test_native_release.py --addon player_runtime --test inventory_transfer --godot <engine>`.

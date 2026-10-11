# Usable wooden chest storage — 2026-10-11

Storage now belongs to a dedicated wooden chest, not the existing shelf. Shelves
remain static furniture. Dismantling furniture for wood and loose book pickups
are separate unfinished interactions, not implied by this container feature.

## Play

Use the normal combined-world launcher. Press M, then 8 to select the wooden
storage chest; RMB places it. Gameplay construction costs eight wood; the free
editor stays free. Leave object/ground-cover mode and fly mode, approach within
three metres, aim at the chest and press E. Select a stack and quantity, then
Deposit or Take. Esc/Tab closes the panel. F5 saves after closing; wait for the
save confirmation before F9 reload. Filled chests must be emptied before deletion.

Existing furnished-world shelves are not converted. Place a chest explicitly.
The mesh has a closed static lid, plank seams and a latch; it has no opening
animation. [Exterior](chest_exterior.png), [inventory](inventory.png), and
[reopened inventory](reopened_inventory.png) are actual renderer captures.

## Implementation and bounds

- Original 0BSD baked mesh: 384 triangles, two opaque shared surfaces, one box
  collision proxy. Normal native spatial model batching/residency applies. Nearby
  chest collision has a 64 m radius, 256-proxy cap and eight-build admission budget.
- `NativeContainerStore` owns sparse nonempty inventories by stable placement ID
  within `storage/wooden_chest/v1`. There is no inventory allocation for empty
  chests and no per-chest Node, script, dynamic body or polling loop.
- 32 slots per inventory; all boxes share a private immutable item catalog.
  Transfers use native atomic inventory accounting and revision guards. Mutation
  is main-thread only; this is not a multiplayer authority implementation.
- Main world caps nonempty chests at 4,096. Encoded contents occupy 16 + 272*N
  bytes: 1,114,128 bytes at capacity. This is serialized size, not total runtime
  memory. Contents stay resident even when geometry unloads; content paging and
  large-world save latency remain unqualified.
- `chest_contents` is committed with player inventory and structures by the normal
  compound save. Absent sections default to empty. Runtime removal protection is
  rebuilt from saved contents, including explicit ownership handoff on reload.
  Invalid referenced IDs reject loading; cross-addon restore rollback is not added.
- GDScript coordinates UI and bounded events; accounting and binary validation
  remain native. Each transfer rechecks reach/occlusion and marks the world dirty.

## Evidence

- Debug and release: 23 checks each, covering isolated revision tokens, stale/ABA
  rejection, atomic capacity failure, sparse erasure, malformed input rejection,
  and full 4,096-container snapshot roundtrip.
- Existing player inventory and atomic transfer regressions pass after replacing
  per-container catalog copies with shared immutable schema ownership.
- Actual main world: 18 create + 18 fresh-process reopen checks at fullscreen
  1920x1080, cap60. Normal paid placement, E interaction, partial transfers,
  filled deletion/undo refusal, reach and wall obstruction, geometry unload/return,
  normal compound saving, same-process reload, emptying and deletion all pass.
- Debug/release DLLs built with pinned Zig and prebuilt godot-cpp. Source hashes,
  binaries' recorded hashes and process commands accompany the evidence.

The earlier shelf-based fixture failure is retained in `fixture_failure`: its
test changed SpinBox.value before apply() reparsed the old text, so it deposited
one item instead of seven. The fixture now enters quantity through the LineEdit.
That failure preceded the user's change to a dedicated chest.

These are correctness and short visual checks, not dense-scene performance,
endurance, thermal or human acceptance. No sustained 60 FPS claim follows from
the screenshots. M2 remains active; this closes one usable interior interaction.

Reproduce with `python tools/check_storage_world.py`. Native checks use
`tools/run_godot_check.py container_store --headless --require CONTAINER_STORE`
and `tools/test_native_release.py --addon player_runtime --test container_store`.

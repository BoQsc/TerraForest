# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks := 0
var failures := 0
var folder := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--corpse-patch-dir="):
			folder = argument.trim_prefix("--corpse-patch-dir=")
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print("PASS " if value else "FAIL ", label)

func inventory() -> RefCounted:
	var result: RefCounted = ClassDB.instantiate("NativePlayerInventory")
	for identity in [102, 201]:
		result.register_item(identity, 999)
	result.register_item(301, 1)
	return result

func corpses(player: RefCounted, capacity := 4096) -> RefCounted:
	var result: RefCounted = ClassDB.instantiate("NativeCorpseStore")
	result.configure(player, capacity, 8)
	return result

func capture(store: RefCounted, residents := [2501, 2502], anchors := [1001, 1002]) -> PackedByteArray:
	var token: Dictionary = store.corpse_patch_state()
	return store.capture_corpse_patch(PackedInt64Array(residents), PackedInt64Array(anchors), token.revision, token.owner)

func restore(store: RefCounted, bytes: PackedByteArray) -> Dictionary:
	var token: Dictionary = store.corpse_patch_state()
	return store.restore_corpse_patch(bytes, token.revision, token.owner)

func sealed(bytes: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes.slice(0, bytes.size() - 32))
	var result := bytes.slice(0, bytes.size() - 32)
	result.append_array(hash.finish())
	return result

func pose(point: Vector3) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for index in 15:
		result.append_array(PackedFloat32Array([1, 0, 0, point.x, 0, 1, 0, point.y + index * 0.01, 0, 0, 1, point.z]))
	return result

func write_bytes(name: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(folder.path_join(name), FileAccess.WRITE)
	check(file != null, "open isolated " + name)
	if file != null:
		file.store_buffer(bytes)

func run() -> void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	if not ClassDB.class_exists("NativeCorpseStore") or folder.is_empty():
		push_error("Corpse patch fixture requires native runtime and isolated output")
		quit(1)
		return
	var player := inventory()
	var store := corpses(player)
	if "--reopen" in OS.get_cmdline_user_args():
		check(store.restore_corpse_snapshot(FileAccess.get_file_as_bytes(folder.path_join("before.bin"))), "fresh process restores owned corpse snapshot")
		var owned := capture(store)
		check(owned == FileAccess.get_file_as_bytes(folder.path_join("owned.bin")), "fresh process exact owners, body poses and loot")
		check(restore(store, FileAccess.get_file_as_bytes(folder.path_join("empty.bin"))).ok, "fresh process scoped cleanup")
		check(store.capture_corpse_snapshot() == FileAccess.get_file_as_bytes(folder.path_join("cleared.bin")), "fresh process retains outside corpses")
		check(restore(store, owned).ok and store.capture_corpse_snapshot() == FileAccess.get_file_as_bytes(folder.path_join("before.bin")), "fresh process complete scoped rollback")
		finish()
		return
	var empty := capture(store)
	check(empty.size() == 2632 and store.validate_corpse_patch(empty), "empty selected residents have explicit corpse absence")
	check(capture(store, [2502, 2501], [1002, 1001]) == empty, "selected capture order canonical")
	var token: Dictionary = store.corpse_patch_state()
	check(restore(store, empty).changes == 0 and store.corpse_patch_state() == token, "empty no-op preserves revision")
	for pairs in [[[], []], [[2501], []], [[2501, 2501], [1001, 1002]], [[2501, 2502], [1001, 1001]], [[10], [1001]], [[2501], [0]], [[2757], [1001]]]:
		check(capture(store, pairs[0], pairs[1]).is_empty(), "invalid selection rejects " + str(pairs))
	var first: int = store.create_corpse(Vector3(100, 80, 100), -0.0, 1703, 2501, 1001)
	var second: int = store.create_corpse(Vector3(110, 80, 100), 1, 1703, 2502, 1002)
	var outside_id: int = store.create_corpse(Vector3(100, 80, 100), 2, 1703, 2503, 1003)
	var legacy_id: int = store.create_corpse(Vector3(100, 80, 100), 3, 1703)
	check(first > 0 and second > first and outside_id > second and legacy_id > outside_id, "owned and unowned corpses coexist at same position")
	check(store.corpse(first).resident == 2501 and store.corpse(first).anchor == 1001 and store.corpse(legacy_id).resident == 0, "native corpse exposes authoritative ownership")
	check(store.create_corpse(Vector3.ZERO, 0, 1703, 2501, 1010) == 0 and store.create_corpse(Vector3.ZERO, 0, 1703, 2504, 1001) == 0, "duplicate resident or authored anchor refuses duplicate loot")
	check(store.create_corpse(Vector3.ZERO, 0, 1703, 0, 1) == 0 and store.create_corpse(Vector3.ZERO, 0, 1703, 5000) == 0, "invalid owner refuses creation")
	check(store.update_corpse(first, Vector3(500, 81, 500), -0.0, 24, pose(Vector3(500, 81, 500))), "moved dismembered corpse retains owner")
	token = store.corpse_patch_state()
	check(store.update_corpse(first, Vector3(500, 81, 500), -0.0, 24, pose(Vector3(500, 81, 500))) and store.corpse_patch_state() == token, "identical pose update preserves revision")
	var owned := capture(store)
	var before: PackedByteArray = store.capture_corpse_snapshot()
	check(before.decode_u32(4) == 2 and store.validate_corpse_snapshot(before), "owned full snapshot uses version two")
	var outside_record: Dictionary = store.corpse(outside_id)
	var outside_inventory: Dictionary = store.snapshot(outside_id)
	var player_before: PackedByteArray = player.capture_storage_snapshot()
	check(capture(store, [2501], [999]).is_empty(), "incorrect anchor refuses capture")
	var result := restore(store, empty)
	check(result.ok and result.changes == 2 and store.corpse(first).is_empty() and store.corpse(second).is_empty(), "absence baseline removes only selected owned corpses")
	check(not store.has_contents(first) and not store.has_contents(second), "corpse cleanup removes owned loot atomically")
	check(store.corpse(outside_id) == outside_record and store.snapshot(outside_id) == outside_inventory and not store.corpse(legacy_id).is_empty(), "nearby outside and legacy bodies and live loot views preserved")
	check(player.capture_storage_snapshot() == player_before, "reset never grants or removes player items")
	var cleared: PackedByteArray = store.capture_corpse_snapshot()
	check(restore(store, owned).ok and store.capture_corpse_snapshot() == before and capture(store) == owned, "scoped rollback restores exact corpses and contents")
	check(not store.restore_corpse_patch(empty, token.revision, token.owner).ok, "old revision cannot clear restored corpse")
	token = store.corpse_patch_state()
	check(not store.restore_corpse_patch(empty, token.revision, token.owner + 1).ok, "different native owner rejects")
	check(store.capture_corpse_patch(PackedInt64Array([2501]), PackedInt64Array([1001]), token.revision - 1, token.owner).is_empty(), "stale capture rejects")
	check(restore(store, owned).changes == 0 and store.corpse_patch_state() == token, "populated no-op preserves revision")
	for field in [0, 4, 8, 12, 16, 24, 36, 44, 48, 60, 64, 68, 72, 792]:
		var broken := owned.duplicate()
		broken.encode_u32(field, 0xffffffff)
		broken = sealed(broken)
		check(not store.validate_corpse_patch(broken) and not restore(store, broken).ok and store.capture_corpse_snapshot() == before, "malformed patch rejects atomically at " + str(field))
	var bad := empty.duplicate()
	bad[49] = 1
	check(not restore(store, sealed(bad)).ok, "absence record cannot hide pose data")
	bad = owned.duplicate()
	bad[bad.size() - 1] ^= 1
	check(not restore(store, bad).ok and not restore(store, owned.slice(0, owned.size() - 1)).ok, "bad checksum and truncation reject")
	bad = owned.duplicate()
	bad.encode_u64(32, 999)
	check(store.validate_corpse_patch(sealed(bad)) and not restore(store, sealed(bad)).ok, "valid but wrong resident anchor rejects")
	bad = owned.duplicate()
	bad.encode_u64(40, outside_id)
	check(not restore(store, sealed(bad)).ok and store.corpse(outside_id) == outside_record, "outside corpse identity cannot be stolen")
	var snapshot_bad := before.duplicate()
	snapshot_bad.encode_u64(32 + 768 + 752, 2501)
	check(not store.restore_corpse_snapshot(snapshot_bad) and store.capture_corpse_snapshot() == before, "duplicate full-snapshot owner refuses atomically")
	var old := corpses(player)
	old.create_corpse(Vector3.ZERO, 0, 1703)
	var old_bytes: PackedByteArray = old.capture_corpse_snapshot()
	check(old_bytes.decode_u32(4) == 1 and old.restore_corpse_snapshot(old_bytes) and old.capture_corpse_snapshot() == old_bytes, "legacy unowned snapshot remains byte-identical with no guessed ownership")
	var view: Dictionary = store.snapshot(first)
	check(store.withdraw(first, player, 0, 1, player.snapshot().revision, view.store_revision).ok, "ordinary player can take corpse loot")
	check(not store.restore_corpse_patch(owned, token.revision, token.owner).ok, "loot transfer invalidates reset token")
	player_before = player.capture_storage_snapshot()
	check(restore(store, owned).ok and player.capture_storage_snapshot() == player_before, "rollback restoration never rolls back earned player loot")
	check(store.capture_corpse_snapshot() == before, "fixture restores exact owned corpse bytes")
	write_bytes("before.bin", before)
	write_bytes("owned.bin", owned)
	write_bytes("empty.bin", empty)
	write_bytes("cleared.bin", cleared)
	maximum_patch(player)
	finish()

func maximum_patch(player: RefCounted) -> void:
	var store := corpses(player, 64)
	var residents: Array = range(2501, 2565)
	var anchors: Array = range(1001, 1065)
	var empty := capture(store, residents, anchors)
	for index in 64:
		store.create_corpse(Vector3(index, 0, 0), 0, 1703, residents[index], anchors[index])
	var started := Time.get_ticks_usec()
	var full := capture(store, residents, anchors)
	var capture_us := Time.get_ticks_usec() - started
	check(full.size() == 82488 and store.validate_corpse_patch(full), "maximum corpse patch bounded")
	var before: PackedByteArray = store.capture_corpse_snapshot()
	started = Time.get_ticks_usec()
	var result := restore(store, empty)
	var clear_us := Time.get_ticks_usec() - started
	check(result.ok and result.changes == 64 and store.corpse_ids().is_empty(), "full-capacity selected cleanup")
	started = Time.get_ticks_usec()
	result = restore(store, full)
	var restore_us := Time.get_ticks_usec() - started
	check(result.ok and result.changes == 64 and store.capture_corpse_snapshot() == before, "full-capacity exact rollback")
	print("CORPSE_PATCH_MAX bytes=%d capture_us=%d clear_us=%d restore_us=%d" % [full.size(), capture_us, clear_us, restore_us])
	residents.append(2565)
	anchors.append(1065)
	check(capture(store, residents, anchors).is_empty(), "over-limit selection refuses")
	var small := corpses(player, 1)
	small.create_corpse(Vector3.ZERO, 0, 1703)
	var saved: PackedByteArray = small.capture_corpse_snapshot()
	check(not restore(small, full).ok and small.capture_corpse_snapshot() == saved, "capacity rejection keeps outside state")

func finish() -> void:
	print("CORPSE_PATCH checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

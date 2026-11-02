# SPDX-License-Identifier: 0BSD
extends SceneTree

var checks := 0
var failures := 0
var folder := ""
const SELECTED := [1, 2, 4]
const DAMAGE_KEYS := ["block:1:2:3", "model:chest:1", "new_inside"]

func _initialize() -> void:
	for addon in ["structures", "player_runtime"]:
		GDExtensionManager.load_extension("res://addons/%s/%s.gdextension" % [addon, addon])
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--owner-patch-dir="):
			folder = argument.trim_prefix("--owner-patch-dir=")
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print("PASS " if value else "FAIL ", label)

func hinges(animated := true) -> RefCounted:
	var state: RefCounted = ClassDB.instantiate("NativeHingedDoors")
	if animated:
		state.configure_animation(PackedFloat32Array([0, 0, 0.5, 0.4, 1, 1]), PackedFloat32Array([0, 1, 0.4, 0.6, 1, 0]))
	return state

func models() -> Node3D:
	var target: Node3D = ClassDB.instantiate("NativeStaticBatch")
	target.configure_collision_only()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 2, 0.14)
	target.configure_asset("test/door_patch", mesh)
	return target

func put(target: Node3D, identity: int, position: Vector3) -> bool:
	return target.upsert_instances(PackedInt64Array([identity]), PackedFloat32Array([1, 0, 0, position.x, 0, 1, 0, position.y, 0, 0, 1, position.z]))

func door_capture(state: RefCounted, ids = SELECTED) -> PackedByteArray:
	var token: Dictionary = state.door_patch_state()
	return state.capture_door_patch(PackedInt64Array(ids), token.revision, token.owner)

func door_restore(state: RefCounted, bytes: PackedByteArray) -> Dictionary:
	var token: Dictionary = state.door_patch_state()
	return state.restore_door_patch(bytes, token.revision, token.owner)

func model_capture(target: Node3D) -> PackedByteArray:
	var token: Dictionary = target.placement_patch_state()
	return target.capture_placement_patch(Vector3i.ZERO, Vector3i.ONE * 32, token.revision, token.owner)

func model_restore(target: Node3D, bytes: PackedByteArray) -> Dictionary:
	var token: Dictionary = target.placement_patch_state()
	return target.restore_placement_patch(bytes, token.revision, token.owner)

func damage_capture(state: RefCounted, keys = DAMAGE_KEYS) -> PackedByteArray:
	var token: Dictionary = state.damage_patch_state()
	return state.capture_damage_patch(PackedStringArray(keys), token.revision, token.owner)

func damage_restore(state: RefCounted, bytes: PackedByteArray) -> Dictionary:
	var token: Dictionary = state.damage_patch_state()
	return state.restore_damage_patch(bytes, token.revision, token.owner)

func seal(bytes: PackedByteArray) -> PackedByteArray:
	var payload := bytes.slice(0, bytes.size() - 32)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(payload)
	payload.append_array(hash.finish())
	return payload

func write_bytes(name: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(folder.path_join(name), FileAccess.WRITE)
	check(file != null, "evidence file " + name)
	if file != null:
		file.store_buffer(bytes)
		file.close()

func doors() -> void:
	var state := hinges()
	var target := models()
	for identity in [1, 2, 3]:
		put(target, identity, Vector3(identity * 4 if identity < 3 else 70, 2, 4))
	check(state.toggle(target, 1, AABB()).ok and state.animate_toggle(target, 2, AABB()).ok and state.animate_toggle(target, 3, AABB()).ok, "stable opened and partially moving doors")
	state.advance(target, 0.1)
	var baseline := door_capture(state)
	var model_baseline := model_capture(target)
	check(not baseline.is_empty() and not model_baseline.is_empty() and state.validate_door_patch(baseline), "selected baseline includes open moving and absent states")
	var members:Dictionary=target.placement_patch_members(model_baseline)
	check(members.ok and members.asset=="test/door_patch" and members.ids==PackedInt64Array([1,2]) and members.bounds==AABB(Vector3.ZERO,Vector3.ONE*32),"validated model original exposes exact namespaced membership")
	var invalid_model:=model_baseline.duplicate();invalid_model[80]^=1
	check(not target.placement_patch_members(invalid_model).ok,"corrupt model original never exposes trusted identities")
	var token: Dictionary = state.door_patch_state()
	check(door_restore(state, baseline).changes == 0 and state.door_patch_state() == token, "door no-op retains token")
	state.advance(target, 0.1)
	state.forget(2)
	put(target, 4, Vector3(16, 2, 4))
	state.toggle(target, 4, AABB())
	var outside := door_capture(state, PackedInt64Array([3]))
	var outside_pose: PackedFloat32Array = target.get_instance(3)
	write_bytes("doors_edited.bin", state.capture_storage_snapshot())
	write_bytes("models_edited.bin", target.capture_snapshot())
	check(not state.restore_door_patch(baseline, token.revision, token.owner).ok, "door mutation invalidates old token")
	token = state.door_patch_state()
	check(not state.restore_door_patch(baseline, token.revision, token.owner + 1).ok, "wrong door owner rejects")
	check(model_restore(target, model_baseline).ok and door_restore(state, baseline).ok, "composed model and hinge restoration")
	check(door_capture(state) == baseline and state.is_open(1) and state.is_moving(2) and not state.is_open(4), "selected door state restores exactly")
	check(door_capture(state, PackedInt64Array([3])) == outside and target.get_instance(3) == outside_pose, "outside moving door remains unchanged")
	write_bytes("doors_baseline.bin", baseline)
	write_bytes("models_baseline.bin", model_baseline)
	write_bytes("doors_expected.bin", state.capture_storage_snapshot())
	write_bytes("models_expected.bin", target.capture_snapshot())
	var before: Dictionary = state.motion_state(2)
	state.advance(target, 0.1)
	check(state.is_moving(2) and state.motion_state(2).time > before.time, "restored mid-swing continues from matching restored model pose")
	check(door_capture(state, PackedInt64Array([1, 1])).is_empty() and door_capture(state, PackedInt64Array([0])).is_empty() and door_capture(state, PackedInt64Array()).is_empty(), "duplicate zero and empty door selections reject")
	var corrupt := baseline.duplicate()
	corrupt[100] ^= 1
	var unchanged: PackedByteArray = state.capture_storage_snapshot()
	check(not door_restore(state, corrupt).ok and state.capture_storage_snapshot() == unchanged, "corrupt door patch leaves complete state intact")
	corrupt = baseline.duplicate()
	corrupt.encode_u32(4, 2)
	check(not state.validate_door_patch(seal(corrupt)), "future door patch version rejects")
	corrupt = baseline.duplicate()
	corrupt.encode_u32(88 + 8, 2)
	check(not state.validate_door_patch(seal(corrupt)), "moving door without closed pose rejects")
	corrupt = baseline.duplicate()
	corrupt.encode_s64(88 + 120, 1)
	check(not state.validate_door_patch(seal(corrupt)), "duplicate encoded identity rejects")
	corrupt = baseline.duplicate()
	corrupt.encode_double(88 + 120 + 112, 20.0)
	check(not state.validate_door_patch(seal(corrupt)), "out-of-clip elapsed time rejects")
	corrupt = baseline.duplicate()
	corrupt.encode_float(88 + 120 + 64 + 12, 12.0)
	check(not state.validate_door_patch(seal(corrupt)), "motion pose inconsistent with authored curve rejects")
	var incompatible := hinges(false)
	check(not incompatible.validate_door_patch(baseline), "animation profile mismatch rejects")
	var protection: Dictionary = {"calls": 0, "blocked": false}
	var observer := func():
		protection.calls += 1
		var current: Dictionary = state.door_patch_state()
		state.forget(1)
		protection.blocked = current.busy and door_capture(state).is_empty() and not door_restore(state, baseline).ok and state.capture_storage_snapshot().is_empty() and not state.restore_storage_snapshot(unchanged) and not state.toggle(target, 1, AABB()).ok
	target.changed.connect(observer)
	check(state.toggle(target, 1, AABB()).ok and protection.calls == 1 and protection.blocked and not state.is_open(1), "publication rejects reentrant mutation and mixed model/hinge capture")
	target.changed.disconnect(observer)
	state.restore_storage_snapshot(unchanged)
	token = state.door_patch_state()
	state.restore_storage_snapshot(unchanged)
	check(not state.restore_door_patch(baseline, token.revision, token.owner).ok, "whole door restore invalidates earlier token")
	target.free()

func door_limits() -> void:
	var state := hinges(false)
	var full := PackedByteArray()
	full.resize(8 + 65536 * 56)
	full.fill(0)
	full.encode_u32(0, 0x31524454)
	full.encode_u32(4, 65536)
	for index in 65536:
		var offset := 8 + index * 56
		full.encode_s64(offset, index + 1)
		for component in [0, 5, 10]:
			full.encode_float(offset + 8 + component * 4, 1)
	check(state.restore_storage_snapshot(full), "full 65536-open-door fixture")
	var ids := PackedInt64Array()
	for identity in range(1, 257):
		ids.append(identity)
	var started := Time.get_ticks_usec()
	var maximum := door_capture(state, ids)
	var captured_us := Time.get_ticks_usec() - started
	for identity in ids:
		state.forget(identity)
	started = Time.get_ticks_usec()
	var receipt := door_restore(state, maximum)
	var restored_us := Time.get_ticks_usec() - started
	check(maximum.size() == 30840 and receipt.ok and receipt.changes == 256, "maximum bounded door patch restores within full collection")
	print("DOOR_PATCH_MAX bytes=%d capture_us=%d restore_us=%d" % [maximum.size(), captured_us, restored_us])
	ids.append(257)
	check(door_capture(state, ids).is_empty(), "257-door selection rejects")
	var single := door_capture(state, PackedInt64Array([1]))
	var replacement := door_capture(state, PackedInt64Array([1, 70000]))
	state.forget(1)
	var target := models()
	put(target, 70000, Vector3(4, 2, 4))
	check(state.toggle(target, 70000, AABB()).ok, "replace one opened identity at global capacity")
	var token: Dictionary = state.door_patch_state()
	check(door_restore(state, single).reason == "capacity" and state.door_patch_state() == token, "door capacity overflow is atomic")
	check(door_restore(state, replacement).ok and state.is_open(1) and not state.is_open(70000), "net opened-door replacement fits full capacity")
	target.free()
	state = hinges()
	target = models()
	for identity in range(1, 34):
		put(target, identity, Vector3(identity * 4, 2, 4))
		if identity < 33:
			state.animate_toggle(target, identity, AABB())
	single = door_capture(state, PackedInt64Array([1]))
	replacement = door_capture(state, PackedInt64Array([1, 33]))
	state.forget(1)
	state.animate_toggle(target, 33, AABB())
	token = state.door_patch_state()
	check(state.moving_count() == 32 and door_restore(state, single).reason == "capacity" and state.door_patch_state() == token, "motion capacity overflow is atomic")
	check(door_restore(state, replacement).ok and state.is_moving(1) and not state.is_moving(33) and state.moving_count() == 32, "net moving-door replacement preserves bounded motion pool")
	target.free()

func damage() -> void:
	var state: RefCounted = ClassDB.instantiate("NativeWorldDurability")
	state.hit(DAMAGE_KEYS[0], 100, 20)
	state.hit(DAMAGE_KEYS[1], 200, 50)
	state.hit("outside", 300, 75)
	var baseline := damage_capture(state)
	check(not baseline.is_empty() and state.validate_damage_patch(baseline) and damage_capture(state, PackedStringArray([DAMAGE_KEYS[2], DAMAGE_KEYS[0], DAMAGE_KEYS[1]])) == baseline, "damage baseline is canonical and includes healthy absence")
	var token: Dictionary = state.damage_patch_state()
	check(damage_restore(state, baseline).changes == 0 and state.damage_patch_state() == token, "damage no-op retains revision")
	state.forget(DAMAGE_KEYS[0])
	state.hit(DAMAGE_KEYS[1], 200, 100)
	state.hit(DAMAGE_KEYS[2], 400, 80)
	state.hit("outside", 300, 5)
	write_bytes("damage_edited.bin", state.capture_storage_snapshot())
	check(not state.restore_damage_patch(baseline, token.revision, token.owner).ok, "damage mutations invalidate captured token")
	token = state.damage_patch_state()
	check(not state.restore_damage_patch(baseline, token.revision, token.owner + 1).ok, "wrong damage owner rejects")
	var receipt := damage_restore(state, baseline)
	check(receipt.ok and receipt.changes == 3 and state.damage(DAMAGE_KEYS[0], 100) == 20 and state.damage(DAMAGE_KEYS[1], 200) == 50 and state.damage(DAMAGE_KEYS[2], 400) == 0, "selected damage is restored and new damage removed")
	check(state.damage("outside", 300) == 80 and state.record_count() == 3, "outside damage remains unchanged")
	write_bytes("damage_baseline.bin", baseline)
	write_bytes("damage_expected.bin", state.capture_storage_snapshot())
	check(damage_capture(state, PackedStringArray(["same", "same"])).is_empty() and damage_capture(state, PackedStringArray([""])).is_empty() and damage_capture(state, PackedStringArray(["bad\nkey"])).is_empty(), "invalid damage selections reject")
	var corrupt := baseline.duplicate()
	corrupt[20] ^= 1
	var unchanged: PackedByteArray = state.capture_storage_snapshot()
	check(not damage_restore(state, corrupt).ok and state.capture_storage_snapshot() == unchanged, "corrupt damage patch is atomic")
	corrupt = baseline.duplicate()
	corrupt.encode_u32(16 + 8, 101)
	check(not state.validate_damage_patch(seal(corrupt)), "damage beyond maximum rejects")
	corrupt = baseline.duplicate()
	corrupt.encode_u32(16 + 4, 0)
	check(not state.validate_damage_patch(seal(corrupt)), "absent damage record cannot retain damage")
	token = state.damage_patch_state()
	state.repair(DAMAGE_KEYS[0], 100, 1)
	check(not state.restore_damage_patch(baseline, token.revision, token.owner).ok, "repair invalidates reset token")
	state.hit("destroyed", 1, 1)
	token = state.damage_patch_state()
	state.hit("destroyed", 1, 1)
	state.forget("absent")
	check(state.damage_patch_state() == token, "zero-effect hit and absent forget do not invalidate token")
	token = state.damage_patch_state()
	state.restore_storage_snapshot(unchanged)
	check(not state.restore_damage_patch(baseline, token.revision, token.owner).ok, "whole durability restore invalidates reset token")
	var inventory: RefCounted = ClassDB.instantiate("NativePlayerInventory")
	inventory.register_item(101, 999)
	var healthy := damage_capture(state, PackedStringArray(["harvest_node"]))
	token = state.damage_patch_state()
	check(not state.harvest_hit("harvest_node", 100, 20, 101, 10, 2, inventory, inventory.snapshot().revision + 1).ok and state.damage_patch_state() == token, "failed harvesting retains damage reset token")
	check(state.harvest_hit("harvest_node", 100, 20, 101, 10, 2, inventory, inventory.snapshot().revision).ok and state.damage_patch_state().revision > token.revision, "actual harvesting invalidates damage reset token")
	var player_items: PackedByteArray = inventory.capture_storage_snapshot()
	check(damage_restore(state, healthy).ok and inventory.capture_storage_snapshot() == player_items, "restoring world damage never refunds or removes player items")

func damage_limits() -> void:
	var state: RefCounted = ClassDB.instantiate("NativeWorldDurability")
	for index in 65536:
		state.hit("key%05d" % index, 100, 10)
	check(state.record_count() == 65536, "full damage capacity fixture")
	var baseline := damage_capture(state, PackedStringArray(["key00000"]))
	var replacement := damage_capture(state, PackedStringArray(["key00000", "replacement"]))
	state.forget("key00000")
	state.hit("replacement", 100, 10)
	var token: Dictionary = state.damage_patch_state()
	check(damage_restore(state, baseline).reason == "capacity" and state.damage_patch_state() == token, "damage capacity overflow is atomic")
	check(damage_restore(state, replacement).ok and state.damage("key00000", 100) == 10 and state.damage("replacement", 100) == 0, "net damage replacement fits full capacity")
	var keys := PackedStringArray()
	for index in 4096:
		keys.append("key%05d" % index)
	var started := Time.get_ticks_usec()
	baseline = damage_capture(state, keys)
	var captured_us := Time.get_ticks_usec() - started
	for key in keys:
		state.forget(key)
	started = Time.get_ticks_usec()
	var receipt := damage_restore(state, baseline)
	var restored_us := Time.get_ticks_usec() - started
	check(receipt.ok and receipt.changes == 4096 and state.record_count() == 65536, "4096 selected damage records restore among 65536")
	print("DAMAGE_PATCH_MAX bytes=%d capture_us=%d restore_us=%d" % [baseline.size(), captured_us, restored_us])
	keys.append("extra")
	check(damage_capture(state, keys).is_empty(), "4097 damage selections reject")
	keys.clear()
	for index in 4096:
		keys.append(("key%05d" % index) + "x".repeat(152))
	check(damage_capture(state, keys).size() == 704560, "maximum-length selected damage keys stay within byte cap")

func reopen() -> void:
	var state := hinges()
	var target := models()
	check(state.restore_storage_snapshot(FileAccess.get_file_as_bytes(folder.path_join("doors_edited.bin"))) and target.restore_snapshot(FileAccess.get_file_as_bytes(folder.path_join("models_edited.bin"))), "fresh process loads edited door/model state")
	check(model_restore(target, FileAccess.get_file_as_bytes(folder.path_join("models_baseline.bin"))).ok and door_restore(state, FileAccess.get_file_as_bytes(folder.path_join("doors_baseline.bin"))).ok, "fresh process uses current tokens for selected reset")
	check(target.capture_snapshot() == FileAccess.get_file_as_bytes(folder.path_join("models_expected.bin")) and state.capture_storage_snapshot() == FileAccess.get_file_as_bytes(folder.path_join("doors_expected.bin")), "fresh door/model restore matches exact expected bytes")
	state.advance(target, 0.1)
	check(state.is_moving(2), "fresh process resumes restored door motion")
	target.free()
	var durability: RefCounted = ClassDB.instantiate("NativeWorldDurability")
	check(durability.restore_storage_snapshot(FileAccess.get_file_as_bytes(folder.path_join("damage_edited.bin"))), "fresh process loads edited durability")
	check(damage_restore(durability, FileAccess.get_file_as_bytes(folder.path_join("damage_baseline.bin"))).ok and durability.capture_storage_snapshot() == FileAccess.get_file_as_bytes(folder.path_join("damage_expected.bin")), "fresh durability reset matches exact expected bytes")

func run() -> void:
	if folder.is_empty():
		check(false, "isolated output folder required")
	elif "--reopen" in OS.get_cmdline_user_args():
		reopen()
	else:
		doors()
		door_limits()
		damage()
		damage_limits()
	print("LOCATION_OWNER_PATCHES checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

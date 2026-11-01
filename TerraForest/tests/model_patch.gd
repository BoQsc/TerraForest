# SPDX-License-Identifier: 0BSD
extends SceneTree

var checks := 0
var failures := 0
var folder := ""
var signals_seen := 0
var callback_snapshot := PackedByteArray()

func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--model-patch-dir="):
			folder = argument.trim_prefix("--model-patch-dir=")
	run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print("PASS " if value else "FAIL ", description)

func batch(collision_only := true, asset := "patch_box") -> Node3D:
	var result: Node3D = ClassDB.instantiate("NativeStaticBatch")
	if collision_only:
		result.configure_collision_only()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 2.0
	result.configure_asset(asset, mesh)
	root.add_child(result)
	return result

func put(target: Node3D, identity: int, position: Vector3) -> bool:
	var transforms: Array[Transform3D] = [Transform3D(Basis.IDENTITY, position)]
	return target.upsert_transforms(PackedInt64Array([identity]), transforms)

func capture(target: Node3D, origin := Vector3i.ZERO, size := Vector3i.ONE * 32) -> PackedByteArray:
	var state: Dictionary = target.placement_patch_state()
	return target.capture_placement_patch(origin, size, state.revision, state.owner)

func restore(target: Node3D, bytes: PackedByteArray) -> Dictionary:
	var state: Dictionary = target.placement_patch_state()
	return target.restore_placement_patch(bytes, state.revision, state.owner)

func seal(bytes: PackedByteArray) -> PackedByteArray:
	var payload := bytes.slice(0, bytes.size() - 32)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(payload)
	payload.append_array(hash.finish())
	return payload

func write_bytes(name: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(folder.path_join(name), FileAccess.WRITE)
	check(file != null, "open evidence " + name)
	if file != null:
		file.store_buffer(bytes)
		file.close()

func observed(target: Node3D) -> void:
	signals_seen += 1
	callback_snapshot = target.capture_snapshot()

func basic() -> void:
	var target := batch()
	check(put(target, 1, Vector3(2, 2, 2)) and put(target, 2, Vector3(30, 2, 2)) and put(target, 3, Vector3(2, 2, 30)), "seed selected models")
	var neighbors := [Vector3(-2, 2, 2), Vector3(34, 2, 2), Vector3(2, -2, 2), Vector3(2, 34, 2), Vector3(2, 2, -2), Vector3(2, 2, 34)]
	for index in neighbors.size():
		put(target, 11 + index, neighbors[index])
	var baseline := capture(target)
	check(not baseline.is_empty() and target.validate_placement_patch(baseline) and capture(target) == baseline, "canonical deterministic capture")
	var state: Dictionary = target.placement_patch_state()
	check(restore(target, baseline).changes == 0 and target.placement_patch_state() == state, "no-op retains revision")
	check(target.capture_placement_patch(Vector3i.ZERO, Vector3i.ONE * 129, state.revision, state.owner).is_empty(), "oversized bounds reject")
	check(target.capture_placement_patch(Vector3i(-1048576, 0, 0), Vector3i.ONE, state.revision, state.owner).is_empty(), "invalid origin rejects")
	target.remove_instances(PackedInt64Array([1]))
	put(target, 2, Vector3(22, 2, 2))
	put(target, 4, Vector3(16, 2, 2))
	for index in neighbors.size():
		put(target, 11 + index, neighbors[index] + Vector3(0, 0.25, 0))
	target.set_removal_protected(11, true)
	target.set_instance_visual_hidden(12, true)
	var edited: PackedByteArray = target.capture_snapshot()
	check(not target.restore_placement_patch(baseline, state.revision, state.owner).ok and target.capture_snapshot() == edited, "stale capture token cannot overwrite later edits")
	state = target.placement_patch_state()
	check(not target.restore_placement_patch(baseline, state.revision, state.owner + 1).ok, "wrong live owner rejects")
	target.changed.connect(observed.bind(target))
	var receipt := restore(target, baseline)
	var expected: PackedByteArray = target.capture_snapshot()
	check(receipt.ok and receipt.changes == 3 and signals_seen == 1 and callback_snapshot == expected, "single publication exposes full replacement")
	check(capture(target) == baseline and target.get_instance(4).is_empty(), "deleted moved and added models restored")
	var intact := true
	for index in neighbors.size():
		var transform: PackedFloat32Array = target.get_instance(11 + index)
		intact = intact and is_equal_approx(transform[7], neighbors[index].y + 0.25)
	check(intact and target.is_removal_protected(11) and target.is_instance_visual_hidden(12), "all six outside faces and runtime ownership preserved")
	check(restore(target, baseline).changes == 0 and signals_seen == 1, "no-op emits no extra event")
	target.changed.disconnect(observed.bind(target))
	write_bytes("baseline.bin", baseline)
	write_bytes("edited.bin", edited)
	write_bytes("expected.bin", expected)
	var corrupt := baseline.duplicate()
	corrupt[40] ^= 1
	check(not restore(target, corrupt).ok and target.capture_snapshot() == expected, "checksum failure leaves all placements unchanged")
	corrupt = baseline.slice(0, baseline.size() - 1)
	check(not target.validate_placement_patch(corrupt), "truncation rejects")
	corrupt = baseline.duplicate()
	corrupt.encode_u32(4, 2)
	check(not target.validate_placement_patch(seal(corrupt)), "future patch version rejects")
	corrupt = baseline.duplicate()
	corrupt.encode_s32(20, 1)
	check(not target.validate_placement_patch(seal(corrupt)), "records extending past encoded region reject")
	var different := batch(true, "different")
	check(not different.validate_placement_patch(baseline), "asset mismatch rejects")
	different.free()
	different = batch()
	different.configure_collision(AABB(Vector3.ONE * -2, Vector3.ONE * 4), 0, 32, 8)
	check(not different.validate_placement_patch(baseline), "collision prototype mismatch rejects")
	different.free()
	put(target, 1, Vector3(70, 2, 2))
	edited = target.capture_snapshot()
	check(restore(target, baseline).reason == "outside_identity" and target.capture_snapshot() == edited, "baseline identity moved outside is not stolen back")
	put(target, 1, Vector3(2, 2, 2))
	put(target, 4, Vector3(0.5, 2, 2))
	check(capture(target).is_empty() and restore(target, baseline).reason == "boundary", "boundary-straddling object blocks reset")
	target.remove_instances(PackedInt64Array([4]))
	put(target, 4, Vector3(16, 2, 2))
	target.set_removal_protected(4, true)
	edited = target.capture_snapshot()
	check(restore(target, baseline).reason == "protected" and target.capture_snapshot() == edited, "nonempty-container protection retains current state")
	target.set_removal_protected(4, false)
	target.set_instance_visual_hidden(4, true)
	check(restore(target, baseline).reason == "protected", "actively hidden owner is not removed")
	target.set_instance_visual_hidden(4, false)
	check(restore(target, baseline).ok, "release runtime ownership then restore")
	var packet: PackedByteArray = target.capture_region(Vector3i.ZERO)
	check(target.unload_region(packet) and capture(target).is_empty() and restore(target, baseline).reason == "unavailable", "unloaded overlap is unavailable not empty")
	check(target.restore_region(packet) and restore(target, baseline).ok, "loaded region restores eligibility")
	target.free()

func paging_and_history() -> void:
	var target := batch()
	put(target, 1, Vector3(2, 2, 2))
	put(target, 2, Vector3(70, 2, 2))
	var baseline := capture(target)
	var packet: PackedByteArray = target.capture_region(Vector3i(2, 0, 0))
	check(target.unload_region(packet) and capture(target) == baseline and restore(target, baseline).ok, "unrelated unavailable region stays untouched")
	check(target.begin_region_admission(packet) and capture(target).is_empty() and restore(target, baseline).reason == "busy", "in-flight admission cannot race reset")
	target.cancel_region_admission()
	for step in 10:
		if not target.region_admission_stats().active:
			break
		target.advance_region_admission(64, 65536, 1000)
	check(target.restore_region(packet), "cancelled transfer rollback finishes before region reload")
	var history: RefCounted = ClassDB.instantiate("NativeStaticHistory")
	check(history.configure([target], 4096, 16), "configure ordinary model history")
	check(history.erase(target, 1), "ordinary history removal")
	check(restore(target, baseline).ok and not history.undo(), "reset revision forms undo history barrier")
	target.free()

func limits() -> void:
	var target := batch()
	var identities := PackedInt64Array()
	var transforms: Array[Transform3D] = []
	for index in 4096:
		identities.append(index + 1)
		transforms.append(Transform3D(Basis.IDENTITY, Vector3(2 + (index % 16) * 2, 2 + ((index / 16) % 16) * 2, 2 + (index / 256) * 2)))
	check(target.upsert_transforms(identities, transforms), "maximum baseline fixture")
	var started := Time.get_ticks_usec()
	var baseline := capture(target, Vector3i.ZERO, Vector3i.ONE * 64)
	var capture_us := Time.get_ticks_usec() - started
	check(not baseline.is_empty() and baseline.size() <= 229652, "bounded 4096-model binary baseline")
	target.remove_instances(identities)
	put(target, 5000, Vector3(70, 2, 2))
	started = Time.get_ticks_usec()
	var receipt := restore(target, baseline)
	var restore_us := Time.get_ticks_usec() - started
	check(receipt.ok and receipt.changes == 4096 and target.get_ids().size() == 4097, "maximum baseline preserves outside model")
	print("MODEL_PATCH_MAX bytes=%d capture_us=%d restore_us=%d" % [baseline.size(), capture_us, restore_us])
	put(target, 5001, Vector3(2, 2, 2))
	check(capture(target, Vector3i.ZERO, Vector3i.ONE * 64).is_empty(), "4097 selected models reject")
	target.free()
	target = batch()
	identities.clear()
	transforms.clear()
	for index in 16385:
		identities.append(index + 1)
		transforms.append(Transform3D(Basis.IDENTITY, Vector3(20, 20, 20) if index else Vector3(2, 2, 2)))
	target.upsert_transforms(identities, transforms)
	check(capture(target, Vector3i.ZERO, Vector3i.ONE * 4).is_empty(), "dense shared group respects candidate work cap")
	target.free()

func full_capacity() -> void:
	var target := batch()
	put(target, 1, Vector3(2, 2, 2))
	var baseline := capture(target)
	var identities := PackedInt64Array()
	var transforms := PackedFloat32Array()
	identities.resize(99999)
	transforms.resize(99999 * 12)
	for index in 99999:
		identities[index] = index + 2
		transforms[index * 12] = 1
		transforms[index * 12 + 5] = 1
		transforms[index * 12 + 10] = 1
		transforms[index * 12 + 3] = 1000
		transforms[index * 12 + 7] = 2
		transforms[index * 12 + 11] = 2
	check(target.upsert_instances(identities, transforms), "full collection capacity fixture")
	target.remove_instances(PackedInt64Array([1]))
	put(target, 100001, Vector3(1000, 2, 2))
	var state: Dictionary = target.placement_patch_state()
	check(restore(target, baseline).reason == "capacity" and target.placement_patch_state() == state and target.get_ids().size() == 100000, "capacity failure changes nothing")
	put(target, 100001, Vector3(2, 2, 2))
	check(restore(target, baseline).ok and not target.get_instance(1).is_empty() and target.get_instance(100001).is_empty(), "net replacement succeeds at full global capacity")
	target.free()
	target = batch()
	put(target, 1, Vector3(2, 2, 2))
	baseline = capture(target, Vector3i.ZERO, Vector3i.ONE * 64)
	target.remove_instances(PackedInt64Array([1]))
	identities.clear()
	transforms.clear()
	for index in 4096:
		identities.append(index + 2)
		transforms.append_array(PackedFloat32Array([1, 0, 0, (index + 10) * 32 + 2, 0, 1, 0, 2, 0, 0, 1, 2]))
	check(target.upsert_instances(identities, transforms), "full region capacity fixture")
	state = target.placement_patch_state()
	check(restore(target, baseline).reason == "capacity" and target.placement_patch_state() == state, "region capacity failure changes nothing")
	put(target, 2, Vector3(34, 2, 2))
	check(restore(target, baseline).ok and target.get_instance(2).is_empty(), "net region replacement counts removed and added groups")
	target.free()

func settle_collision(target: Node3D) -> void:
	for step in 30:
		await physics_frame
		await process_frame
		var status: Dictionary = target.collision_stats()
		if not status.selection_pending and status.pending_bodies == 0:
			break
	await physics_frame
	await process_frame

func ray_at(position: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 4, position - Vector3.UP * 4, 2)
	return root.get_world_3d().direct_space_state.intersect_ray(query)

func physical() -> void:
	var target := batch()
	target.position = Vector3(100, 0, 0)
	target.configure_collision(AABB(-Vector3.ONE, Vector3.ONE * 2), 96, 32, 8)
	target.set_collision_focus(Vector3(16, 2, 16))
	put(target, 1, Vector3(2, 2, 2))
	put(target, 2, Vector3(2, 2, -4))
	var baseline := capture(target, Vector3i.ZERO, Vector3i.ONE * 64)
	await settle_collision(target)
	check(not ray_at(Vector3(102, 2, 2)).is_empty(), "baseline has real physics body")
	var outside: RID = target.collision_body_for(2)
	put(target, 1, Vector3(34, 2, 2))
	put(target, 3, Vector3(18, 2, 2))
	await settle_collision(target)
	check(not ray_at(Vector3(134, 2, 2)).is_empty(), "edited placement moved across native region")
	check(restore(target, baseline).ok and target.collision_body_for(2) == outside, "local reset preserves outside live body")
	check(not target.is_collision_region_ready(AABB(Vector3(101, 1, 1), Vector3.ONE * 2)), "changed collision reports unavailable until rebuilt")
	await settle_collision(target)
	check(not ray_at(Vector3(102, 2, 2)).is_empty() and ray_at(Vector3(134, 2, 2)).is_empty() and ray_at(Vector3(118, 2, 2)).is_empty(), "physics republishes baseline without old or added ghost bodies")
	var probes: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(102, 2, 2)), Transform3D(Basis.IDENTITY, Vector3(134, 2, 2))]
	check(target.overlap_mask(probes, AABB(-Vector3.ONE * 0.1, Vector3.ONE * 0.2)) == PackedByteArray([1, 0]), "vegetation and placement exclusion sees restored local bounds")
	target.free()

func run() -> void:
	if folder.is_empty():
		check(false, "isolated evidence folder required")
	elif "--reopen" in OS.get_cmdline_user_args():
		var target := batch()
		var baseline := FileAccess.get_file_as_bytes(folder.path_join("baseline.bin"))
		check(target.restore_snapshot(FileAccess.get_file_as_bytes(folder.path_join("edited.bin"))), "fresh-process edited snapshot loads")
		check(restore(target, baseline).ok, "fresh-process baseline restores with current live token")
		check(target.capture_snapshot() == FileAccess.get_file_as_bytes(folder.path_join("expected.bin")), "fresh process matches exact expected world")
		target.free()
	else:
		basic()
		paging_and_history()
		limits()
		full_capacity()
		await physical()
	print("MODEL_PATCH checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

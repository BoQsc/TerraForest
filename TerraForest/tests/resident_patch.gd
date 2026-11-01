# SPDX-License-Identifier: 0BSD
extends SceneTree

var checks := 0
var failures := 0
var folder := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resident-patch-dir="):
			folder = argument.trim_prefix("--resident-patch-dir=")
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print("PASS " if value else "FAIL ", label)

func capture(store: RefCounted, ids: Array) -> PackedByteArray:
	var token: Dictionary = store.resident_patch_state()
	return store.capture_resident_patch(PackedInt64Array(ids), token.revision, token.owner)

func restore(store: RefCounted, bytes: PackedByteArray) -> Dictionary:
	var token: Dictionary = store.resident_patch_state()
	return store.restore_resident_patch(bytes, token.revision, token.owner)

func sealed(bytes: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes.slice(0, bytes.size() - 32))
	var result := bytes.slice(0, bytes.size() - 32)
	result.append_array(hash.finish())
	return result

func anchors(count: int) -> Array:
	var result: Array = []
	for index in count:
		result.append({"key": 1001 + index, "position": Vector3(400 + (index % 16) * 10, 80, 400 + (index / 16) * 10), "yaw": -0.0 if index == 0 else 0.25, "pose": 1 + index % 2})
	return result

func outside(bytes: PackedByteArray, ids: Array) -> PackedByteArray:
	var result := bytes.duplicate()
	for identity: int in ids:
		for offset in range(32 + (identity - 1) * 140, 32 + identity * 140):
			result[offset] = 0
	return result

func contains(store: RefCounted, identity: int, position: Vector3) -> bool:
	var count := 0
	for record: Dictionary in store.nearby(position, 2.0):
		if record.id == identity:
			count += 1
	return count == 1

func write_bytes(name: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(folder.path_join(name), FileAccess.WRITE)
	check(file != null, "open isolated " + name)
	if file != null:
		file.store_buffer(bytes)

func run() -> void:
	if not ClassDB.class_exists("NativeZombiePopulation"):
		GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	if not ClassDB.class_exists("NativeZombiePopulation") or folder.is_empty():
		push_error("Resident patch fixture requires native runtime and isolated output")
		quit(1)
		return
	var store: RefCounted = ClassDB.instantiate("NativeZombiePopulation")
	if "--reopen" in OS.get_cmdline_user_args():
		check(store.restore_snapshot(FileAccess.get_file_as_bytes(folder.path_join("mutated.bin"))), "fresh process restores mutated world component")
		var result := restore(store, FileAccess.get_file_as_bytes(folder.path_join("baseline.bin")))
		check(result.ok and result.changes == 2, "fresh process restores only selected authored residents")
		check(store.capture_snapshot() == FileAccess.get_file_as_bytes(folder.path_join("expected.bin")), "fresh process exact population bytes")
		check(contains(store, 2501, store.resident(2501).position), "fresh process revives local spatial membership")
		finish()
		return
	check(capture(store, [2501]).is_empty(), "uninitialized population refuses capture")
	check(store.initialize(1703, Vector3.ZERO), "initialize population")
	check(store.register_sleepers(anchors(3)).added == 3, "register stable authored identities")
	var selected := [2501, 2502]
	var baseline := capture(store, selected)
	check(baseline.size() == 360 and store.validate_resident_patch(baseline), "bounded canonical resident patch")
	check(capture(store, [2502, 2501]) == baseline, "capture order canonicalized")
	for invalid in [[], [1], [2500], [2504], [2501, 2501], [-1]]:
		check(capture(store, invalid).is_empty(), "reject invalid or non-authored selection " + str(invalid))
	var token: Dictionary = store.resident_patch_state()
	check(capture(store, selected) == baseline and store.resident_patch_state() == token, "capture never mutates")
	var result := restore(store, baseline)
	check(result.ok and result.changes == 0 and result.buckets == 0 and store.resident_patch_state() == token, "exact no-op does not invalidate revision or rebuild buckets")
	var first: Dictionary = store.resident(2501)
	check(not store.update_resident(2501, first.position, first.yaw, PackedByteArray()), "authored identity cannot lose required vitals")
	check(store.resident_patch_state() == token, "failed update leaves revision unchanged")
	var dead: PackedByteArray = first.vitals.duplicate()
	dead.encode_float(0, 0)
	check(store.update_resident(2501, Vector3(900, 80, 900), 0.5, dead), "selected resident can die away from home")
	var second: Dictionary = store.resident(2502)
	var wound: PackedByteArray = second.vitals.duplicate()
	wound.encode_float(0, 23)
	check(store.update_resident(2502, Vector3(1100, 90, 1100), 0.9, wound), "selected resident can travel and wake")
	var third: Dictionary = store.resident(2503)
	check(store.update_resident(2503, Vector3(1200, 80, 1200), 0.8, wound), "outside authored resident changes independently")
	check(store.exclude(10), "outside ambient resident exclusion")
	var mutated: PackedByteArray = store.capture_snapshot()
	check(not store.restore_resident_patch(baseline, token.revision, token.owner).ok and store.capture_snapshot() == mutated, "stale revision rejects without mutation")
	token = store.resident_patch_state()
	check(not store.restore_resident_patch(baseline, token.revision, token.owner + 1).ok, "different native owner rejects")
	check(store.capture_resident_patch(PackedInt64Array(selected), token.revision - 1, token.owner).is_empty(), "stale capture rejects")
	var dead_patch := capture(store, selected)
	check(store.validate_resident_patch(dead_patch), "dead baseline is valid for rollback")
	result = restore(store, baseline)
	check(result.ok and result.changes == 2 and result.buckets <= 3, "selected revive restores only affected spatial buckets")
	check(capture(store, selected) == baseline, "exact vitals, sleep, pose, identity and signed-zero yaw restored")
	check(outside(store.capture_snapshot(), selected) == outside(mutated, selected), "all outside resident bytes retained")
	check(contains(store, 2501, first.position) and contains(store, 2502, second.position), "revived residents indexed exactly once at home")
	check(not contains(store, 2502, Vector3(1100, 90, 1100)), "old travelled spatial membership removed")
	var expected: PackedByteArray = store.capture_snapshot()
	check(restore(store, dead_patch).ok and store.capture_snapshot() == mutated, "rollback retains dead resident tombstone and outside changes")
	check(restore(store, baseline).ok and store.capture_snapshot() == expected, "repeat reset has no resident duplication")
	for field in [0, 4, 8, 12, 16, 28, 32, 56, 60, 64, 124, 180]:
		var bad := baseline.duplicate()
		bad.encode_u32(field, 0xffffffff)
		bad = sealed(bad)
		token = store.resident_patch_state()
		check(not store.validate_resident_patch(bad) and not restore(store, bad).ok and store.capture_snapshot() == expected and store.resident_patch_state() == token, "malformed field rejects atomically at " + str(field))
	var bad := baseline.duplicate()
	bad.encode_u64(172, 9007199254740992)
	check(not store.validate_resident_patch(sealed(bad)) and not restore(store, sealed(bad)).ok, "over-limit anchor rejects")
	bad = baseline.duplicate()
	bad[bad.size() - 1] ^= 1
	check(not restore(store, bad).ok, "checksum mismatch rejects")
	bad = baseline.slice(0, baseline.size() - 1)
	check(not restore(store, bad).ok, "truncated patch rejects")
	bad = baseline.duplicate()
	bad.encode_u64(180, 2501)
	check(not restore(store, sealed(bad)).ok, "duplicate sorted identity rejects")
	bad = baseline.duplicate()
	bad.encode_u64(320, 1001)
	check(not restore(store, sealed(bad)).ok, "duplicate authored anchor rejects")
	bad = baseline.duplicate()
	bad.encode_u64(172, 9000)
	check(store.validate_resident_patch(sealed(bad)) and not restore(store, sealed(bad)).ok and store.capture_snapshot() == expected, "valid but differently owned anchor cannot replace resident")
	var other: RefCounted = ClassDB.instantiate("NativeZombiePopulation")
	other.initialize(1704, Vector3.ZERO)
	other.register_sleepers(anchors(3))
	check(not restore(other, baseline).ok, "different world seed refuses patch")
	other = ClassDB.instantiate("NativeZombiePopulation")
	other.initialize(1703, Vector3(10, 0, 10))
	other.register_sleepers(anchors(3))
	check(not restore(other, baseline).ok, "different arrival profile refuses patch")
	other = ClassDB.instantiate("NativeZombiePopulation")
	other.initialize(1703, Vector3.ZERO)
	other.register_sleepers(anchors(1))
	other.update_resident(2501, Vector3(950, 90, 950), 0.7, wound)
	var other_before: PackedByteArray = other.capture_snapshot()
	check(not restore(other, baseline).ok and other.capture_snapshot() == other_before, "missing target rejects entire patch before first replacement")
	var amputated: PackedByteArray = first.vitals.duplicate()
	amputated.encode_float(12, 0)
	amputated.encode_float(16, 0)
	amputated.encode_u32(56, (1 << 3) | (1 << 4))
	var waking: PackedByteArray = first.sleep.duplicate()
	waking.encode_u32(4, 2)
	waking.encode_float(8, 0.5)
	waking.encode_u32(32, 2)
	waking.encode_float(40, 0.5)
	check(store.update_resident(2501, first.position, first.yaw, amputated, waking), "waking amputated resident records valid phase")
	var waking_patch := capture(store, [2501])
	check(store.validate_resident_patch(waking_patch) and restore(store, baseline).ok and restore(store, waking_patch).ok and capture(store, [2501]) == waking_patch, "limb state and mid-wake phase restore exactly")
	check(restore(store, baseline).ok and store.capture_snapshot() == expected, "sleeping baseline clears prior injuries and wake phase")
	var spawned: int = store.add_resident(Vector3(1300, 80, 1300), 0, first.vitals)
	check(spawned == 2504 and capture(store, [spawned]).is_empty(), "unauthored developer-spawned residents cannot be captured")
	check(store.restore_snapshot(expected), "remove only fixture developer addition through full test restore")
	token = store.resident_patch_state()
	check(store.restore_snapshot(expected) and not store.restore_resident_patch(baseline, token.revision, token.owner).ok, "whole snapshot restore invalidates old token")
	write_bytes("mutated.bin", mutated)
	write_bytes("baseline.bin", baseline)
	write_bytes("expected.bin", expected)
	maximum_patch()
	finish()

func maximum_patch() -> void:
	var store: RefCounted = ClassDB.instantiate("NativeZombiePopulation")
	store.initialize(1703, Vector3.ZERO)
	check(store.register_sleepers(anchors(256)).added == 256, "full authored capacity")
	var identities: Array = range(2501, 2757)
	var started := Time.get_ticks_usec()
	var baseline := capture(store, identities)
	var capture_us := Time.get_ticks_usec() - started
	check(baseline.size() == 37952 and store.validate_resident_patch(baseline), "maximum patch bytes bounded")
	var expected: PackedByteArray = store.capture_snapshot()
	for identity: int in identities:
		var record: Dictionary = store.resident(identity)
		var vitals: PackedByteArray = record.vitals.duplicate()
		if identity % 2 == 0:
			vitals.encode_float(0, 0)
		store.update_resident(identity, Vector3(1000, 90, 1000), 1, vitals)
	started = Time.get_ticks_usec()
	var result := restore(store, baseline)
	var restore_us := Time.get_ticks_usec() - started
	check(result.ok and result.changes == 256 and store.capture_snapshot() == expected, "maximum full-population selected restore exact")
	print("RESIDENT_PATCH_MAX bytes=%d capture_us=%d restore_us=%d buckets=%d" % [baseline.size(), capture_us, restore_us, result.buckets])
	identities.append(2757)
	check(capture(store, identities).is_empty(), "over-limit request rejects")

func finish() -> void:
	print("RESIDENT_PATCH checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

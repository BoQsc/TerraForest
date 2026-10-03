# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var store: RefCounted = ClassDB.instantiate("NativeEntityStore")
	check(store.capture_storage_snapshot().is_empty(), "unconfigured pool cannot publish snapshot")
	store.configure(100000)
	var empty: PackedByteArray = store.capture_storage_snapshot()
	check(empty.size() == 24 and store.validate_snapshot(empty), "configured empty store has valid compact snapshot")
	var ids: PackedInt64Array = store.spawn_grid(100000, Vector3(-100, 20, -100), 4, Vector3(1, 2, 3))
	store.despawn(ids[42])
	var start := Time.get_ticks_usec()
	var saved: PackedByteArray = store.capture_storage_snapshot()
	var capture_us := Time.get_ticks_usec() - start
	check(saved.size() == 24 + 99999 * 32, "snapshot stores live rows only at 32 bytes each")
	for mutation: int in 8:
		var bad := saved.duplicate()
		match mutation:
			0: bad.encode_u32(0, 0)
			1: bad.encode_u32(4, 3)
			2: bad.encode_u32(8, 262145)
			3: bad.encode_u32(12, 100001)
			4: bad.resize(bad.size() - 1)
			5: bad.append(0)
			6: bad.encode_float(32, INF)
			7: bad.encode_float(44, NAN)
		check(not store.validate_snapshot(bad) and not store.restore_storage_snapshot(bad) and store.capture_storage_snapshot() == saved and store.contains(ids[0]), "malformed snapshot leaves live state intact %d" % mutation)
	start = Time.get_ticks_usec()
	check(store.restore_storage_snapshot(saved), "restore replaces live pool")
	var restore_us := Time.get_ticks_usec() - start
	check(store.capture_storage_snapshot() == saved and not store.contains(ids[0]) and not store.contains(ids[-1]), "round trip exact and previous runtime handles invalidated")
	var query: Dictionary = store.query_sphere(Vector3(-100, 20, -100), 0)
	check(query.complete and query.ids.size() == 1, "restored spatial index finds entity")
	var handle: int = query.ids[0]
	store.step(0.1)
	check(store.get_position(handle).is_equal_approx(Vector3(-99.9, 20.2, -99.7)), "restored velocity drives next simulation tick")
	var archive: RefCounted = ClassDB.instantiate("NativeWorldArchive")
	var packed: PackedByteArray = archive.encode({"terrain": PackedByteArray([1]), "entities": saved})
	var decoded: Dictionary = archive.decode(packed)
	var provider := preload("res://addons/world_runtime/world_persistence.gd").new()
	check(provider.register_component("entities", store.capture_storage_snapshot, store.restore_storage_snapshot, store, empty), "entity codec registers with compound world persistence")
	provider._restore(decoded.sections, 4)
	check(provider._capture().sections.entities == saved and not store.contains(handle), "compound provider restores and captures exact entity section")
	var damaged := packed.duplicate()
	damaged[damaged.size() - 1] ^= 1
	check(not archive.decode(damaged).ok, "compound archive detects entity payload corruption")
	check(store.restore_storage_snapshot(empty) and store.statistics().active == 0 and store.statistics().spatial_cells == 0, "empty world restore clears population and spatial index")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/entity_storage.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures": failures, "rows": 99999, "bytes": saved.size(), "capture_us": capture_us, "restore_us": restore_us, "scope": "native codec and compound provider integration; no gameplay population or streaming"}, "  "))
	file.close()
	quit(1 if failures else 0)

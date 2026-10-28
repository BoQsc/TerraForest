extends SceneTree

var failures := 0
var checks := 0
var rows: Array = []

func mesh_fingerprint(blocks: Node3D) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	for child in blocks.get_children():
		if child is MeshInstance3D:
			hash.update(var_to_bytes(child.position))
			hash.update(var_to_bytes(child.mesh.get_faces()))
	return hash.finish().hex_encode()

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func run() -> void:
	var blocks: Node3D = ClassDB.instantiate("NativeBlockWorld")
	root.add_child(blocks)
	blocks.set_collision_radius(0)
	blocks.set_process(false)
	var empty: PackedByteArray = blocks.capture_snapshot()
	for name in ["cottage_thin_roof_a2", "village_shop_hipped_r1", "village_shop_thin_roof_b2", "large_house_c1"]:
		blocks.restore_snapshot(empty)
		var prefab: Resource = load("res://addons/structures/prefabs/" + name + ".tres")
		check(blocks.set_cells(prefab.get_records()), name + " block records authored unchanged")
		blocks.flush_bakes()
		check(blocks.geometry_lod_stats().chunks_with_lods > 0, name + " has reduced geometry")
		rows.append({"name": name, "lod": blocks.geometry_lod_stats(), "streaming": blocks.streaming_stats()})
		var snapshot: PackedByteArray = blocks.capture_snapshot()
		var jobs: int = blocks.stats().worker_jobs_submitted
		blocks.set_geometry_lod_enabled(false)
		blocks.set_geometry_lod_enabled(true)
		check(blocks.capture_snapshot() == snapshot and blocks.stats().worker_jobs_submitted == jobs, name + " toggle neither edits nor rebakes")
		var mesh_hash := mesh_fingerprint(blocks)
		var records: PackedInt32Array = prefab.get_records()
		var target := Vector3i(records[0], records[1], records[2])
		var top := Vector3(target) + Vector3(.5, 20, .5)
		var bottom := top - Vector3(0, 40, 0)
		var original_hit: Dictionary = blocks.raycast_cells(top, bottom)
		check(blocks.set_cells(PackedInt32Array([target.x, target.y, target.z, 0])), name + " removes one real cell")
		blocks.flush_bakes()
		check(blocks.get_cell(target) == 0 and blocks.capture_snapshot() != snapshot, name + " LOD does not preserve deleted cell")
		check(blocks.restore_snapshot(snapshot), name + " restores saved authority")
		blocks.flush_bakes()
		check(mesh_fingerprint(blocks) == mesh_hash and blocks.raycast_cells(top, bottom) == original_hit, name + " rebuild preserves near geometry and authoritative picking")
	blocks.configure_streaming(true, 64, 32, 4 * 1024 * 1024, 4 * 1024 * 1024)
	blocks.set_focus(Vector3.ZERO)
	blocks.set_collision_radius(64)
	blocks.flush_bakes()
	blocks.set_focus(Vector3(1000, 0, 1000)); blocks.flush_bakes()
	blocks.set_focus(Vector3.ZERO); blocks.flush_bakes()
	var near_hash := mesh_fingerprint(blocks)
	var jobs: int = blocks.stats().worker_jobs_submitted
	var geometry: Dictionary = blocks.geometry_lod_stats()
	var collider_count: int = blocks.collision_stats().live_pieces
	check(blocks.collision_stats().ready and collider_count > 0, "full-detail collision is ready")
	for enabled in [false, true]:
		blocks.set_geometry_lod_enabled(enabled)
		check(blocks.collision_stats().live_pieces == collider_count and mesh_fingerprint(blocks) == near_hash, "LOD toggle preserves collision and full-detail faces")
	for trip in 8:
		blocks.set_focus(Vector3(1000, 0, 1000)); blocks.flush_bakes()
		blocks.set_focus(Vector3.ZERO); blocks.flush_bakes()
	check(blocks.stats().worker_jobs_submitted == jobs and mesh_fingerprint(blocks) == near_hash, "cached LOD round trips submit no worker jobs")
	check(blocks.geometry_lod_stats().index_bytes == geometry.index_bytes and blocks.geometry_lod_stats().bake_total_ms == geometry.bake_total_ms, "cached LODs retain all levels without rebaking")
	var stream: Dictionary = blocks.streaming_stats()
	check(stream.mesh_payload_bytes <= stream.mesh_byte_limit and stream.cache_capacity_bytes <= stream.cache_byte_limit, "LOD vertices and indices are inside existing memory budgets")
	var path := "user://building_lod_settings_test.cfg"
	ProjectSettings.set_setting("terraforest/graphics_settings_path", path)
	var config := ConfigFile.new()
	config.set_value("graphics", "fullscreen", false)
	config.save(path)
	var policy = preload("res://addons/structures/building_lod.gd")
	policy.apply(blocks)
	check(blocks.is_geometry_lod_enabled(), "LOD defaults on without a saved preference")
	policy.set_enabled(blocks, false, true)
	policy.apply(blocks)
	config.load(path)
	check(not blocks.is_geometry_lod_enabled() and not config.get_value("graphics", "fullscreen"), "LOD preference persists without overwriting fullscreen")
	policy.set_enabled(blocks, true, false)
	policy.apply(blocks)
	check(not blocks.is_geometry_lod_enabled(), "temporary toggle does not persist")
	DirAccess.remove_absolute(path)
	ProjectSettings.set_setting("terraforest/graphics_settings_path", null)
	blocks.set_collision_radius(0)
	blocks.configure_streaming(false, 384, 256, 64 * 1024 * 1024, 32 * 1024 * 1024)
	blocks.restore_snapshot(empty)
	var shape_cells := PackedInt32Array()
	var expected_faces := 0
	var ordinal := 0
	for shape in range(1, 19):
		for rotation in range(4 if shape <= 8 else 24):
			shape_cells.append_array(PackedInt32Array([2 + ordinal % 16 * 3, 3, 2 + ordinal / 16 * 3, blocks.encode_block(shape, rotation, rotation % 4)]))
			expected_faces += blocks.preview_mesh(shape, rotation).get_faces().size()
			ordinal += 1
	check(blocks.set_cells(shape_cells), "all 18 shapes and all 272 supported orientations author successfully")
	blocks.flush_bakes()
	var actual_faces := 0
	for child in blocks.get_children():
		if child is MeshInstance3D: actual_faces += child.mesh.get_faces().size()
	check(actual_faces == expected_faces, "near shape triangles stay identical to original preview templates")
	check(blocks.geometry_lod_stats().chunks_with_lods > 0, "mixed curved and planar shape fixture receives LODs")
	rows.append({"name": "all_shapes_rotations", "lod": blocks.geometry_lod_stats(), "streaming": blocks.streaming_stats()})
	DirAccess.make_dir_recursive_absolute("res://reports/building_lod")
	FileAccess.open("res://reports/building_lod/result.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "rows": rows}, "  "))
	print("BUILDING_LOD ", JSON.stringify({"checks": checks, "failures": failures, "rows": rows}))
	blocks.free()
	quit(1 if failures else 0)

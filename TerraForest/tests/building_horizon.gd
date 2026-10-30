extends SceneTree

var checks := 0
var failures := 0
var blocks: Node3D
var pager: RefCounted
var checkpoint := PackedByteArray()
var focus := Vector3.ZERO
var output := "res://reports/building_horizon"
var images := false
var rows: Array = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func settle() -> bool:
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		if pager != null: pager.step(focus, checkpoint)
		await process_frame
		if blocks.distant_rendering_stats().ready and blocks.is_idle(): return true
	return false

func fingerprint() -> String:
	var parts := PackedByteArray()
	for child in blocks.get_node("DistantBuildings").get_children():
		parts.append_array(var_to_bytes([child.position, child.mesh.get_faces()]))
	return parts.hex_encode().sha256_text()

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--horizon-images": images = true
		if argument.begins_with("--horizon-output="): output = argument.trim_prefix("--horizon-output=")
	DirAccess.make_dir_recursive_absolute(output)
	Engine.max_fps = 120
	blocks = ClassDB.instantiate("NativeBlockWorld")
	root.add_child(blocks)
	blocks.set_collision_radius(0)
	blocks.configure_streaming(true, 64, 16, 4 * 1024 * 1024, 4 * 1024 * 1024)
	blocks.set_distant_rendering_enabled(true)
	preload("res://addons/structures/material_startup.gd").prepare(blocks)
	var empty: PackedByteArray = blocks.capture_snapshot()
	var origins := [Vector3i.ZERO, Vector3i(768, 0, 0), Vector3i(1600, 0, 0), Vector3i(-1024, 0, 0)]
	var names := ["cottage_thin_roof_a2", "village_shop_hipped_r1", "village_shop_thin_roof_b2", "large_house_c1"]
	for house in origins.size():
		var prefab: Resource = load("res://addons/structures/prefabs/" + names[house] + ".tres")
		var records: PackedInt32Array = prefab.get_records()
		for index in range(0, records.size(), 4):
			records[index] += origins[house].x
			records[index + 1] += origins[house].y
			records[index + 2] += origins[house].z
		check(blocks.set_cells(records), "author original " + names[house])
	var authored: PackedByteArray = blocks.capture_snapshot()
	check(await settle(), "all distant regions finish without visiting them")
	check(blocks.capture_snapshot() == authored, "horizon does not modify authoritative blocks")
	var initial: Dictionary = blocks.distant_rendering_stats()
	check(initial.visible_chunks > 0 and initial.mesh_chunks > blocks.stats().mesh_chunks, "far buildings survive the 64 m near-render cutoff")
	var overlap := false
	for near in blocks.get_children():
		if near is MeshInstance3D:
			for distant in blocks.get_node("DistantBuildings").get_children():
				if distant.position == near.position and distant.visible: overlap = true
	check(not overlap, "near and far meshes never double-draw the same chunk")
	rows.append({"stage": "resident", "horizon": initial, "near": blocks.streaming_stats()})
	if images: await capture()
	focus = Vector3(100000, 0, 100000)
	blocks.set_focus(focus)
	blocks.flush_bakes()
	check(blocks.stats().mesh_chunks == 0 and blocks.distant_rendering_stats().visible_chunks == initial.mesh_chunks, "all building representations remain after arbitrarily distant travel")
	var jobs: int = blocks.distant_rendering_stats().published_chunks
	for trip in 8:
		blocks.set_focus(Vector3.ZERO); blocks.flush_bakes()
		blocks.set_focus(focus); blocks.flush_bakes()
	check(blocks.distant_rendering_stats().published_chunks == jobs, "eight near/far handoffs reuse horizon geometry without baking")
	blocks.configure_history(1024 * 1024, 8)
	var cell := Vector3i(1900, 1, 0)
	check(blocks.set_cells(PackedInt32Array([cell.x, cell.y, cell.z, 1])), "author distant isolated cell")
	check(await settle(), "distant addition rebuilds derived geometry")
	var before := fingerprint()
	check(blocks.set_cells(PackedInt32Array([cell.x, cell.y, cell.z, 0])), "remove distant isolated cell")
	check(await settle() and before != fingerprint(), "removed cells disappear from distant geometry")
	check(blocks.undo(AABB()) and await settle(), "undo restores distant geometry")
	check(blocks.get_cell(cell) == 1, "undo preserves the original cell")
	blocks.set_cells(PackedInt32Array([cell.x, cell.y, cell.z, 0]))
	blocks.clear_history()
	check(await settle(), "deleted addition leaves no stale mesh")
	var codec: RefCounted = ClassDB.instantiate("NativeStructuresSnapshot")
	codec.configure_assets(PackedStringArray())
	var archive: RefCounted = ClassDB.instantiate("NativeRegionWorldArchive")
	archive.configure(ClassDB.instantiate("NativeWorldArchive"), codec, true)
	var path := ProjectSettings.globalize_path(output.path_join("fixture_%d.trw" % Time.get_ticks_usec()))
	check(archive.acquire(path), "isolated archive opens")
	check(archive.publish(path, archive.encode({"terrain": PackedByteArray([1]), "structures": codec.encode(blocks.capture_snapshot(), {})})) == OK, "save approved building cells")
	var state: Dictionary = codec.decode_storage(archive.decode(archive.read(path)).sections.structures)
	checkpoint = state.checkpoint
	check(blocks.restore_storage_state(state.resident, state.unavailable_keys, state.unavailable_checksums), "metadata-only reload restores unavailable-region index")
	pager = ClassDB.instantiate("NativeBlockPager")
	check(pager.configure(blocks, archive, 64, 128, 64), "native paging attaches archive to distant renderer")
	var storage: Dictionary = blocks.capture_storage_state()
	check(await settle(), "never-visited archived regions all receive horizon meshes")
	check(blocks.stats().chunks == 0 and blocks.stats().collision_chunks == 0, "distant archive rendering loads no editable chunks or physics")
	check(blocks.capture_storage_state() == storage, "archive horizon leaves saved cells and residency unchanged")
	check(blocks.distant_rendering_stats().mesh_chunks == initial.mesh_chunks, "metadata-only reload represents the same building chunks")
	rows.append({"stage": "archive_only", "horizon": blocks.distant_rendering_stats(), "paging": pager.stats()})
	focus = Vector3(770, 4, 0)
	blocks.set_focus(focus)
	check(await settle(), "approach archived building loads near detail without losing horizon")
	for frame in 120:
		pager.step(focus, checkpoint)
		await process_frame
	check(await settle() and blocks.is_region_loaded(Vector3i(12, 0, 0)), "normal pager still admits nearby authoritative blocks")
	check(blocks.distant_rendering_stats().mesh_bytes <= blocks.distant_rendering_stats().byte_limit and blocks.distant_rendering_stats().budget_rejections == 0, "far representation stays within its explicit memory ceiling")
	pager.stop(); pager = null
	blocks.restore_snapshot(authored)
	await process_frame
	blocks.restore_snapshot(empty)
	check(await settle() and blocks.distant_rendering_stats().mesh_chunks == 0, "world replacement rejects in-flight old-world geometry")
	blocks.restore_snapshot(authored)
	check(await settle(), "original world rebuilds after replacement")
	blocks.set_distant_rendering_enabled(false)
	check(blocks.distant_rendering_stats().mesh_chunks == 0, "disable releases all distant visuals")
	blocks.set_distant_rendering_enabled(true)
	check(await settle(), "reenable rebuilds all regions")
	blocks.restore_snapshot(authored)
	await process_frame
	blocks.free()
	archive.release()
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "rows": rows}, "  "))
	print("BUILDING_HORIZON checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

func capture() -> void:
	root.size = Vector2i(1920, 1080)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("788f9c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .6
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43, -27, 0)
	root.add_child(sun)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.far = 6000
	camera.fov = 12
	camera.current = true
	for distance in [450, 1200, 3000]:
		camera.position = Vector3(800, distance * .12, -distance)
		camera.look_at(Vector3(780, 4, 0))
		for enabled in [false, true]:
			blocks.get_node("DistantBuildings").visible = enabled
			for frame in 12: await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("distance_%d_%s.png" % [distance, "horizon" if enabled else "old_cutoff"]))
	blocks.get_node("DistantBuildings").visible = true
	camera.free(); sun.free(); environment.free()

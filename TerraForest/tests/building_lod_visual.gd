extends SceneTree

const Structures = preload("res://addons/structures/structures_world.gd")
var failures := 0
var checks := 0
var output := "res://reports/building_lod_visual"
var rows: Array = []
var blocks: Node3D
var camera: Camera3D

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func settle() -> void:
	for frame in 40: await RenderingServer.frame_post_draw

func primitives() -> int:
	return RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lod-output="): output = argument.trim_prefix("--lod-output=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920, 1080)
	root.mesh_lod_threshold = 1.0
	Engine.max_fps = 60
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("788f9c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .55
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43, -27, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400
	root.add_child(sun)
	var structures := Structures.new()
	root.add_child(structures)
	check(structures.prepare(), "native structures ready")
	preload("res://addons/structures/furniture_catalog.gd").register(structures)
	preload("res://addons/structures/storage_catalog.gd").register(structures)
	preload("res://addons/structures/door_catalog.gd").register(structures)
	preload("res://addons/structures/window_catalog.gd").register(structures)
	blocks = structures.blocks
	blocks.set_collision_radius(0)
	blocks.set_process(false)
	var transaction: RefCounted = ClassDB.instantiate("NativePrefabPlacement")
	var names := ["cottage_thin_roof_a2", "village_shop_hipped_r1", "village_shop_thin_roof_b2", "large_house_c1"]
	var authored := true
	for row in 6:
		for column in 4:
			var asset: Resource = load("res://addons/structures/prefabs/" + names[column] + ".tres")
			var result: Dictionary = transaction.place(blocks, asset, Vector3i(column * 32 - 48, 0, row * 32), 0, structures.model_collections(), [])
			authored = authored and result.get("ok", false)
	check(authored, "24 approved houses with original attached windows and doors")
	blocks.flush_bakes()
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1000, 1000)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("59684a")
	plane.material = material
	ground.mesh = plane
	ground.position = Vector3(0, -5, 40)
	root.add_child(ground)
	camera = Camera3D.new()
	camera.far = 1500
	root.add_child(camera)
	camera.current = true
	var snapshot: PackedByteArray = blocks.capture_snapshot()
	var jobs: int = blocks.stats().worker_jobs_submitted
	var stats: Dictionary = blocks.geometry_lod_stats()
	check(stats.chunks_with_lods > 0 and stats.lowest_triangles < stats.base_triangles * .9, "dense district has useful conservative geometry levels")
	var views := [[Vector3(7, 6, -22), Vector3(4, 5, 5)], [Vector3(115, 64, -120), Vector3(0, 8, 55)], [Vector3(205, 104, -300), Vector3(0, 8, 55)]]
	for index in views.size():
		camera.position = views[index][0]
		camera.look_at(views[index][1])
		structures.set_model_focus(camera.position)
		var counts := []
		for enabled in [false, true]:
			blocks.set_geometry_lod_enabled(enabled)
			await settle()
			counts.append(primitives())
			root.get_texture().get_image().save_png(output.path_join("view_%d_%s.png" % [index, "lod" if enabled else "full"]))
		rows.append({"view": index, "position": camera.position, "full_triangles": counts[0], "lod_triangles": counts[1]})
		check(counts[1] <= counts[0], "view %d never adds drawn geometry" % index)
	check(rows[-1].lod_triangles < rows[-1].full_triangles * .92, "actual distant renderer uses reduced index buffers")
	var sweeps := []
	for enabled in [false, true]:
		blocks.set_geometry_lod_enabled(enabled)
		var intervals: Array[float] = []
		var draw_counts := []
		var previous := Time.get_ticks_usec()
		for frame in 180:
			var fraction := float(frame) / 179
			camera.position = Vector3(115, 50, -300).lerp(Vector3(6, 5, -18), fraction)
			camera.look_at(Vector3(0, 5, 30))
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			intervals.append((now - previous) / 1000.0)
			previous = now
			draw_counts.append(primitives())
		intervals.sort()
		sweeps.append({"enabled": enabled, "median_ms": intervals[90], "p95_ms": intervals[171], "max_ms": intervals[-1], "triangles": draw_counts})
	for frame in range(0, 180, 15):
		camera.position = Vector3(115, 50, -300).lerp(Vector3(6, 5, -18), float(frame) / 179)
		camera.look_at(Vector3(0, 5, 30))
		for enabled in [false, true]:
			blocks.set_geometry_lod_enabled(enabled)
			for draw in 5: await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("sweep_%03d_%s.png" % [frame, "lod" if enabled else "full"]))
	check(blocks.capture_snapshot() == snapshot and blocks.stats().worker_jobs_submitted == jobs, "camera and LOD changes never mutate cells or submit bakes")
	structures.free()
	blocks = ClassDB.instantiate("NativeBlockWorld")
	root.add_child(blocks)
	preload("res://addons/structures/material_startup.gd").prepare(blocks)
	blocks.set_collision_radius(0)
	var cells := PackedInt32Array()
	for shape in range(1, 19):
		for orientation in 4:
			cells.append_array(PackedInt32Array([shape * 3, 0, orientation * 3, blocks.encode_block(shape, orientation, orientation)]))
	blocks.set_cells(cells)
	blocks.flush_bakes()
	var gallery := []
	for distance in [30, 180]:
		camera.position = Vector3(28, distance * .3, -distance)
		camera.look_at(Vector3(28, .5, 6))
		var counts := []
		for enabled in [false, true]:
			blocks.set_geometry_lod_enabled(enabled)
			await settle()
			counts.append(primitives())
			root.get_texture().get_image().save_png(output.path_join("shapes_%d_%s.png" % [distance, "lod" if enabled else "full"]))
		gallery.append({"distance": distance, "full_triangles": counts[0], "lod_triangles": counts[1]})
		check(counts[1] <= counts[0], "all-shape gallery never adds drawn geometry")
	var result := {"checks": checks, "failures": failures, "views": rows, "lod": stats, "sweeps": sweeps, "scope": "24 approved houses including attached models, 1080p 100% scale, 180-frame approach per mode, offscreen nonactivating window. Capped wall intervals are not isolated GPU speedup or full-world performance."}
	result["shape_gallery"] = gallery
	result["shape_lods"] = blocks.geometry_lod_stats()
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	blocks.free()
	ground.free()
	camera.free()
	sun.free()
	environment.free()
	await process_frame
	print("BUILDING_LOD_VISUAL checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

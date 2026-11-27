# SPDX-License-Identifier: 0BSD
extends SceneTree
# Matched camera/time replays. Readback is excluded from the GPU-cost sample.
const Asset = preload("res://addons/world_ecosystem/woodland_mesh.gd")
const BEFORE = "res://tests/fixtures/woodland_pre_stability.gdshader"
const AFTER = "res://addons/world_ecosystem/woodland.gdshader"
var output := ""
var failures := 0
var checks := 0
var captured_bytes := 0
var still_bytes := 0
var world: Node3D
var camera: Camera3D
var materials: Array[ShaderMaterial] = []
var base_eye := Vector3(0, 1.8, 8)
var ground_y := 0.0
var samples: Dictionary = {}
var sample_roots: Array[Vector3] = []
var motion_crop := Rect2i(200, 500, 320, 96)
var game: Node
var results: Dictionary = {}
var diagnose_wind := false

func _initialize() -> void: run.call_deferred()
func retains_runtime_far_filter() -> bool: return false
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
	return ok
func wait_for(predicate: Callable, seconds: int) -> bool:
	var deadline := Time.get_ticks_msec() + seconds * 1000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	return predicate.call()
func settle(count: int = 12) -> void:
	for frame in count: await RenderingServer.frame_post_draw
func comparison_shader(path: String) -> Shader:
	var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string(path).replace("void vertex()", "uniform float comparison_time = 0.0;\nvoid vertex()").replace("TIME", "comparison_time")
	if diagnose_wind and path == AFTER:
		# Test-only isolation: preserve lighting/geometry, freeze only wind offsets.
		shader.code = shader.code.replace("* wind_strength", "* 0.0")
	return shader
func apply_shader(shader: Shader) -> void:
	for material in materials:
		material.shader = shader
		material.set_shader_parameter("comparison_time", 0.0)
		material.set_shader_parameter("cover_clock", 1000000.0)
		material.set_shader_parameter("cover_projection_scale", 1.0)
func pose(frame: int) -> void:
	# Continuous 1.2 m/s lateral + 0.6 m/s forward camera motion at 60 Hz.
	camera.global_position = base_eye + Vector3(frame * 0.02 - 1.2, 0, -frame * 0.01)
	camera.look_at(camera.global_position + Vector3(0, -0.8, -60))
	for material in materials:
		material.set_shader_parameter("cover_eye", camera.global_position)
		material.set_shader_parameter("comparison_time", frame / 60.0)
func luma_at(image: Image, point: Vector2) -> float:
	var x := clampi(floori(point.x), 0, image.get_width() - 2)
	var y := clampi(floori(point.y), 0, image.get_height() - 2)
	var color := image.get_pixel(x, y).lerp(image.get_pixel(x + 1, y), point.x - x).lerp(image.get_pixel(x, y + 1).lerp(image.get_pixel(x + 1, y + 1), point.x - x), point.y - y)
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
func prepare_samples() -> void:
	samples = {"near": [], "middle": [], "far": []}
	pose(0)
	# Track actual foliage positions: a flat-ground homography misclassifies
	# hillside foreground as distant vegetation. Fixed anchors include wind and
	# coverage changes around leaves, without sampling unrelated flat terrain.
	for root_point: Vector3 in sample_roots:
		var distance := root_point.distance_to(camera.global_position)
		var band := "near" if distance < 28.0 else ("middle" if distance < 80.0 else "far")
		if distance < 8.0 or distance > 120.0 or samples[band].size() >= 320: continue
		for offset in [Vector3(0, 0.12, 0), Vector3(0.06, 0.22, 0), Vector3(-0.06, 0.22, 0)]:
			var point: Vector3 = root_point + offset
			if camera.is_position_behind(point): continue
			var pixel := camera.unproject_position(point)
			if pixel.x < 40 or pixel.x > 1880 or pixel.y < 220 or pixel.y > 820: continue
			if samples[band].size() < 320: samples[band].append(point)
	for band: String in samples: check(samples[band].size() >= 24, band + " moving samples available")
	var tiles: Dictionary = {}
	for point: Vector3 in samples.far:
		var pixel := camera.unproject_position(point)
		var tile := Vector2i(int(pixel.x) / 320, int(pixel.y) / 96)
		tiles[tile] = int(tiles.get(tile, 0)) + 1
	var best := 0
	for tile: Vector2i in tiles:
		if tiles[tile] > best:
			best = tiles[tile]
			motion_crop = Rect2i(clampi(tile.x * 320, 0, 1600), clampi(tile.y * 96 - 12, 0, 984), 320, 96)
func save_still(image: Image, name: String) -> void:
	# Context stills are JPEG; motion crops and all measurements stay lossless.
	var data := image.save_jpg_to_buffer(0.94)
	still_bytes += data.size()
	if not check(still_bytes <= 3 * 1024 * 1024, "stills within admitted 3 MiB"):
		quit(1)
		return
	FileAccess.open(output.path_join(name + ".jpg"), FileAccess.WRITE).store_buffer(data)
func replay(shader: Shader, name: String, capture: bool) -> Dictionary:
	apply_shader(shader)
	pose(0)
	await settle(24)
	var previous: Dictionary = {}
	var differences := {"near": 0.0, "middle": 0.0, "far": 0.0}
	var counts := {"near": 0, "middle": 0, "far": 0}
	var frames: Array[PackedByteArray] = []
	for frame in 120:
		pose(frame)
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		for band: String in samples:
			var current := PackedFloat32Array()
			for point: Vector3 in samples[band]: current.append(luma_at(image, camera.unproject_position(point)))
			if previous.has(band):
				for index in current.size():
					differences[band] += absf(current[index] - previous[band][index])
					counts[band] += 1
			previous[band] = current
		if capture and frame % 4 == 0:
			var data := image.get_region(motion_crop).save_webp_to_buffer()
			captured_bytes += data.size() + 4
			if captured_bytes > 5 * 1024 * 1024:
				check(false, "motion frames exceed admitted 5 MiB")
				results.merge({"checks": checks, "failures": failures, "error": "motion capture ceiling"}, true)
				FileAccess.open(output.path_join("vegetation_stability.json"), FileAccess.WRITE).store_string(JSON.stringify(results, "  "))
				quit(1)
				return {}
			frames.append(data)
		if capture and frame == 60: save_still(image, name)
	if capture:
		var file := FileAccess.open(output.path_join(name + ".frames"), FileAccess.WRITE)
		file.store_32(frames.size())
		for data: PackedByteArray in frames:
			file.store_32(data.size())
			file.store_buffer(data)
	var result := {"name": name, "samples": counts}
	for band: String in differences: result[band] = differences[band] / maxf(1.0, counts[band])
	return result
func paired_cost(before: Shader, after: Shader) -> Dictionary:
	# Short ABBA windows keep each conservative comparison close in time.
	# Warm both programs first; previous long windows showed clock/load drift.
	for shader in [before, after]:
		apply_shader(shader); pose(60); await settle(120)
	var groups: Array = []
	var worst_delta := -INF
	var raw: Array[Dictionary] = []
	for cycle in 8:
		var group: Array[Dictionary] = []
		for shader in [before, after, after, before]:
			apply_shader(shader); pose(cycle * 12); await settle(4)
			var gpu: Array[float] = []
			var cpu: Array[float] = []
			var intervals: Array[float] = []
			var previous := Time.get_ticks_usec()
			for frame in 24:
				pose(cycle * 12 + frame)
				await RenderingServer.frame_post_draw
				var now := Time.get_ticks_usec(); intervals.append((now - previous) / 1000.0); previous = now
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
				cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
			gpu.sort(); cpu.sort(); intervals.sort()
			group.append({"gpu_p95_ms": gpu[22], "gpu_p50_ms": gpu[12], "cpu_p95_ms": cpu[22], "frame_p95_ms": intervals[22], "draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)})
		var delta := maxf(group[1].gpu_p95_ms, group[2].gpu_p95_ms) - minf(group[0].gpu_p95_ms, group[3].gpu_p95_ms)
		worst_delta = maxf(worst_delta, delta)
		groups.append({"abba": group, "gpu_p95_increment_ms": delta})
		raw.append_array(group)
	return {"groups": groups, "worst_gpu_p95_increment_ms": worst_delta, "raw": raw}
func compare(label: String) -> void:
	var before := comparison_shader(BEFORE)
	var after := comparison_shader(AFTER)
	prepare_samples()
	var rows: Array[Dictionary] = []
	# ABBA: identical poses/times, no frame readbacks in the cost samples.
	var cost_result: Dictionary = {"raw": [], "groups": [], "worst_gpu_p95_increment_ms": 0.0}
	if not diagnose_wind: cost_result = await paired_cost(before, after)
	results[label] = {"cost_interleaved": cost_result}
	rows.append(await replay(before, label + "_before", true))
	rows.append(await replay(after, label + "_after", true))
	rows.append(await replay(after, label + "_after_repeat", false))
	rows.append(await replay(before, label + "_before_repeat", false))
	var baseline := minf(rows[0].far, rows[3].far)
	var candidate := maxf(rows[1].far, rows[2].far)
	var noise_pass := false
	if not diagnose_wind: noise_pass = check(candidate <= baseline * 0.85, label + " far temporal residual improves at least 15% in both repeats")
	var gpu_delta: float = cost_result.worst_gpu_p95_increment_ms
	var cost_pass := false
	if not diagnose_wind: cost_pass = check(gpu_delta <= 0.3, label + " conservative GPU p95 increment <=0.3 ms")
	if label == "synthetic" and not diagnose_wind:
		var same_draws := true
		for group: Dictionary in cost_result.groups:
			for row: Dictionary in group.abba: same_draws = same_draws and row.draw_calls == group.abba[0].draw_calls
		check(same_draws, label + " no additional draw calls")
	results[label] = {"motion": rows, "crop": str(motion_crop), "sample_method": "fixed anchors around actual grass roots; true 3D distance bands", "cost_interleaved": cost_result, "far_residual_ratio": candidate / maxf(baseline, 0.000001), "worst_gpu_p95_increment_ms": gpu_delta, "noise_pass": noise_pass, "cost_pass": cost_pass}
	if diagnose_wind:
		results[label].merge({"diagnostic_only": true, "cost_interleaved": null, "worst_gpu_p95_increment_ms": null, "noise_pass": null, "cost_pass": null}, true)
	FileAccess.open(output.path_join("vegetation_stability.json"), FileAccess.WRITE).store_string(JSON.stringify(results, "  "))
func synthetic() -> void:
	world = Node3D.new(); root.add_child(world)
	camera = Camera3D.new(); world.add_child(camera); camera.current = true; camera.fov = 75
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color("859166")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color = Color("b8c3ce"); environment.environment.ambient_light_energy = 0.55
	world.add_child(environment)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-52, -27, 0); sun.light_energy = 1.3; world.add_child(sun)
	var ground := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(140, 200); ground.mesh = plane; ground.position = Vector3(0, -0.02, -60)
	var tint := StandardMaterial3D.new(); tint.albedo_color = Color("859166"); tint.roughness = 1; ground.material_override = tint; world.add_child(ground)
	var views: Array[MultiMeshInstance3D] = []
	var snapshots: Array[PackedByteArray] = []
	for species in [1, 2, 3, 6, 7, 8]:
		var mesh := Asset.build(species)
		var material: ShaderMaterial = mesh.surface_get_material(0); materials.append(material)
		material.set_shader_parameter("distance_fade_start", 100.0); material.set_shader_parameter("distance_fade_end", 124.0)
		for row in 8:
			for column in 8:
				var batch := MultiMesh.new(); batch.transform_format = MultiMesh.TRANSFORM_3D; batch.mesh = mesh; batch.instance_count = 144 if species == 2 else 4
				for index in batch.instance_count:
					var phase: float = index * 2.399963 + row * 7.3 + column * 3.7 + species
					var point := Vector3(column * 12 - 48 + fmod(index * 3.713, 12), 0, -row * 12 + fmod(index * 7.717, 12))
					batch.set_instance_transform(index, Transform3D(Basis(Vector3.UP, phase), point))
					if species == 2: sample_roots.append(point)
				var view := MultiMeshInstance3D.new(); view.multimesh = batch; view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; world.add_child(view); views.append(view)
				if views.size() == 1: snapshots.append(batch.buffer.to_byte_array())
	# Near-only scene proves exact pixels, including deterministic wind.
	for view in views: view.visible = false
	var close := MeshInstance3D.new(); close.mesh = Asset.build(2); world.add_child(close)
	var close_material: ShaderMaterial = close.mesh.surface_get_material(0)
	camera.position = Vector3(0.8, 0.6, 1.4); camera.look_at(Vector3(0, 0.2, 0)); close_material.set_shader_parameter("cover_eye", camera.position)
	var near_images: Array[PackedByteArray] = []
	for path in [BEFORE, AFTER]:
		# Near preservation still compares restored production, not the diagnostic override.
		var diagnostic := diagnose_wind; diagnose_wind = false
		close_material.shader = comparison_shader(path); diagnose_wind = diagnostic
		close_material.set_shader_parameter("comparison_time", 0.37); await settle()
		near_images.append(root.get_texture().get_image().get_data())
	check(near_images[0] == near_images[1], "near grass pixels including wind are byte-identical")
	close.free()
	for view in views: view.visible = true
	await compare("synthetic")
	check(views[0].multimesh.buffer.to_byte_array() == snapshots[0], "synthetic native instance buffer unchanged")
	world.free(); materials.clear(); sample_roots.clear(); await process_frame
func actual_world(slot: String) -> void:
	var path := "user://worlds/" + slot + ".trw"
	if not check(slot.is_valid_identifier() and FileAccess.file_exists(path), "existing world selected read-only"): return
	var original := FileAccess.get_sha256(path)
	ProjectSettings.set_setting("terraforest/offscreen_session", true)
	preload("res://addons/world_runtime/session_options.gd").set_arguments(PackedStringArray(["--world-slot=" + slot, "--snapshot-readonly", "--temporary", "--no-derived-cache", "--ground-cover", "--gameplay-construction"]), true)
	game = load("res://demo/world.tscn").instantiate(); game.temporary_world = true; game.background_fps = 60; game.max_fps = 60; root.add_child(game)
	if not check(await wait_for(func(): return not game.loading_active, 90), "read-only populated world ready"):
		game.shutdown_requested = true; await game.terrain.shutdown_after_edits(); game.free(); return
	game.set_process(false); game.set_physics_process(false); game._clear_motion()
	var cover: Node = game.ground_cover
	check(await wait_for(func(): return cover.resident.size() == cover._wanted.size() and cover._dirty.is_empty() and cover._requests.is_empty() and cover._scatter_job.is_empty() and cover._support_job.is_empty(), 45), "actual cover population settles")
	var center: Vector3 = game.player.global_position
	var best := INF
	for owner: Variant in cover.resident:
		var row: Dictionary = cover.resident[owner][2]
		var transforms: PackedFloat32Array = row.transforms
		for index in row.ids.size():
			var point := Vector3(transforms[index * 12 + 3], transforms[index * 12 + 7], transforms[index * 12 + 11])
			sample_roots.append(point)
			var distance := point.distance_to(game.player.global_position)
			if distance > 8.0 and distance < best: best = distance; center = point
	check(best < 64.0, "nearby natural grass field found")
	cover.set_process(false)
	check(await wait_for(func():
		for batch: Node in cover.batches:
			var stats: Dictionary = batch.render_stats()
			if stats.pending_batches != 0 or stats.selection_pending: return false
		return true, 20), "actual vegetation render pages settle")
	# Freeze publication/actors for a rendering comparison, while the external
	# driver moves the real camera and advances deterministic foliage wind.
	game.process_mode = Node.PROCESS_MODE_DISABLED
	# Historical wind/shading controls require their original opaque mesh. A live
	# far material would otherwise keep TIME-based wind outside their paired shader.
	# The new reconstruction driver overrides this hook to inspect normal startup.
	if not retains_runtime_far_filter():
		var grass: ArrayMesh = cover.preview_meshes[2]
		if grass.get_surface_count()>1:
			var legacy := preload("res://tests/fixtures/grass_filtered.gd")
			legacy.restore(grass,legacy.capture(grass))
	for material: ShaderMaterial in cover.foliage_materials:
		if material.shader.code.contains("distant_self_shade"): materials.append(material)
	camera = game.camera; camera.fov = 75; ground_y = center.y; base_eye = center + Vector3(0, 1.8, 0)
	var state: PackedByteArray = cover.removed.capture_storage_snapshot()
	var population := 0
	var page_counts: Array[Dictionary] = []
	for batch: Node in cover.batches:
		population += batch.get_ids().size()
		var stats: Dictionary = batch.render_stats()
		page_counts.append({"pages": stats.resident_batches, "shadows": stats.shadow_batches, "bytes": stats.resident_transform_bytes})
	await compare("world")
	var after_population := 0
	var after_pages: Array[Dictionary] = []
	for batch: Node in cover.batches:
		after_population += batch.get_ids().size()
		var stats: Dictionary = batch.render_stats()
		after_pages.append({"pages": stats.resident_batches, "shadows": stats.shadow_batches, "bytes": stats.resident_transform_bytes})
	check(page_counts == after_pages, "actual vegetation draw pages, shadow pages and transform bytes unchanged")
	check(state == cover.removed.capture_storage_snapshot() and after_population == population, "actual world removals, authored cover and population unchanged")
	check(FileAccess.get_sha256(path) == original, "canonical player save hash unchanged")
	results["world_input"] = {"slot": slot, "sha256": original, "camera_origin": str(base_eye), "population": population, "materials": materials.size(), "pages_before": page_counts, "pages_after": after_pages}
	game.process_mode = Node.PROCESS_MODE_INHERIT
	game.shutdown_requested = true; await game.terrain.shutdown_after_edits(); game.free(); materials.clear(); await process_frame
func run() -> void:
	var slot := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--check-evidence-dir="): output = argument.trim_prefix("--check-evidence-dir=")
		if argument.begins_with("--stability-source-slot="): slot = argument.trim_prefix("--stability-source-slot=")
		if argument == "--diagnose-wind": diagnose_wind = true
	if output.is_empty(): push_error("Use the admitted check runner"); quit(1); return
	Engine.max_fps = 60
	for resource_path in [BEFORE, AFTER]:
		results[resource_path.get_file()] = FileAccess.get_sha256(resource_path)
	results["diagnose_wind"] = diagnose_wind
	FileAccess.open(output.path_join("trial_shader.gdshader"), FileAccess.WRITE).store_string(FileAccess.get_file_as_string(AFTER))
	FileAccess.open(output.path_join("driver.gd"), FileAccess.WRITE).store_string(FileAccess.get_file_as_string("res://tests/vegetation_stability.gd"))
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	await synthetic()
	if not slot.is_empty(): await actual_world(slot)
	results.merge({"checks": checks, "failures": failures, "captured_frame_bytes": captured_bytes, "still_bytes": still_bytes, "scope": "Continuous deterministic camera/time replays, true-distance foliage-registered display-luma residual. Includes wind and coverage changes; not pure geometric aliasing, physical driving, thermal or universal visual acceptance."})
	if diagnose_wind:
		results["scope"] = "Diagnostic only: unchanged lighting/geometry, normal wind versus frozen wind while moving the camera. Projection anchors may be occluded. Cost/visual acceptance gates are not evaluated; passing assertions only verify the fixture and preserved source/save. Runtime uses neither the rejected brightening nor this frozen-wind override."
	FileAccess.open(output.path_join("vegetation_stability.json"), FileAccess.WRITE).store_string(JSON.stringify(results, "  "))
	# Let Godot assign resource identities for the new original test resources.
	for resource_path in ["res://tests/vegetation_stability.gd", BEFORE]:
		if not FileAccess.file_exists(resource_path + ".uid"):
			FileAccess.open(resource_path + ".uid", FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id()) + "\n")
	print("VEGETATION_STABILITY failures=", failures)
	quit(1 if failures else 0)

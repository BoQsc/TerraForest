extends SceneTree

var game: Node3D
var output := "res://reports/building_horizon_world"
var slot := "recipe_generated_4644d8cfc8f97e43"
var checks := 0
var failures := 0
var save_path := ""
var save_hash := ""

func _initialize() -> void:
	ProjectSettings.set_setting("terraforest/offscreen_session", true)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func run() -> void:
	var cache := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--horizon-output="): output = argument.trim_prefix("--horizon-output=")
		if argument.begins_with("--horizon-slot="): slot = argument.trim_prefix("--horizon-slot=")
		if argument.begins_with("--derived-cache="): cache = argument
	DirAccess.make_dir_recursive_absolute(output)
	save_path = "user://worlds/" + slot + ".trw"
	if not FileAccess.file_exists(save_path):
		push_error("Read-only world fixture is missing: " + save_path)
		quit(1); return
	save_hash = FileAccess.get_sha256(save_path)
	var arguments := PackedStringArray(["--world-slot=" + slot, "--snapshot-readonly", "--gameplay-construction", "--ground-cover", "--actors", "--vehicle-fleet", "--temporary"])
	if not cache.is_empty(): arguments.append(cache)
	preload("res://addons/world_runtime/session_options.gd").set_arguments(arguments, true)
	game = load("res://demo/world.tscn").instantiate()
	game.temporary_world = true
	game.background_fps = 60
	root.add_child(game)
	var started := Time.get_ticks_msec()
	var deadline := started + 150000
	while game.loading_active and Time.get_ticks_msec() < deadline and game.terrain.latest_error.is_empty():
		game.app_focused = true
		await process_frame
	check(not game.loading_active and game.terrain.latest_error.is_empty(), "actual populated save loads with complete distant building coverage")
	if failures:
		print("HORIZON_LOADING ", game.loading_work_text, " ", game.terrain.latest_error, " ", game.structures.blocks.distant_rendering_stats())
		await finish({}); return
	var loading_ms := Time.get_ticks_msec() - started
	var groups := {}
	for child in game.structures.blocks.get_node("DistantBuildings").get_children():
		var region := Vector3i(floori(child.position.x / 64), floori(child.position.y / 64), floori(child.position.z / 64))
		groups[region] = int(groups.get(region, 0)) + 1
	var selected := Vector3i.ZERO
	for region in groups:
		if groups[region] > int(groups.get(selected, 0)): selected = region
	var target := Vector3(selected) * 64 + Vector3(32, 8, 32)
	var view := target + Vector3(-500 if target.x > 1024 else 500, 120, 100)
	game.fly = true
	game.teleport(view, view.y)
	deadline = Time.get_ticks_msec() + 90000
	while game.loading_active and Time.get_ticks_msec() < deadline:
		game.app_focused = true
		await process_frame
	check(not game.loading_active, "camera arrival finishes normal terrain streaming")
	for frame in 120: await process_frame
	game.set_physics_process(false)
	game._clear_motion()
	var blocks: Node3D = game.structures.blocks
	var snapshot: Dictionary = blocks.capture_storage_state()
	var jobs: int = blocks.distant_rendering_stats().published_chunks
	game.camera.global_position = view
	game.camera.look_at(target)
	var counts := []
	for enabled in [false, true]:
		blocks.get_node("DistantBuildings").visible = enabled
		for frame in 40:
			game.app_focused = true
			await RenderingServer.frame_post_draw
		counts.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		root.get_texture().get_image().save_png(output.path_join("world_" + ("horizon" if enabled else "old_cutoff") + ".png"))
	check(blocks.distant_rendering_stats().ready and blocks.distant_rendering_stats().visible_chunks > 0, "far block geometry remains present in the actual world")
	check(counts[1] > counts[0], "renderer draws additional real distant building geometry")
	check(snapshot == blocks.capture_storage_state(), "comparison does not change authoring or residency")
	check(blocks.distant_rendering_stats().published_chunks == jobs, "fixed-camera comparison submits no horizon rebakes")
	var viewport := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	var samples := []
	for enabled in [false, true]:
		blocks.get_node("DistantBuildings").visible = enabled
		for frame in 20: await RenderingServer.frame_post_draw
		var elapsed: Array[float] = []
		var gpu: Array[float] = []
		var previous := Time.get_ticks_usec()
		for frame in 120:
			game.app_focused = true
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			elapsed.append((now - previous) / 1000.0)
			previous = now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
		elapsed.sort(); gpu.sort()
		samples.append({"enabled": enabled, "frame_p95_ms": elapsed[114], "gpu_p95_ms": gpu[114], "frame_max_ms": elapsed[-1]})
	blocks.get_node("DistantBuildings").visible = true
	var horizon: Dictionary = blocks.distant_rendering_stats()
	check(horizon.budget_rejections == 0 and horizon.failed_reads == 0 and horizon.mesh_bytes <= horizon.byte_limit, "world-wide representation fits its resource ceiling without failed reads")
	await finish({"slot": slot, "loading_ms": loading_ms, "horizon": horizon, "near": blocks.streaming_stats(), "region": blocks.region_stats(), "draw_primitives": counts, "samples": samples, "camera_far": game.camera.far, "camera": view, "target": target})

func finish(result: Dictionary) -> void:
	game.shutdown_requested = true
	await game.terrain.shutdown_after_edits()
	game.free()
	await process_frame
	check(FileAccess.get_sha256(save_path) == save_hash, "source save remains byte-identical")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "test never captures the mouse")
	result["checks"] = checks; result["failures"] = failures
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print("BUILDING_HORIZON_WORLD checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

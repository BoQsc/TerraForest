extends SceneTree
const Scene = preload("res://demo/world.tscn")
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Presentation = preload("res://addons/presentation/fullscreen_policy.gd")
var game: Node3D
var samples: Array[float] = []
var checks: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var failures: int = 0
var cycles: int = 4
var uncapped: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, name: String) -> void:
	checks.append({"name": name, "pass": ok})
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", name)

func wait_ready(seconds: float = 90.0) -> bool:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if not game.loading_active and game.ecosystem.resident.size() >= 100 and not game.terrain.pending_edit:
			return true
		await process_frame
	return false

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/" + name + ".png")

func snapshot(label: String) -> void:
	snapshots.append({"label": label, "memory_static": Performance.get_monitor(Performance.MEMORY_STATIC), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), "terrain_cache_bytes": game.terrain.cache_bytes, "terrain_tiles": game.terrain.tiles.size(), "vegetation": game.vegetation.statistics(), "resident": game.ecosystem.resident.size(), "pending": game.ecosystem._requests.size()})

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--cycles="):
			cycles = clampi(int(argument.get_slice("=", 1)), 1, 200)
		if argument == "--uncapped":
			uncapped = true
	DirAccess.make_dir_recursive_absolute("res://reports")
	game = Scene.instantiate()
	root.add_child(game)
	game.temporary_world = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	check(await wait_ready(), "full scene finishes collision/loading gate and vegetation streaming")
	if failures > 0:
		finish()
		return
	await create_timer(4.0).timeout
	check(Presentation.measurement(root)["fair_graphical_sample"], "measured presentation is 1920x1080 fullscreen at 100 percent render scale")
	if failures > 0:
		finish()
		return
	if uncapped:
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await capture("overview")
	snapshot("warm")
	# Fixed scene, then steady camera rotation. Report wall frame times, not simulated delta.
	var previous: int = Time.get_ticks_usec()
	for i in range(1800 if uncapped else 360):
		await process_frame
		var now: int = Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
		game.yaw += 0.0006 if uncapped else 0.003
	check(game.vegetation.renderer.roots.size() > 1000, "full scene renders over one thousand supported trees")
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(game.player.global_position + Vector3.UP * 5, game.player.global_position - Vector3.UP * 30, 1))
	check(not hit.is_empty(), "published terrain has usable collision under player")
	if not hit.is_empty():
		var point: Vector3 = hit["position"] + Vector3(8, 0, 0)
		var before: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 20, point - Vector3.UP * 20, 1))
		if not before.is_empty():
			point = before["position"]
		var old_revision: int = game.terrain.published_revision
		check(game.terrain.edit(Codec.brush(point, point, 3.0, 0, false, 1), point - Vector3.ONE * 8, point + Vector3.ONE * 8), "rendered terrain excavation accepted")
		var deadline: int = Time.get_ticks_msec() + 30000
		while game.terrain.pending_edit and Time.get_ticks_msec() < deadline:
			await process_frame
		check(game.terrain.published_revision > old_revision and not game.terrain.pending_edit, "edited meshes and collision publish in the live scene")
		await physics_frame
		await physics_frame
		var after: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 20, point - Vector3.UP * 20, 1))
		check(not after.is_empty() and (after["position"] as Vector3).y < point.y - 0.5, "published collider follows the excavated surface rather than the old ground")
	await capture("after_edit")
	for cycle in range(cycles):
		game.teleport(Vector3(600 if cycle % 2 == 0 else 800, 0, 1310))
		check(await wait_ready(), "travel cycle %d settles" % cycle)
		await create_timer(2.0).timeout
		snapshot("travel_%d" % cycle)
		check(game.ecosystem.resident.size() <= game.ecosystem.max_resident_cells and game.ecosystem._requests.size() <= 2, "travel cycle %d stays within streaming limits" % cycle)
	await capture("final_scene")
	finish()

func finish() -> void:
	samples.sort()
	var frame: Dictionary = {}
	if not samples.is_empty():
		frame = {"p50_ms": samples[int(samples.size() * 0.50)], "p95_ms": samples[int(samples.size() * 0.95)], "p99_ms": samples[int(samples.size() * 0.99)], "max_ms": samples[-1], "count": samples.size()}
	var report: Dictionary = {"engine": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "uncapped": uncapped, "checks": checks, "failures": failures, "frame_times": frame, "snapshots": snapshots, "note": "Repeat-travel integration soak; not a multi-hour endurance or baseline speedup claim."}
	report["presentation"] = Presentation.measurement(root)
	var file := FileAccess.open("res://reports/scene_soak.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	game.terrain.shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)

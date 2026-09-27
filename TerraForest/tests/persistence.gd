extends SceneTree
const Terrain = preload("res://addons/volumetric_terrain/terrain_world.gd")
var terrain
var failures: int = 0
var checks: Array[Dictionary] = []
var messages: Array[String] = []
var slot: String = "test_%d" % OS.get_process_id()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "pass": ok})
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func until(predicate: Callable) -> bool:
	var end: int = Time.get_ticks_msec() + 15000
	while not predicate.call() and Time.get_ticks_msec() < end:
		await process_frame
	return predicate.call()

func create_world() -> void:
	terrain = Terrain.new()
	terrain.save_slot = slot
	terrain.diagnostics_pause_streaming = true
	root.add_child(terrain)
	terrain.message_changed.connect(func(message: String): messages.append(message))
	check(terrain.start(StandardMaterial3D.new(), false) == OK, "persistent world starts")

func run() -> void:
	Engine.max_fps = 120
	create_world()
	check(await until(func(): return terrain.world_ready), "new persistent world ready")
	var point := Vector3(800, 50, 1310)
	# A deep sphere intersects solid terrain regardless of the local natural surface.
	check(terrain.sculpt_sphere(point, 8.0), "public sphere edit accepted")
	check(await until(func(): return not terrain.pending_edit), "persistent edit finishes")
	check(not terrain.natural_column_available(point), "edited column marked before save")
	terrain.save_world()
	check(await until(func(): return messages.any(func(m): return m.begins_with("World saved and verified"))), "canonical save verified on worker")
	var path: String = "user://worlds/" + slot + ".trw"
	check(FileAccess.get_file_as_bytes(path).size() > 32, "canonical snapshot written")
	terrain.shutdown()
	terrain.free()
	await process_frame
	create_world()
	check(await until(func(): return terrain.world_ready), "saved snapshot reloads in a new world instance")
	check(not terrain.natural_column_available(point), "persistent modification metadata prevents tree regrowth after reload")
	terrain.shutdown()
	terrain.free()
	await process_frame
	var invalid := PackedByteArray([1, 2, 3, 4])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(invalid)
	file.close()
	create_world()
	check(await until(func(): return not terrain.latest_error.is_empty()), "corrupt snapshot reports initialization failure")
	check(not terrain.world_ready, "corrupt world never becomes ready")
	terrain.shutdown()
	terrain.free()
	await process_frame
	check(FileAccess.get_file_as_bytes(path) == invalid, "shutdown does not overwrite corrupt canonical snapshot")
	for suffix in ["", ".bak", ".tmp.%d" % OS.get_process_id()]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	DirAccess.make_dir_recursive_absolute("res://reports")
	file = FileAccess.open("res://reports/persistence.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	file.close()
	quit(0 if failures == 0 else 1)

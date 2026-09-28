extends SceneTree
const Terrain = preload("res://addons/volumetric_terrain/terrain_world.gd")
const Vegetation = preload("res://addons/vegetation/vegetation_world.gd")
const Ecosystem = preload("res://addons/world_ecosystem/world_ecosystem.gd")
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Demo = preload("res://demo/world.gd")
var failures: int = 0
var checks: Array[Dictionary] = []
var terrain = Terrain.new()
var vegetation = Vegetation.new()
var ecosystem = Ecosystem.new()
var camera := Camera3D.new()
var _region_events: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "pass": ok})
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)

func until(predicate: Callable, seconds: float = 20.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return predicate.call()

func run() -> void:
	Engine.max_fps = 120
	root.add_child(terrain)
	terrain.diagnostics_pause_streaming = true
	check(not terrain.backend.configure_collision_piece_size(255) and not terrain.backend.configure_collision_piece_size(1025), "invalid collision piece sizes rejected before startup")
	check(terrain.backend.configure_collision_piece_size(256) and terrain.backend.configure_collision_piece_size(1024), "collision recipe size configurable before worker startup")
	check(terrain.start(StandardMaterial3D.new(), true) == OK, "native terrain starts")
	check(not terrain.backend.configure_collision_piece_size(512), "running terrain worker rejects collision recipe size mutation")
	check(await until(func(): return terrain.world_ready), "worker completes startup")
	var second = Terrain.new()
	check(second.start(StandardMaterial3D.new(), true) == ERR_ALREADY_IN_USE, "second scene facade rejected until cache and save ownership supports multiple worlds")
	second.free()
	var unused = Vegetation.new()
	unused.free()
	root.add_child(camera)
	camera.position = Vector3(800, 75, 1310)
	root.add_child(vegetation)
	vegetation.camera = camera
	check(vegetation.initialize() == OK, "source meshes, compact maps and all view arrays load")
	ecosystem.terrain = terrain
	ecosystem.vegetation = vegetation
	ecosystem.camera = camera
	ecosystem.stream_radius = 64.0
	ecosystem.max_resident_cells = 9
	root.add_child(ecosystem)
	var a: Dictionary = ecosystem._candidates(Vector2i(12, 20))
	var b: Dictionary = ecosystem._candidates(Vector2i(12, 20))
	check(a == b, "placement deterministic before asynchronous surface queries")
	check(await until(func(): return ecosystem.resident.size() == 9), "nine cells finish streaming")
	check(vegetation.renderer.roots.size() > 100, "vegetation placed on native terrain support")
	check(vegetation.renderer.roots.size() <= 9 * 36, "resident tree count bounded by candidate budget")
	var old_ids: Array = vegetation.renderer.roots.keys()
	camera.position.x = 300.0
	check(await until(func(): return ecosystem.resident.size() == 9 and not vegetation.renderer.roots.has(old_ids[0])), "teleport unloads old owners and replaces cells")
	await process_frame
	check(vegetation.renderer.owners.size() <= 9 and vegetation.renderer.cells.size() <= 9, "unloaded ownership and render cells reclaimed")
	check(ecosystem._requests.size() <= 2, "surface query concurrency bounded")
	check(not terrain.edit(PackedByteArray([2]), Vector3.ZERO, Vector3.ONE), "truncated edit packet rejected before decoding")
	check(not terrain.edit(Codec.command(6, [1703]), Vector3.ZERO, Vector3.ONE), "non-edit native opcodes rejected at public edit boundary")
	check(not terrain.edit(Codec.brush(Vector3.INF, Vector3.ZERO, 2, 0, false, 1), Vector3.ZERO, Vector3.ONE), "nonfinite edit coordinates rejected")
	var first: int = vegetation.renderer.roots.keys()[0]
	var point: Vector3 = vegetation.renderer.roots[first]["t"].origin
	terrain.region_changed.connect(func(_bounds: AABB, _revision: int): _region_events += 1)
	var radius: float = 3.0
	check(terrain.edit(Codec.brush(point, point, radius, 0, false, 1), point - Vector3.ONE * 8, point + Vector3.ONE * 8), "terrain excavation accepted")
	check(await until(func(): return not terrain.pending_edit), "excavation transaction commits")
	check(_region_events == 1, "exactly one region event after publication")
	check(not terrain.natural_column_available(point), "edited columns excluded from procedural regrowth")
	check(await until(func(): return not vegetation.renderer.roots.has(first)), "published excavation removes supported tree owner")
	check(ecosystem.resident.size() == 9, "edits preserve unaffected cell ownership without resampling")
	check(not vegetation.renderer.roots.has(first), "excavated root stays absent while unaffected roots remain")
	camera.position.x = 800.0
	check(await until(func(): return ecosystem.resident.size() == 9 and ecosystem._requests.is_empty() and vegetation.renderer.roots.keys().all(func(id): return vegetation.renderer.roots[id]["t"].origin.x > 600.0)), "travel away releases the edited neighborhood")
	camera.position.x = 300.0
	check(await until(func(): return ecosystem.resident.size() == 9 and ecosystem._requests.is_empty() and vegetation.renderer.roots.size() > 100 and vegetation.renderer.roots.keys().all(func(id): return vegetation.renderer.roots[id]["t"].origin.x < 500.0)), "travel back resamples the edited neighborhood")
	check(not vegetation.renderer.roots.has(first), "excavated stable ID does not regrow after unload and return")
	var root_count: int = vegetation.renderer.roots.size()
	var invalid: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3.INF)]
	check(not vegetation.upsert_chunk("invalid", PackedInt64Array([999999]), invalid) and vegetation.renderer.roots.size() == root_count, "invalid transforms rejected without mutation")
	vegetation.root_limit = root_count
	check(not vegetation.upsert_chunk("over-budget", PackedInt64Array([999999]), [Transform3D.IDENTITY]), "global root limit applies before mutation")
	for i in range(60):
		camera.position = Vector3(240 + (i % 6) * 64, 75, 1300)
		ecosystem._refresh(ecosystem._cell(camera.position))
		await process_frame
	check(ecosystem.resident.size() <= 9 and ecosystem._requests.size() <= 2, "rapid travel preserves residency and in-flight bounds")
	ecosystem.set_process(false)
	ecosystem.reset()
	vegetation.clear()
	await process_frame
	check(vegetation.renderer.roots.is_empty() and vegetation.renderer.cells.is_empty() and vegetation.renderer.owners.is_empty(), "clear releases all roots, owners and GPU cell nodes")
	check(vegetation.renderer._heap_id.is_empty(), "clear releases selector event heap")
	terrain.shutdown()
	check(not terrain.backend.thread.is_started(), "shutdown joins the persistent worker")
	check(terrain.start(StandardMaterial3D.new(), true) == ERR_UNCONFIGURED, "stopped terrain rejects restart rather than silently starting a stopped worker")
	ecosystem.free()
	vegetation.free()
	camera.free()
	terrain.free()
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/integration.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "engine": Engine.get_version_info()}, "  "))
	file.close()
	quit(0 if failures == 0 else 1)

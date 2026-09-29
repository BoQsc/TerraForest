extends SceneTree
const Scene = preload("res://demo/world.tscn")
const Presentation = preload("res://addons/presentation/fullscreen_policy.gd")
var game: Node3D
var checks := 0
var failures := 0
var messages: Array[String] = []
var slot := "pager_world_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
var paging_samples: Array[float] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func until(predicate: Callable,seconds: int = 60) -> bool:
	var end := Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<end:
		if game != null:
			var stats: Dictionary = game.structures.region_paging_stats()
			if stats.active: paging_samples.append(stats.last_ms)
		await process_frame
	return predicate.call()

func create_world() -> void:
	game=Scene.instantiate()
	game.terrain.save_slot=slot
	game.fly=true
	game.terrain.message_changed.connect(func(text: String): messages.append(text))
	root.add_child(game)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func travel(origin: Vector3i) -> void:
	game.fly=true
	game.player.velocity=Vector3.ZERO
	game.player.global_position=Vector3(origin)+Vector3(12,15,18)
	game.terrain.focus=game.player.global_position

func save() -> bool:
	messages.clear()
	game.terrain.save_world()
	return await until(func(): return messages.any(func(text): return text.begins_with("World saved and verified")),30)

func region(origin: Vector3i) -> Vector3i:
	return Vector3i(floori(origin.x/64.0),floori(origin.y/64.0),floori(origin.z/64.0))

func run() -> void:
	create_world()
	check(await until(func(): return game.terrain.world_ready and not game.loading_active and game.structures.region_paging_stats().active),"persistent main scene starts automatic native building paging")
	if failures:
		finish()
		return
	var near := Vector3i(800,144,1310)
	var far := Vector3i(1696,144,1310)
	var near_key := region(near)
	var far_key := region(far)
	var cottage: Resource = load("res://addons/structures/prefabs/brick_cottage.tres")
	var blocks: Node3D = game.structures.blocks
	check(blocks.place_prefab(cottage,near,0) and blocks.place_prefab(cottage,far,0),"persistent fixture authors two separated textured cottages")
	var near_packet: PackedByteArray = blocks.capture_region(near_key)
	var far_packet: PackedByteArray = blocks.capture_region(far_key)
	blocks.clear_history()
	travel(near)
	check(await save(),"main terrain worker commits the authored building regions")
	check(await until(func(): return not blocks.is_region_loaded(far_key) and blocks.is_region_loaded(near_key)),"main scene evicts the distant committed cottage automatically")
	check(game.structures.capture_snapshot().is_empty() and not game.structures.capture_storage_snapshot().is_empty(),"paged main world exposes a safe storage snapshot while legacy capture remains guarded")
	travel(far)
	check(await until(func(): return blocks.is_region_loaded(far_key) and not blocks.is_region_loaded(near_key)),"player travel admits the destination cottage and evicts the old distant region")
	check(blocks.capture_region(far_key)==far_packet,"travel restores exact authored shapes and materials")
	var stair := far+Vector3i(12,0,0)
	check(blocks.set_cells(PackedInt32Array([stair.x,stair.y,stair.z,3])),"native building edit is accepted in an admitted region")
	var edited_far: PackedByteArray = blocks.capture_region(far_key)
	travel(near)
	check(await until(func(): return blocks.is_region_loaded(near_key)),"return travel reloads the original cottage")
	for i in range(30): await process_frame
	check(blocks.is_region_loaded(far_key) and blocks.can_undo() and blocks.get_cell(stair)==3,"automatic main-scene paging retains a distant unsaved edit and undo history")
	check(await save(),"main world saves edits while other building residency changes")
	blocks.clear_history()
	check(await until(func(): return not blocks.is_region_loaded(far_key)),"committed distant edit becomes evictable after history releases it")
	check(await save(),"main world persists the resulting partially resident state")
	var epoch: int = game.structures.region_paging_stats().epoch
	game.terrain.reload_world()
	check(await until(func(): return game.terrain.world_ready and not game.loading_active and game.structures.region_paging_stats().epoch>epoch and blocks.is_region_loaded(near_key)),"hot reload restores metadata and automatically resumes nearby admission with a new epoch")
	check(blocks.capture_region(near_key)==near_packet and not blocks.is_region_loaded(far_key),"hot reload keeps exact nearby cells and leaves distant cottage unloaded")
	game.terrain.shutdown()
	game.free()
	game=null
	await process_frame
	create_world()
	check(await until(func(): return game.terrain.world_ready and not game.loading_active and game.structures.region_paging_stats().active),"fresh main-scene instance reopens the paged saved world")
	blocks=game.structures.blocks
	travel(far)
	check(await until(func(): return blocks.is_region_loaded(far_key) and not blocks.is_region_loaded(near_key)),"fresh instance streams the distant edited cottage on travel")
	check(blocks.capture_region(far_key)==edited_far and blocks.get_cell(stair)==3,"resident edit survives save eviction hot reload shutdown and fresh startup")
	var stats: Dictionary = game.structures.region_paging_stats()
	check(stats.scan_high<=128 and stats.operation_high<=1 and blocks.region_stats().resident_chunks<=1536,"interactive main-world paging stays within configured scan transfer and chunk bounds")
	if DisplayServer.get_name()!="headless":
		var measurement: Dictionary = Presentation.measurement(root)
		check(measurement.window_size==[1920,1080] and measurement.viewport==[1920,1080] and measurement.fullscreen,"persistent paging evidence uses 1920x1080 fullscreen")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/block_pager_world.png")
	finish()

func finish() -> void:
	var stats: Dictionary = game.structures.region_paging_stats() if game != null else {}
	if game != null:
		game.terrain.shutdown()
		game.free()
		game=null
	paging_samples.sort()
	var timing := {}
	if not paging_samples.is_empty():
		timing={"samples":paging_samples.size(),"median_ms":paging_samples[paging_samples.size()/2],"p95_ms":paging_samples[mini(paging_samples.size()-1,int(paging_samples.size()*0.95))],"max_ms":paging_samples[-1]}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/block_pager_world.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"pager":stats,"observed_step_times":timing,"scope":"Two-cottage persistent main-world travel and reload; not a city or sustained high-speed benchmark."},"  "))
	file.close()
	quit(1 if failures else 0)

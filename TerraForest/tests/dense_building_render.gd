extends SceneTree
const Scene = preload("res://demo/structures.tscn")
const Presentation = preload("res://addons/presentation/fullscreen_policy.gd")
var game: Node3D
var checks := 0
var failures := 0
var report := {}
var upload_bounded := true

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func summary(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	values.sort()
	return {"samples":values.size(),"median_ms":values[values.size()/2],"p95_ms":values[mini(values.size()-1,int(values.size()*0.95))],"max_ms":values[-1]}

func settle(label: String,seconds: int = 120) -> bool:
	var start := Time.get_ticks_usec()
	var previous := start
	var intervals: Array[float] = []
	var uploads: Array[float] = []
	while Time.get_ticks_usec()-start<seconds*1000000:
		await process_frame
		var now := Time.get_ticks_usec()
		intervals.append((now-previous)/1000.0)
		previous=now
		var stream: Dictionary = game.buildings.streaming_stats()
		uploads.append(stream.upload_last_us/1000.0)
		upload_bounded=upload_bounded and stream.upload_last_chunks<=stream.upload_chunk_limit and (stream.upload_last_bytes<=stream.upload_byte_limit or stream.upload_last_chunks==1)
		if game.buildings.is_idle() and game.buildings.collision_stats().ready and game.buildings.collision_stats().retired_bodies==0:
			report[label]={"ready_ms":(now-start)/1000.0,"frame_intervals":summary(intervals),"native_upload_stage":summary(uploads),"blocks":game.buildings.stats(),"streaming":game.buildings.streaming_stats(),"collision":game.buildings.collision_stats()}
			return true
	report[label]={"timeout":true,"frame_intervals":summary(intervals),"blocks":game.buildings.stats(),"streaming":game.buildings.streaming_stats(),"collision":game.buildings.collision_stats()}
	return false

func run() -> void:
	game=Scene.instantiate()
	root.add_child(game)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var blank: Node3D = ClassDB.instantiate("NativeBlockWorld")
	game.buildings.restore_snapshot(blank.capture_snapshot())
	blank.free()
	game.buildings.configure_history(0,0)
	check(game.buildings.configure_streaming(true,384,256,64*1024*1024,32*1024*1024),"dense render fixture uses the main-world mesh and cache budgets")
	var floor_prefab: Resource = load("res://addons/structures/prefabs/tower_floor.tres")
	var cottage: Resource = load("res://addons/structures/prefabs/brick_cottage.tres")
	var authored := true
	var start := Time.get_ticks_usec()
	for z in range(4):
		for x in range(4):
			var origin := Vector3i(x*40-60,0,z*40-60)
			for floor_index in range(12):
				authored=game.buildings.place_prefab(floor_prefab,origin+Vector3i(0,floor_index*4,0),0) and authored
	for x in range(8):
		authored=game.buildings.place_prefab(cottage,Vector3i(x*24-84,0,-108),0) and authored
	report["authoring_ms"]=(Time.get_ticks_usec()-start)/1000.0
	check(authored,"native prefab authoring creates sixteen twelve-storey towers and eight cottages")
	var original: PackedByteArray = game.buildings.capture_snapshot()
	var viewpoint := Vector3(150,85,-185)
	game.camera.position=viewpoint
	game.camera.look_at(Vector3(0,18,0))
	game.buildings.set_focus(viewpoint)
	game.notice="Dense district · 16 towers / 8 cottages"
	check(await settle("cold_load"),"dense district completes nearby mesh and collision admission")
	var stream: Dictionary = game.buildings.streaming_stats()
	check(stream.deferred_chunks==0 and stream.budget_blocked_chunks==0,"all authored district chunks fit the configured view without missing pieces")
	check(stream.mesh_payload_bytes<=64*1024*1024 and stream.cache_capacity_bytes<=32*1024*1024,"dense district respects mesh and cache payload budgets")
	await create_timer(3.0).timeout
	var intervals: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in range(240):
		await process_frame
		var now := Time.get_ticks_usec()
		intervals.append((now-previous)/1000.0)
		previous=now
	report["stationary_frames"]=summary(intervals)
	report["engine_static_bytes"]=int(Performance.get_monitor(Performance.MEMORY_STATIC))
	report["scene_nodes"]=int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if DisplayServer.get_name()!="headless":
		report["presentation"]=Presentation.measurement(root)
		check(report.presentation.fair_graphical_sample,"dense district is measured at 1920x1080 fullscreen and full rendering scale")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/dense_building_render.png")
		var reference: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/block_material_tiles.json"))
		var tiles: Texture2DArray
		for child in game.buildings.get_children():
			if child is MeshInstance3D:
				tiles=child.mesh.surface_get_material(0).get_shader_parameter("tiles")
				break
		var tile_hashes := []
		for layer in range(4):
			var data: PackedByteArray = tiles.get_layer_data(layer).get_data()
			var hash := HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(data)
			var digest := hash.finish().hex_encode()
			tile_hashes.append(digest)
			check(data.size()==reference[layer].bytes and digest==reference[layer].sha256,"bulk-generated material layer %d preserves every texel and mip level" % layer)
		report["material_tile_hashes"]=tile_hashes
	# Move down a street at 30 m/s; sample actual frame intervals, including
	# collision retirement and admission. This is an authoring camera, not a car.
	intervals.clear()
	previous=Time.get_ticks_usec()
	start=previous
	while Time.get_ticks_usec()-start<6000000:
		var t := float(Time.get_ticks_usec()-start)/1000000.0
		game.camera.position=Vector3(-90+t*30,6,-40)
		game.camera.look_at(game.camera.position+Vector3(1,0.15,0.25))
		await process_frame
		var now := Time.get_ticks_usec()
		intervals.append((now-previous)/1000.0)
		previous=now
	report["street_travel_frames"]=summary(intervals)
	check(await settle("street_settle"),"street-level nearby collision finishes after travel")
	check(game.buildings.capture_snapshot()==original,"render and collision travel leave authored district bytes unchanged")
	game.camera.position=viewpoint+Vector3(1000,0,0)
	check(await settle("away"),"distant view finishes mesh and physics retirement")
	check(game.buildings.stats().mesh_chunks==0 and game.buildings.collision_stats().live_pieces==0,"distant travel releases all district meshes and physics")
	game.camera.position=viewpoint
	game.camera.look_at(Vector3(0,18,0))
	check(await settle("return"),"return view restores the district within the same budgets")
	check(game.buildings.capture_snapshot()==original,"cache return preserves the entire district")
	check(game.buildings.streaming_stats().bake_jobs==report.cold_load.streaming.bake_jobs,"returning district uses cached geometry without any new worker bakes")
	check(upload_bounded and game.buildings.streaming_stats().upload_high_chunks>1,"district cache return batches uploads within per-frame count and payload policies")
	report["checks"]=checks
	report["failures"]=failures
	report["scope"]="Rendered block district and shared showcase props with shadows; no terrain, forest, cell-region paging, multiplayer or vehicle simulation. Frame intervals include VSync and scheduling; not isolated GPU timings."
	game.free()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/dense_building_render.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	quit(1 if failures else 0)

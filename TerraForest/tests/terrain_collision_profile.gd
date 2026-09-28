extends SceneTree
## Opt-in diagnostic, not an FPS benchmark or a hard latency test.
const Scene = preload("res://demo/world.tscn")
const Presentation = preload("res://addons/presentation/fullscreen_policy.gd")
var game: Node3D
var samples: Array[Dictionary] = []
var worst := PackedVector3Array()
var worst_ms := -1.0
var dropped := 0

func _initialize() -> void:
	run.call_deferred()

func record(sample: Dictionary, faces: PackedVector3Array) -> void:
	sample["triangles"]=faces.size()/3
	if samples.size()<10000: samples.append(sample)
	else: dropped+=1
	if float(sample.cook_ms)>worst_ms and not sample.reused:
		worst_ms=sample.cook_ms
		worst=faces

func stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	values.sort()
	return {"count":values.size(),"median_ms":values[values.size()/2],"p95_ms":values[mini(values.size()-1,int(values.size()*0.95))],"max_ms":values.back()}

func run() -> void:
	var piece_size := 1024
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--collision-piece-triangles="): piece_size=int(arg.get_slice("=",1))
	game=Scene.instantiate()
	# Desktop focus must not change this comparison's 60 FPS cap.
	game.max_fps=60
	game.background_fps=60
	if not game.terrain.backend.configure_collision_piece_size(piece_size):
		game.free()
		push_error("Invalid collision profile piece size")
		quit(1)
		return
	game.temporary_world=true
	game.terrain.profile_collision_pieces=true
	game.terrain.collision_piece_measured.connect(record)
	root.add_child(game)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	# Use a wall-clock window so low FPS cannot silently shorten sampling.
	var begin := Time.get_ticks_msec()
	var deadline := begin+30000
	var ready_ms := -1
	var frame_intervals: Array[float] = []
	var physics_times: Array[float] = []
	var previous_frame := Time.get_ticks_usec()
	while Time.get_ticks_msec()<deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		if ready_ms<0 and game.terrain.world_ready and not game.loading_active: ready_ms=Time.get_ticks_msec()-begin
		if ready_ms>=0 and Time.get_ticks_msec()-begin>ready_ms+3000 and frame_intervals.size()<10000:
			frame_intervals.append(float(now-previous_frame)/1000.0)
			physics_times.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		previous_frame=now
	var presentation: Dictionary = Presentation.measurement(root)
	var ready: bool = game.terrain.world_ready and not game.loading_active
	var resident_shapes := 0
	for entry in game.terrain.tiles.values(): resident_shapes+=entry.get("collision_shapes",{}).size()
	var resident_tiles: int = game.terrain.tiles.size()
	var engine_static_bytes := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var scene_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	game.terrain.shutdown()
	game.free()
	await process_frame
	# The worker is stopped before isolated replays. Retain only one <=1024
	# triangle piece; no entire terrain snapshot or unbounded trace retention.
	var recipes: RefCounted = ClassDB.instantiate("NativeTerrainCollision")
	var replay := {}
	for size in [256,512,1024]:
		var prepared: Dictionary = recipes.prepare(worst,size)
		var times: Array[float] = []
		var totals: Array[float] = []
		for repetition in range(40):
			var total := 0.0
			for piece in prepared.pieces:
				var result: Dictionary = piece.resolve({})
				times.append(result.cook_ms)
				total+=float(result.cook_ms)
			totals.append(total)
		replay[str(size)]={"pieces":prepared.pieces.size(),"per_piece":stats(times),"whole_fixture":stats(totals)}
	var cook: Array[float] = []
	for sample in samples:
		if not sample.reused: cook.append(sample.cook_ms)
	var pass_result: bool = ready and not worst.is_empty() and dropped==0 and (presentation.headless or presentation.fair_graphical_sample)
	var report := {"pass":pass_result,"world_ready":ready,"presentation":presentation,"engine":Engine.get_version_info(),"scope":"30-second temporary-world startup, wall-clock main-thread shape creation; isolated replay after worker shutdown excludes body attachment and simulation. Not a physical display, endurance or CPU-time guarantee.","runtime_cook":stats(cook),"samples":samples,"dropped":dropped,"worst_faces_triangles":worst.size()/3,"replay":replay}
	report["configured_piece_triangles"]=piece_size
	report["ready_ms"]=ready_ms
	report["resident_tiles"]=resident_tiles
	report["resident_shapes"]=resident_shapes
	report["engine_static_bytes"]=engine_static_bytes
	report["scene_nodes"]=scene_nodes
	report["steady_frame_intervals"]=stats(frame_intervals)
	report["steady_physics_monitor"]=stats(physics_times)
	report["foreground_and_background_fps_cap"]=60
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/terrain_collision_profile.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	file=FileAccess.open("res://reports/terrain_collision_worst.faces",FileAccess.WRITE)
	file.store_buffer(worst.to_byte_array())
	file.close()
	print("PASS " if pass_result else "FAIL ","terrain collision profile ",JSON.stringify({"runtime":stats(cook),"replay":replay}))
	quit(0 if pass_result else 1)

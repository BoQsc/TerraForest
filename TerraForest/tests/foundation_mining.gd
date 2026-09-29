extends SceneTree
## Adversarial integrated workload. Failure is evidence, not a reason to relax budgets.
const Scene = preload("res://demo/world.tscn")
const Presentation = preload("res://addons/presentation/fullscreen_policy.gd")
var game: Node3D
var phase := "startup"
var frames: Array[float] = []
var edits: Array[Dictionary] = []
var phases: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var previous_us := 0
var height_token := 900000
var height_value := NAN
var phase_begin := 0
var stage_totals: Dictionary = {}
var frame_file: FileAccess
var workload_scale := 1
var work: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func frame() -> void:
	var now := Time.get_ticks_usec()
	if previous_us > 0:
		var elapsed := (now-previous_us)/1000.0
		frames.append(elapsed)
		frame_file.store_csv_line([phase,str(now),str(elapsed),str(game.terrain.backend.queued()),str(game.terrain.sdf_pages),str(Performance.get_monitor(Performance.MEMORY_STATIC))])
	previous_us=now

func stage(label: String, elapsed: float) -> void:
	var row: Dictionary=stage_totals.get(label,{"calls":0,"total_ms":0.0,"max_ms":0.0})
	row.calls+=1
	row.total_ms+=elapsed
	row.max_ms=maxf(row.max_ms,elapsed)
	stage_totals[label]=row

func summary(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var stalls := 0
	for value in values:
		if value>50: stalls+=1
	return {"count":values.size(),"median_ms":sorted[sorted.size()/2],"p95_ms":sorted[mini(sorted.size()-1,int(sorted.size()*.95))],"p99_ms":sorted[mini(sorted.size()-1,int(sorted.size()*.99))],"max_ms":sorted.back(),"over_50ms":stalls}

func check(ok: bool, label: String) -> void:
	checks.append({"pass":ok,"name":label})
	print("PASS " if ok else "FAIL ",label)

func until(predicate: Callable, seconds: float=30) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await process_frame
	return predicate.call()

func begin_phase(label: String) -> void:
	phase=label
	frames.clear()
	edits.clear()
	stage_totals.clear()
	work.clear()
	phase_begin=Time.get_ticks_msec()
	print("FOUNDATION_PHASE ",phase)

func end_phase() -> void:
	var latency: Array[float]=[]
	var builds: Array[float]=[]
	var queue: Array[float]=[]
	var changed := 0
	for row in edits:
		latency.append(row.publish_ms)
		builds.append(row.build_ms)
		queue.append(row.worker_queue_ms)
		if row.changed: changed+=1
	var record := {"phase":phase,"elapsed_ms":Time.get_ticks_msec()-phase_begin,"frames":summary(frames),"edit_latency":summary(latency),"build":summary(builds),"worker_queue":summary(queue),"changed_edits":changed,"edits":edits.duplicate(true),"stages":stage_totals.duplicate(true),"sdf_pages":game.terrain.sdf_pages,"triangles":game.terrain.total_triangles,"tiles":game.terrain.tiles.size(),"cache_bytes":game.terrain.cache_bytes,"engine_static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"trees":game.vegetation.renderer.roots.size()}
	phases.append(record)
	record["patch_work"]=work.duplicate(true)
	checkpoint(false)
	frame_file.flush()
	print("FOUNDATION_RESULT ",JSON.stringify({"phase":phase,"frames":record.frames,"latency":record.edit_latency,"build":record.build,"pages":record.sdf_pages}))

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--foundation-scale="):
			workload_scale=int(arg.get_slice("=",1))
	if workload_scale not in [1,4,16]:
		push_error("Foundation scale must be 1, 4 or 16")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute("res://reports")
	frame_file=FileAccess.open("res://reports/foundation_mining.frames.csv",FileAccess.WRITE)
	frame_file.store_csv_line(["phase","time_us","frame_ms","queued","sdf_pages","engine_static_bytes"])
	game=Scene.instantiate()
	game.temporary_world=true
	game.max_fps=60
	game.background_fps=60
	root.add_child(game)
	game.fly=true
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	process_frame.connect(frame)
	game.terrain.stage_measured.connect(stage)
	game.terrain.work_measured.connect(func(row: Dictionary): work.append(row.duplicate(true)))
	game.terrain.edit_measured.connect(func(row: Dictionary): edits.append(row.duplicate(true)))
	game.terrain.height_received.connect(func(_point: Vector3,h: float,token: int):
		if token==height_token: height_value=h)
	if not await until(func(): return game.terrain.world_ready and not game.loading_active,60):
		check(false,"initial world readiness within 60 seconds")
		finish()
		return
	check(Presentation.measurement(root).fair_graphical_sample,"1920x1080 fullscreen, full rendering scale")
	begin_phase("streaming_baseline")
	await create_timer(5).timeout
	end_phase()
	for scenario in ["compact_history_control","expanding_excavation","travel_new_regions","return_history_control"]:
		begin_phase(scenario)
		var count := (64 if scenario=="travel_new_regions" else 24)*workload_scale
		for index in range(count):
			var x := 832.0+float(index%64)*8.0 if scenario=="travel_new_regions" else 800.0
			var z := 1310.0+float(index/64)*8.0 if scenario=="travel_new_regions" else 1310.0
			if scenario.ends_with("history_control"): x=760.0
			if scenario=="expanding_excavation": x+=float(index/24)*8.0
			var point := Vector3(x,0,z)
			height_value=NAN
			height_token+=1
			game.terrain.request_height(point,height_token)
			if not await until(func(): return is_finite(height_value)):
				check(false,"height query deadline in "+scenario)
				end_phase()
				finish()
				return
			point.y=height_value
			game.player.position=point+Vector3(0,10,12)
			game.camera.look_at(point)
			if scenario=="expanding_excavation": point.y-=float(index%24)*.5
			var add: bool=scenario.ends_with("history_control") and index%2==1
			var before := edits.size()
			var accepted: bool=game.terrain.sculpt_sphere(point,2.5,add)
			if not accepted or not await until(func(): return not game.terrain.pending_edit and edits.size()>before):
				check(false,"edit admission/publication deadline in "+scenario)
				end_phase()
				finish()
				return
		end_phase()
	begin_phase("recovery")
	await create_timer(10).timeout
	end_phase()
	for row in phases:
		check(not row.frames.is_empty() and row.frames.p99_ms<=20.0 and row.frames.over_50ms==0,row.phase+": frame p99 <=20 ms and no >50 ms stalls")
		if not row.edit_latency.is_empty():
			check(row.edit_latency.p95_ms<=150.0,row.phase+": edit publication p95 <=150 ms")
			check(row.changed_edits>=row.edits.size()*.9,row.phase+": at least 90 percent of edits actually change terrain")
	var first: Dictionary=phases[1].edit_latency
	var last: Dictionary=phases[4].edit_latency
	check(last.median_ms<=first.median_ms*1.25,"return control median latency grows no more than 25 percent")
	finish()

func checkpoint(complete: bool) -> void:
	var report := {"workload_scale":workload_scale,"checks":checks,"phases":phases,"presentation":Presentation.measurement(root),"engine":Engine.get_version_info(),"scope":"Integrated temporary terrain and forest; scripted public edit calls and stepped travel without waiting for destination residency; four controlled workloads and recovery. Separate original/return control site. Does not test furnished cities, entities, multiplayer, physical input latency, or hour-long endurance. 20 ms frame gate is a regression tolerance, not proof of strict 60 FPS or headroom."}
	report["complete"]=complete
	var file := FileAccess.open("res://reports/foundation_mining.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()

func finish() -> void:
	process_frame.disconnect(frame)
	frame_file.close()
	checkpoint(phases.size()==6)
	game.terrain.shutdown()
	game.free()
	await process_frame
	quit(0 if checks.all(func(row): return row.pass) else 1)

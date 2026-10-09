# SPDX-License-Identifier: 0BSD
extends SceneTree
const DIR="res://reports/furnished_cost/"
var game: Node
var failures:=0
var phases: Array=[]
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func summary(rows: Array,key: String) -> Dictionary:
	var values: Array=[]
	for row: Dictionary in rows: values.append(float(row[key]))
	values.sort()
	return {"median":values[values.size()/2],"p95":values[floori((values.size()-1)*0.95)],"p99":values[floori((values.size()-1)*0.99)],"max":values.back()}
func ready() -> bool:
	return game.terrain.backend.status()=="idle" and game.terrain.backend.queued()==0 and game.ground_cover.resident.size()==49 and game.ground_cover._requests.is_empty() and game.ground_cover._support_job.is_empty() and game.ground_cover._dirty.is_empty()
func sample(label: String,eye: Vector3,aim: Vector3) -> void:
	game.player.global_position=eye-Vector3.UP*1.6;game.camera.global_position=eye;game.camera.look_at(aim)
	var deadline:=Time.get_ticks_msec()+12000
	var idle:=0
	while idle<60 and Time.get_ticks_msec()<deadline:
		await RenderingServer.frame_post_draw
		idle=idle+1 if ready() else 0
	check(idle==60,label+" settles for 60 frames before capture")
	var rows: Array=[];var previous:=Time.get_ticks_usec();var viewport:=root.get_viewport_rid()
	for frame in range(180):
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec()
		rows.append({"frame_ms":(now-previous)/1000.0,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"terrain_active":0 if game.terrain.backend.status()=="idle" else 1,"terrain_queued":game.terrain.backend.queued()})
		previous=now
	var result:={"view":label,"eye":eye,"aim":aim,"rows":rows,"summary":{},"ground":[],"furniture":[],"trees":game.vegetation.renderer.roots.size(),"blocks":game.structures.blocks.stats(),"block_render":game.structures.blocks.streaming_stats()}
	for key in rows[0]:result.summary[key]=summary(rows,key)
	for batch in game.ground_cover.batches:result.ground.append(batch.render_stats())
	for name in ["table","chair","shelf"]:result.furniture.append(game.structures.model("furniture/"+name+"/v1").render_stats())
	check(result.summary.frame_ms.p95<=18.5 and result.summary.frame_ms.p99<=25 and result.summary.frame_ms.max<=50,label+" meets unchanged short-route frame gates")
	check(result.summary.gpu_ms.median>0,label+" has GPU measurements")
	check(result.summary.terrain_active.max==0 and result.summary.terrain_queued.max==0,label+" has no terrain work during capture")
	phases.append(result)
	root.get_texture().get_image().save_png(DIR+label+".png")
	print("FURNISHED_PHASE ",JSON.stringify({"view":label,"summary":result.summary}))
func run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active and game.terrain.save_slot.begins_with("furnished_probe_"),"disposable furnished world loaded")
	game.set_physics_process(false);game._clear_motion();game.fly=true;game.needs_floor_spawn=false
	check(game.structures.blocks.stats().cells==1872 and game.ground_enabled,"declared four cottages and ground cover active")
	for name in ["table","chair","shelf"]:check(game.structures.model("furniture/"+name+"/v1").get_ids().size()==4,"four "+name+" objects loaded")
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence/furnished_world/manifest.json"))
	var origin:=Vector3(manifest.target[0],manifest.target[1],manifest.target[2])
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	await sample("interior",origin+Vector3(4.5,3.7,-10),origin+Vector3(4.5,2.8,-15))
	await sample("entrance",origin+Vector3(4.5,3.7,-6),origin+Vector3(4.5,2.8,-14))
	await sample("overview",origin+Vector3(40,26,54),origin+Vector3(4,2,16))
	var presentation: Dictionary=preload("res://addons/presentation/fullscreen_policy.gd").measurement(root)
	check(presentation.fair_graphical_sample and Engine.max_fps==60,"native fullscreen1080p cap60")
	var report:={"failures":failures,"slot":game.terrain.save_slot,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"presentation":presentation,"phases":phases,"scope":"Three stationary views, 180 post-draw intervals each; bounded small furnished settlement with forest/ground cover. Cap included in frame intervals. Viewport GPU time is not GPU usage, power or thermal proof. Not a travel, active simulation, dense-city or endurance test."}
	var file:=FileAccess.open(DIR+"cost.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),false)
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
	print("FURNISHED_COST failures=",failures);quit(1 if failures else 0)

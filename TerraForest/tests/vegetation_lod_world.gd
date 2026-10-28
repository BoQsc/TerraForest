extends SceneTree

var game:Node
var failures:=0
var output:="res://reports/vegetation_lod_world"
var phases:=[]

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->bool:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
	return ok

func wait_for(predicate:Callable,seconds:int)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()

func settled()->bool:
	return not game.loading_active and game.ecosystem.resident.size()==game.ecosystem._wanted.size() and game.ecosystem._requests.is_empty() and game.ecosystem._reconcile.is_empty()

func summarize(values:Array)->Dictionary:
	values.sort()
	return {"median":values[values.size()/2],"p95":values[int(values.size()*.95)],"max":values[-1]}

func run()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	DirAccess.make_dir_recursive_absolute(output)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60
	root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active or not game.terrain.latest_error.is_empty(),90),"actual world loads"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.fly=true
	check(await wait_for(settled,90),"extended real-terrain forest settles with bounded jobs")
	var viewport:=root.get_viewport_rid();RenderingServer.viewport_set_measure_render_time(viewport,true)
	for mode in ["stationary","travel"]:
		var frames:=[];var gpu:=[];var render_cpu:=[];var forest_cpu:=[];var scatter_cpu:=[]
		var previous:=Time.get_ticks_usec()
		for frame in 240:
			if mode=="travel":game.player.position.x+=.15
			await RenderingServer.frame_post_draw
			var now:=Time.get_ticks_usec();frames.append((now-previous)/1000.0);previous=now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
			render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport))
			forest_cpu.append(game.vegetation.last_process_us/1000.0);scatter_cpu.append(game.ecosystem.last_process_us/1000.0)
		phases.append({"mode":mode,"frame_ms":summarize(frames),"gpu_ms":summarize(gpu),"render_cpu_ms":summarize(render_cpu),"forest_cpu_ms":summarize(forest_cpu),"scatter_cpu_ms":summarize(scatter_cpu),"owners":game.ecosystem.resident.size(),"roots":game.vegetation.renderer.roots.size()})
		check(game.ecosystem.resident.size()<=441 and game.ecosystem._requests.size()<=2 and game.vegetation.renderer.roots.size()<=16384,"bounded streaming during "+mode)
		root.get_texture().get_image().save_png(output.path_join(mode+".png"))
	check(await wait_for(settled,90),"travel catches up without lost owners")
	check(game.ecosystem.rejected_batches==0 and game.terrain.latest_error.is_empty(),"no rejected forest publication or terrain errors")
	check(preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"automated test never captures the desktop pointer")
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"phases":phases,"gpu":RenderingServer.get_video_adapter_name(),"scope":"Fresh temporary seed 1703 baseline world, extended forest, 240 stationary + 240 moving frames at 1080p nonactivating offscreen; not dense-city/endurance qualification."},"  "))
	await finish()

func finish()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
	print("VEGETATION_LOD_WORLD failures=",failures);quit(1 if failures else 0)

extends SceneTree

var game: Node3D
var failures:=0
var output:="res://reports/world_overview"
var saved_hash:=""
var save_path:="user://worlds/recipe_generated_4644d8cfc8f97e43.trw"

func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var arguments:=PackedStringArray(["--world-slot=recipe_generated_4644d8cfc8f97e43","--snapshot-readonly","--temporary","--gameplay-construction","--ground-cover","--actors","--vehicle-fleet"])
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--view-output="):output=argument.trim_prefix("--view-output=")
		if argument.begins_with("--derived-cache="):arguments.append(argument)
	DirAccess.make_dir_recursive_absolute(output)
	if not FileAccess.file_exists(save_path):push_error("Missing disposable populated-world fixture");quit(1);return
	saved_hash=FileAccess.get_sha256(save_path)
	preload("res://addons/world_runtime/session_options.gd").set_arguments(arguments,true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+150000
	while game.loading_active and Time.get_ticks_msec()<deadline and game.terrain.latest_error.is_empty():
		game.app_focused=true;await process_frame
	check(not game.loading_active and game.terrain.latest_error.is_empty(),"populated read-only world loads with exact building horizon")
	check(game.terrain.root_coverage==64,"all actual terrain roots are ready before play")
	if failures:await finish({});return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true
	var view=game.player_view
	var body_pose:Transform3D=game.player.global_transform
	var eye_pose:Transform3D=game.camera.transform
	var original_environment:Environment=game.camera.environment if game.camera.environment!=null else game.get_world_3d().environment
	var original_fog:=original_environment.fog_density
	var collision_focus:Vector3=game.terrain.focus
	var near_state:Dictionary=game.structures.blocks.capture_storage_state()
	var before_trees:int=game.vegetation.renderer.roots.size()
	var samples:=[]
	check(not view.active and game.camera.current,"default remains first person")
	view.set_overview(true)
	check(view.active and view.third_camera.current and not game._model_edit_available(),"overview uses actual world camera and disables remote tool actions")
	check(game.vegetation.collision_camera==game.camera and game.ecosystem.camera==game.camera and game.ground_cover.camera==game.camera,"visual zoom does not move tree ownership or local collision")
	var viewport:=root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport,true)
	for distance:float in [32.0,256.0,768.0,1800.0]:
		view.overview_distance=distance
		for frame in 120:
			game.app_focused=true;await RenderingServer.frame_post_draw
		check(game.terrain.root_coverage==64,"zoom preserves complete volumetric terrain coverage "+str(distance))
		check(absf(view.zoom_distance-distance)<1.0,"smooth zoom reaches requested distance "+str(distance))
		check(game.player.global_transform.is_equal_approx(body_pose) and game.camera.transform.is_equal_approx(eye_pose),"overview preserves physical body and first-person aim")
		check(game.terrain.focus==collision_focus and game.terrain.render_view.is_finite(),"separate render focus leaves physical focus unchanged")
		var elapsed:Array[float]=[];var gpu:Array[float]=[]
		var previous:=Time.get_ticks_usec()
		for frame in 60:
			game.app_focused=true;await RenderingServer.frame_post_draw
			var now:=Time.get_ticks_usec();elapsed.append((now-previous)/1000.0);previous=now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
		elapsed.sort();gpu.sort()
		var row:Dictionary={"distance":distance,"actual_camera_distance":view.third_camera.global_position.distance_to(game.camera.global_position),"frame_p95_ms":elapsed[57],"gpu_p95_ms":gpu[57],"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"horizon":game.structures.blocks.distant_rendering_stats(),"terrain_tiles":game.terrain.tiles.size(),"trees":game.vegetation.renderer.roots.size()}
		samples.append(row)
		root.get_texture().get_image().save_png(output.path_join("overview_%d.png"%int(distance)))
	check(game.structures.blocks.capture_storage_state()==near_state,"zoom alone does not hydrate remote editable building regions")
	check(game.structures.blocks.distant_rendering_stats().ready,"world-wide building representation remains ready at maximum zoom")
	view.set_overview(false)
	for frame in 20:await RenderingServer.frame_post_draw
	check(game.camera.current and not view.active and game.terrain.render_view==Vector3.INF,"leaving overview restores first-person and normal planning")
	check(game.vegetation.renderer.far_distance==game.vegetation.draw_distance,"normal tree visibility range restored")
	check(is_equal_approx(original_environment.fog_density,original_fog),"overview atmosphere never changes first-person environment")
	view.set_enabled(true,false);view.update()
	check(view.active and view.third_camera.current and is_equal_approx(view.arm.spring_length,3.4),"existing third-person view still uses its original collision boom")
	view.set_enabled(false,false)
	var vehicles=game.world_vehicle
	var captured:PackedByteArray=vehicles.capture_snapshot()
	var count:int=vehicles.fleet.statistics().records
	game.session_menu.set_open(true);game.session_menu.show_page("Dev Spawner")
	game.session_menu.spawner.vehicle_button.pressed.emit()
	deadline=Time.get_ticks_msec()+15000
	while game.session_menu.spawner.vehicle_busy and Time.get_ticks_msec()<deadline:await process_frame
	check(vehicles.last_spawn_identity>0 and vehicles.fleet.statistics().records==count+1,"installed Dev Spawner creates default pack vehicle with one click")
	if vehicles.last_spawn_identity>0:
		var body:RigidBody3D=vehicles.activation.residents.get(vehicles.last_spawn_identity)
		check(body!=null and vehicles.kind_of(body)==vehicles.Packs.DEFAULT and vehicles.adapter(body)!=null,"installed Ranger runs through per-body module adapter")
	check(vehicles.restore_snapshot(captured),"vehicle module save restores without touching source world")
	await finish({"samples":samples,"starting_trees":before_trees,"mouse":Input.mouse_mode})
func finish(result:Dictionary)->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
	check(FileAccess.get_sha256(save_path)==saved_hash,"source save remains byte-identical")
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"test never captures the mouse")
	result["failures"]=failures
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("WORLD_OVERVIEW failures=",failures)
	quit(1 if failures else 0)

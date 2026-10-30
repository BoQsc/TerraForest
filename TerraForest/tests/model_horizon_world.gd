# SPDX-License-Identifier: 0BSD
extends SceneTree
const SAVE:="user://worlds/recipe_generated_4644d8cfc8f97e43.trw"
var game:Node3D
var failures:=0
var output:="res://reports/model_horizon_world"
var evidence:Dictionary={}
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func until(predicate:Callable,timeout:int=150000)->bool:
	var deadline:=Time.get_ticks_msec()+timeout;var next_note:=Time.get_ticks_msec()+5000
	while not predicate.call() and Time.get_ticks_msec()<deadline and game.terrain.latest_error.is_empty():
		game.app_focused=true
		if Time.get_ticks_msec()>=next_note:
			next_note+=5000
			print("MODEL_WORLD_WAIT ",game.loading_stage_text," · ",game.loading_work_text," · ",game.structures.model_horizon_stats())
		await process_frame
	if not predicate.call():print("MODEL_WORLD_STOP ",game.terrain.latest_error," · ",game.loading_stage_text," · ",game.structures.model_horizon_stats())
	return predicate.call()
func finish(original:String)->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	check(FileAccess.get_sha256(SAVE)==original,"original populated world remains byte-identical")
	evidence["failures"]=failures
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(evidence,"  "))
	print("MODEL_HORIZON_WORLD failures=",failures)
	quit(1 if failures else 0)
func run()->void:
	var options:=PackedStringArray(["--world-slot=recipe_generated_4644d8cfc8f97e43","--snapshot-readonly","--temporary","--ground-cover","--no-zombies"])
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--view-output="):output=argument.trim_prefix("--view-output=")
		if argument.begins_with("--derived-cache="):options.append(argument)
	DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_sha256(SAVE)
	preload("res://addons/world_runtime/session_options.gd").set_arguments(options,true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path=""
	root.add_child(game)
	var began:=Time.get_ticks_usec()
	check(await until(func():return not game.loading_active),"production play gate waits for complete prop visuals")
	evidence["load_seconds"]=(Time.get_ticks_usec()-began)/1000000.0
	if failures:await finish(original);return
	game.set_process(false);game.set_physics_process(false);game.player_view.set_process(false);game._clear_motion()
	var structures:Node3D=game.structures;var horizon:Node=structures._model_horizon
	check(await until(func():return structures.drain_model_paging(),10000),"model transfer boundary drains before exact logical-count audit")
	var rows:Array=[];var expected_total:=0;var complete:=true;var selected:Dictionary={}
	for collection:Node3D in structures._model_list:
		var region:Dictionary=collection.region_stats();var visual:PackedInt64Array=horizon.represented_ids(collection)
		expected_total+=region.logical_instances
		complete=complete and visual.size()==region.logical_instances and collection.render_stats().resident_batches==0
		rows.append({"asset":collection.stats().asset_id,"logical":region.logical_instances,"resident":region.resident_instances,"visual":visual.size()})
		for identity:int in visual:
			var record:Dictionary=horizon.visual_record(collection,identity)
			if record.is_empty():complete=false;continue
			var point:Vector3=collection.to_global(record.transform.origin)
			if selected.is_empty() and point.distance_to(game.player.global_position)>650:
				selected={"collection":collection,"identity":identity,"record":record,"point":point,"asset":collection.stats().asset_id}
	check(complete and expected_total>0 and horizon.statistics().rendered==expected_total,"every registered prop has exactly one world-wide visual representation")
	check(not selected.is_empty(),"fixture includes a represented object beyond the former local cutoff")
	evidence["collections"]=rows;evidence["initial"]=horizon.statistics()
	if failures:await finish(original);return
	var collection:Node3D=selected.collection;var identity:int=selected.identity
	var point:Vector3=selected.point;var record:Dictionary=selected.record
	var draw:MultiMeshInstance3D=record.node
	var gpu_pose:Transform3D=draw.global_transform*draw.multimesh.get_instance_transform(record.slot)
	check(gpu_pose.is_equal_approx(collection.global_transform*record.transform),"actual distant GPU placement matches canonical collection coordinates")
	game.camera.global_position=point+Vector3(6,4,6);game.camera.look_at(point+Vector3.UP)
	for frame in 45:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("distant_prop_close.png"))
	evidence["selected"]={"asset":selected.asset,"identity":identity,"point":point,"player_distance":point.distance_to(game.player.global_position)}
	var before:Dictionary=horizon.statistics()
	game.model_paging.focus=func():return point
	check(structures.resume_model_paging(),"model paging resumes with controlled distant focus")
	structures.set_model_focus(point)
	check(await until(func():return collection.get_instance(identity).size()==12,30000),"physical admission reaches the exact distant object")
	check(await until(func():return horizon.statistics().ready,10000),"visual owner remains ready after canonical admission")
	check(horizon.visual_record(collection,identity).node==draw and horizon.statistics().uploaded_bytes==before.uploaded_bytes,"canonical admission reuses the same GPU page instead of handing off duplicate visuals")
	var snapshot:PackedByteArray=collection.capture_region(Vector3i(floori(record.transform.origin.x/32),floori(record.transform.origin.y/32),floori(record.transform.origin.z/32)))
	var original_pose:PackedFloat32Array=collection.get_instance(identity)
	var changed:=original_pose.duplicate();changed[7]+=0.15
	check(collection.upsert_instances(PackedInt64Array([identity]),changed),"authored pose update is accepted through existing native API")
	check(await until(func():return horizon.statistics().ready,10000) and is_equal_approx(float(horizon.visual_record(collection,identity).transform.origin.y),float(changed[7])),"distant native visual follows the authored pose update")
	check(collection.upsert_instances(PackedInt64Array([identity]),original_pose),"pose restores in-memory without writing player save")
	check(await until(func():return horizon.statistics().ready,10000),"restored pose republishes")
	structures.set_model_focus(game.player.global_position)
	game.model_paging.focus=func():return game.player.global_position
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED,"offscreen validation never captures the OS pointer")
	evidence["final"]=horizon.statistics();evidence["captured_region_bytes"]=snapshot.size()
	await finish(original)

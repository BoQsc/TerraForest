# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var output:=""
var slot:=""
var samples:Array[Dictionary]=[]
var previous:=0
var label:="loading"
var manual_save:Dictionary={"requested":false,"completed":false,"success":false}
var light_abba:=false
var repeat_light_setters:=false
var light_phases:Array[Dictionary]=[]
func repeat_lights()->void:
	if not repeat_light_setters or not is_instance_valid(game):return
	for light:Node in game.structures.resident_lights.get_children():
		if light is OmniLight3D and light.visible:
			light.global_position=light.global_position
			light.light_energy=light.light_energy
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	node_added.connect(func(node:Node):
		if node.scene_file_path=="res://demo/world.tscn":ProjectSettings.set_setting("terraforest/offscreen_session",true))
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--trace-world-slot="):slot=arg.trim_prefix("--trace-world-slot=")
		if arg.begins_with("--trace-world-output="):output=arg.trim_prefix("--trace-world-output=")
	run.call_deferred()
func wait_for(predicate:Callable,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline and not predicate.call():
		if is_instance_valid(game):game.app_focused=true
		await process_frame
	return predicate.call()
func frame()->void:
	var now:=Time.get_ticks_usec()
	if previous>0:
		var sample:Dictionary={"phase":label,"frame_ms":(now-previous)/1000.0}
		if light_abba:
			sample.gpu_ms=RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
			sample.draw_calls=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		samples.append(sample)
	previous=now
func run()->void:
	if not slot.begins_with("StartupBench_FPS_") or not slot.is_valid_identifier() or output.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	RenderingServer.frame_post_draw.connect(frame)
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed
	var browser=current_scene
	if not await wait_for(func():return not browser.library.loading,60):quit(1);return
	var command:Dictionary=preload("res://demo/world_launch.gd").command(slot,false,29,1703,true)
	browser._open_game(command.args)
	if not await wait_for(func():return is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn",90):quit(1);return
	game=current_scene;game.background_fps=60;game.app_focused=true
	if not await wait_for(func():return game.startup_complete,90):quit(1);return
	if "--trace-no-first-person-depth" in OS.get_cmdline_user_args():game.first_person_view.set_enabled(false,false)
	if "--trace-uncapped" in OS.get_cmdline_user_args():
		game.max_fps=0;game.background_fps=0;Engine.max_fps=0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not await wait_for(func():return game.startup_complete and not game.loading_active and not game.player_view.entry.blocks_actions(),120):quit(1);return
	var trace=root.get_node_or_null("WorldSession/FrameTrace")
	var initializations:Array=[]
	for zombie:Node in game.zombies.residents:initializations.append(zombie.initialization_us.duplicate())
	var initial_yaw:float=game.yaw
	label="arrival_idle"
	var short:bool="--trace-short" in OS.get_cmdline_user_args()
	await wait_for(func():return false,12 if short else 20)
	light_abba="--trace-light-abba" in OS.get_cmdline_user_args()
	if light_abba:
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
		process_frame.connect(repeat_lights)
		for phase:String in ["guarded_a","repeated_b","repeated_b2","guarded_a2"]:
			repeat_light_setters=phase.begins_with("repeated")
			label="light_warmup"
			await wait_for(func():return false,1)
			label="lights_"+phase
			await wait_for(func():return false,5)
			light_phases.append({"phase":phase,"lights":game.structures.resident_lights.statistics()})
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(label+".png"))
		repeat_light_setters=false;process_frame.disconnect(repeat_lights)
	if "--trace-save" in OS.get_cmdline_user_args():
		label="save_during_play"
		if trace!=null:trace.mark("explicit normal save during gameplay")
		manual_save.requested=true
		var saved_callback:Callable=func(success:bool):manual_save.completed=true;manual_save.success=success
		game.terrain.save_completed.connect(saved_callback,CONNECT_ONE_SHOT)
		game.terrain.changed_since_save=true;game.terrain.save_world()
		await wait_for(func():return manual_save.completed,20)
	label="turning"
	var turn_started:=Time.get_ticks_msec()
	var deadline:=turn_started+(5000 if short else 30000)
	while Time.get_ticks_msec()<deadline:
		game.app_focused=true;game.yaw=initial_yaw+(Time.get_ticks_msec()-turn_started)*TAU/30000.0
		await process_frame
	label="settled_idle"
	await wait_for(func():return false,5 if short else 15)
	if trace!=null:
		trace.mark("end of fresh-world observation")
		await wait_for(func():return false,3)
	label="test_screenshot"
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("arrival.png"))
	RenderingServer.frame_post_draw.disconnect(frame)
	var record:Dictionary={"slot":slot,"samples":samples,"trace_enabled":trace!=null,"position":game.player.position,"temporary":game.temporary_world,"snapshot_readonly":game.terrain.backend.readonly_snapshot,"mouse_captures":preload("res://addons/world_runtime/mouse_ownership.gd").captures}
	record.initializations=initializations
	record.last_capture=game.persistence.last_capture.duplicate(true)
	record.manual_save=manual_save.duplicate()
	if light_abba:record.light_phases=light_phases
	if trace!=null:record.trace_files=trace.written;record.trace_overhead_last_us=trace.overhead_us
	FileAccess.open(output.path_join("observation.json"),FileAccess.WRITE).store_string(JSON.stringify(record))
	game.yaw=initial_yaw;game.player.rotation.y=initial_yaw
	game.shutdown_requested=true
	var saved:bool=await game.terrain.shutdown_after_edits()
	game.free();await process_frame;await process_frame
	var okay:bool=saved and record.mouse_captures==0 and (not manual_save.requested or manual_save.completed and manual_save.success)
	print("FRAME_TRACE_WORLD ok=",okay," slot=",slot);quit(0 if okay else 1)

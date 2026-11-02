# SPDX-License-Identifier: 0BSD
extends SceneTree
const Mouse=preload("res://addons/world_runtime/mouse_ownership.gd")
var output:=""
var slot:=""
var phase:="starting"
var last_tick:=0
var samples:Array=[]
var failures:=0
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true)
	node_added.connect(func(node:Node):
		if node.scene_file_path=="res://demo/world.tscn":ProjectSettings.set_setting("terraforest/offscreen_session",true))
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--ui-output="):output=argument.trim_prefix("--ui-output=")
		if argument.begins_with("--ui-slot="):slot=argument.trim_prefix("--ui-slot=")
	run.call_deferred()
func _process(_delta:float)->bool:
	var now:=Time.get_ticks_usec()
	var stage:String=current_scene.startup_stage if is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn" else "resources"
	if last_tick>0:samples.append({"phase":phase,"stage":stage,"ms":(now-last_tick)/1000.0})
	last_tick=now;return false
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func wait_for(predicate:Callable,seconds:float=120)->bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<end:await process_frame
	return predicate.call()
func run()->void:
	if output.is_empty() or not slot.begins_with("Expedition_1703_"):quit(2);return
	var saved:="user://worlds/"+slot+".trw"
	var before:=FileAccess.get_sha256(saved)
	phase="selector";change_scene_to_file("res://demo/worlds.tscn");await scene_changed
	check(await wait_for(func():return not current_scene.library.loading),"selector catalog loads")
	var browser:=current_scene
	phase="preview";browser.world_tabs.current_tab=1
	check(await wait_for(func():return browser.preview_worker==null and browser.preview_view.texture!=null),"generation preview responds and completes")
	var command:Dictionary=preload("res://demo/world_launch.gd").command(slot,false,1,1703,true)
	command.args.append_array(PackedStringArray(["--snapshot-readonly","--no-zombies"]))
	phase="opening";var started:=Time.get_ticks_usec();browser._open_game(command.args)
	var handler_ms:=(Time.get_ticks_usec()-started)/1000.0
	check(handler_ms<100,"open handler acknowledges without waiting: "+str(handler_ms)+" ms")
	check(await wait_for(func():return is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn" and not current_scene.loading_active),"world opens from selector")
	phase="ready";current_scene.player_view.entry.pending=false;current_scene.player_view.refresh_processing()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("loaded.png"))
	var worst:Dictionary={}
	for sample:Dictionary in samples:worst[sample.phase]=maxf(worst.get(sample.phase,0),sample.ms)
	var session:=root.get_node("WorldSession")
	FileAccess.open(output.path_join("latency.json"),FileAccess.WRITE).store_string(JSON.stringify({"max_frame_ms":worst,"handler_ms":handler_ms,"stages":session.get("stage_timings"),"startup":current_scene.get("startup_timings"),"samples":samples},"  "))
	print("UI_LATENCY ",worst)
	current_scene.shutdown_requested=true;await current_scene.terrain.shutdown_after_edits();current_scene.free();await process_frame
	check(FileAccess.get_sha256(saved)==before,"read-only test preserves saved world bytes")
	check(Mouse.captures==0,"test never captures mouse")
	for frame in 3:await process_frame
	print("MENU_TRANSITION failures=",failures);quit(1 if failures else 0)

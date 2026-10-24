# SPDX-License-Identifier: 0BSD
extends SceneTree
const Launch=preload("res://demo/world_launch.gd")
const Options=preload("res://addons/world_runtime/session_options.gd")
var failures:=0
var checks:=0
var original_window:=-1
var original_handle:=0
var windows_stable:=true
var process_id:=OS.get_process_id()
var folder:="res://reports/window_session"
var slots:Array[String]=[]
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label);return ok
func _initialize()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--session-evidence-dir="):folder=argument.trim_prefix("--session-evidence-dir=")
	run.call_deferred()
func _process(_delta:float)->bool:
	if original_window>=0:windows_stable=windows_stable and root.get_window_id()==original_window and DisplayServer.get_window_list().size()==1 and DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,original_window)==original_handle
	return false
func wait_for(predicate:Callable,seconds:int=40)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func browser_ready()->bool:return is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/worlds.tscn"
func game_ready()->bool:return is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn" and not current_scene.loading_active
func photograph(name:String)->void:
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func open_world(slot:String,create:bool,generator:int,seed_value:int,gameplay:bool)->bool:
	var browser=current_scene
	var command:=Launch.command(slot,create,generator,seed_value,gameplay)
	if not command.ok:return false
	command.args.append("--no-zombies")
	browser._open_game(command.args)
	var ready:bool=await wait_for(game_ready,60)
	if not ready:
		print("SESSION_OPEN_DIAGNOSTIC scene=",current_scene," options=",Options.arguments()," transitioning=",root.get_node("WorldSession").transitioning)
		if is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn":print("WORLD_LOADING ",current_scene.loading_stage_text," ",current_scene.loading_work_text," ",current_scene.terrain.latest_error," ",current_scene.terrain.loading_state(current_scene.player.position,current_scene.fly))
	return ready
func leave()->bool:
	current_scene.session_menu.leave_to_browser()
	return await wait_for(browser_ready,40)
func run()->void:
	DirAccess.make_dir_recursive_absolute(folder);original_window=root.get_window_id();original_handle=DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,original_window)
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed
	check(browser_ready(),"world selector opens in original window")
	var slot:="window_flow_"+Crypto.new().generate_random_bytes(8).hex_encode();slots.append(slot)
	if not check(await open_world(slot,true,1,1703,true),"selector opens a new playable world in place"):await finish();return
	var game=current_scene
	check(game.terrain.save_slot==slot and game.terrain.backend.world_generator==1 and game.terrain.backend.world_seed==1703,"session profile reaches terrain worker")
	check(game.construction_inventory.gameplay and game.ground_enabled and game.world_vehicle.fleet_enabled,"gameplay and streamed systems receive session flags")
	game.session_menu.set_open(true);game.session_menu.confirmation.dialog_text="Embedded confirmation";game.session_menu.confirmation.popup_centered()
	await process_frame
	check(game.session_menu.confirmation.is_embedded() and DisplayServer.get_window_list().size()==1,"confirmation dialogs remain inside the game window")
	game.session_menu.confirmation.hide();game.session_menu.set_open(false)
	await photograph("playing")
	var old_game:WeakRef=weakref(game);game=null
	if not check(await leave(),"save and return to selector in the same window"):await finish();return
	await process_frame
	check(old_game.get_ref()==null and not ProjectSettings.has_setting(Options.KEY),"old world is freed and per-session arguments are cleared")
	check(FileAccess.file_exists("user://worlds/"+slot+".trw"),"world save is published before returning")
	if not check(await open_world(slot,false,4,42,false),"saved world reopens without restarting the game"):await finish();return
	check(current_scene.terrain.backend.world_generator==1 and current_scene.terrain.backend.world_seed==1703 and not current_scene.construction_inventory.gameplay,"saved generation identity and newly selected play mode are independent")
	if not check(await leave(),"second return releases save ownership"):await finish();return
	var browser=current_scene
	for index in browser.worlds.item_count:
		if browser.worlds.get_item_metadata(index)==slot:browser.worlds.select(index)
	var digest:=FileAccess.get_sha256("user://worlds/"+slot+".trw")
	browser.refresh_photographs()
	check(browser.photograph_pid==process_id and browser.photograph_job.viewport!=null and browser.photograph_job.viewport.msaa_3d==root.msaa_3d and browser.photograph_job.viewport.size==Vector2i(1920,1080),"photographs render offscreen in the same process at full resolution and matching antialiasing")
	await photograph("photograph_loading")
	if not check(await wait_for(func():return browser.photograph_pid<0,140),"offscreen photograph refresh completes"):await finish();return
	check(browser.notice.text.begins_with("Photographs refreshed") and FileAccess.file_exists("user://worlds/"+slot+".preview/north.png"),"refreshed world pictures are available to selector")
	check(FileAccess.get_sha256("user://worlds/"+slot+".trw")==digest and not ProjectSettings.has_setting(Options.KEY),"read-only photographs preserve save bytes and restore session context")
	browser.refresh_photographs();browser.cancel_photographs()
	check(await wait_for(func():return browser.photograph_pid<0,40) and browser.notice.text.begins_with("Photograph capture cancelled"),"photograph cancellation tears down the offscreen task")
	check(FileAccess.get_sha256("user://worlds/"+slot+".trw")==digest,"cancelled photographs leave saved world unchanged")
	var other:="window_flow_"+Crypto.new().generate_random_bytes(8).hex_encode();slots.append(other)
	if not check(await open_world(other,true,4,42,true),"a different world opens after photography"):await finish();return
	check(current_scene.terrain.save_slot==other and current_scene.terrain.backend.world_generator==4 and current_scene.terrain.backend.world_seed==42 and not current_scene.temporary_world,"slot, seed, generator and readonly flags do not leak across sessions")
	check(await leave(),"different world returns normally")
	check(windows_stable and OS.get_process_id()==process_id,"all transitions retain one native window and the original process")
	await photograph("selector_returned")
	await finish()
func finish()->void:
	if is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn":
		current_scene.shutdown_requested=true;await current_scene.terrain.shutdown_after_edits()
	if is_instance_valid(current_scene):current_scene.free()
	await process_frame
	print("WINDOW_SESSION_FLOW checks=",checks," failures=",failures," slots=",slots)
	quit(1 if failures else 0)

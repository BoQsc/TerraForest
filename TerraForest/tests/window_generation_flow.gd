# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"
func run()->void:
	if folder=="res://reports/window_session":folder="res://reports/window_generation"
	DirAccess.make_dir_recursive_absolute(folder)
	original_window=root.get_window_id();original_handle=DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,original_window)
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed
	var browser=current_scene
	var cancel_slot:="window_cancel_"+Crypto.new().generate_random_bytes(8).hex_encode()
	browser.name_field.text=cancel_slot;browser.seed_field.value=1703;browser.layout_preset.select(2)
	browser.launch_selected(true)
	check(browser.preparation_pid==process_id and browser.preparation_job.task.external_stages==false,"generation coordinator belongs to the visible game process")
	if not check(await wait_for(func():return is_instance_valid(browser.preparation_job.task.local_stage),20),"native generation starts in an offscreen viewport"):await finish();return
	var worker:Node=browser.preparation_job.task.local_stage
	check(worker.viewport!=null and worker.main_window_id==original_window and worker.viewport.msaa_3d==root.msaa_3d,"generation uses a SubViewport with matching antialiasing without a new Window")
	await photograph("generation_cancel_loading")
	browser.cancel_preparation()
	check(await wait_for(func():return browser.preparation_pid<0,70),"active generation cancels and joins its workers")
	check(not FileAccess.file_exists("user://worlds/"+cancel_slot+".trw") and browser_ready(),"cancelled staging never replaces the selector or publishes a world")
	var lease:RefCounted=ClassDB.instantiate("NativeWorldArchive")
	check(lease.acquire(ProjectSettings.globalize_path("user://worlds/"+cancel_slot+".prepare")),"cancellation releases the world destination lease");lease.release()
	check(not ProjectSettings.has_setting(Options.KEY),"cancelled generation restores session options")
	var slot:="window_generated_"+Crypto.new().generate_random_bytes(8).hex_encode();slots.append(slot)
	browser.name_field.text=slot;browser.launch_selected(true)
	var report_path:String=browser.preparation_status
	check(await wait_for(game_ready,600),"Generate and play completes in the original window")
	if not game_ready():
		print("GENERATION_DIAGNOSTIC ",FileAccess.get_file_as_string(report_path));await finish();return
	check(current_scene.terrain.save_slot==slot and current_scene.terrain.backend.world_generator==19 and current_scene.construction_inventory.gameplay,"generated save opens with its saved profile and gameplay mode")
	var status:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(report_path))
	var metadata:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(status.report).path_join("run.json")))
	var local_only:=true
	for phase:Dictionary in metadata.phases:local_only=local_only and phase.mode=="same_window" and phase.pid==process_id
	check(local_only and metadata.phases.size()==1,"production generation spawns no renderer process or verification window")
	await photograph("generated_playing")
	check(await leave(),"generated world saves and returns to selector")
	check(windows_stable and OS.get_process_id()==process_id,"generation, cancellation, play and return retain the same native window handle")
	await photograph("generated_selector")
	await finish()
func finish()->void:
	if is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn":
		current_scene.shutdown_requested=true;await current_scene.terrain.shutdown_after_edits()
	if is_instance_valid(current_scene):current_scene.free()
	await process_frame
	print("WINDOW_GENERATION_FLOW checks=",checks," failures=",failures," slots=",slots)
	quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"
const Policy=preload("res://addons/presentation/fullscreen_policy.gd")
var settings_file:=""
var watch_windowed:=false
var mode_violations:=0
var samples:=0
func _initialize()->void:
	settings_file="user://windowed_stages_"+str(OS.get_process_id())+".cfg"
	ProjectSettings.set_setting("terraforest/graphics_settings_path",settings_file)
	var config:=ConfigFile.new();config.set_value("graphics","fullscreen",false);config.save(settings_file)
	super._initialize()
func _process(delta:float)->bool:
	if watch_windowed:
		samples+=1
		if DisplayServer.window_get_mode() not in [DisplayServer.WINDOW_MODE_WINDOWED,DisplayServer.WINDOW_MODE_MAXIMIZED] or root.borderless:mode_violations+=1
	return super._process(delta)
func f11(echo:bool=false)->void:
	var event:=InputEventKey.new();event.keycode=KEY_F11;event.pressed=true;event.echo=echo;Input.parse_input_event(event)
func ticks()->void:
	for frame in 5:await process_frame
func run()->void:
	if folder=="res://reports/window_session":folder="res://reports/windowed_stages"
	DirAccess.make_dir_recursive_absolute(folder)
	original_window=root.get_window_id();original_handle=DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,original_window)
	Policy.apply(root);await ticks();watch_windowed=true
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed
	check(await wait_for(browser_catalog_ready),"saved windowed preference applies to world browser")
	watch_windowed=false;f11();await ticks()
	check(DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN,"F11 works in browser")
	f11(true);await ticks()
	check(Policy.fullscreen_enabled(),"held F11 does not repeatedly toggle")
	f11();await ticks();watch_windowed=true
	var browser=current_scene
	# Exercise a real generation worker and its loading overlay, then cancel.
	var cancel_slot:="windowed_cancel_"+Crypto.new().generate_random_bytes(8).hex_encode()
	browser.name_field.text=cancel_slot;browser.seed_field.value=1703;browser.settlement_count.select(0);browser.offroads.select(0)
	browser.launch_selected(true)
	check(await wait_for(func():return is_instance_valid(browser.preparation_job.task) and is_instance_valid(browser.preparation_job.task.local_stage),30),"generation starts while main window stays windowed")
	await photograph("generation_windowed")
	browser.cancel_preparation()
	check(await wait_for(func():return browser.preparation_pid<0,80),"generation cancels back to windowed browser")
	check(not FileAccess.file_exists("user://worlds/"+cancel_slot+".trw"),"cancelled generation preserves published saves")
	var slot:="windowed_flow_"+Crypto.new().generate_random_bytes(8).hex_encode();slots.append(slot)
	var command:=Launch.command(slot,true,1,1703,true)
	check("--windowed" in command.args and not "--fullscreen" in command.args,"world launch inherits windowed preference")
	command.args.append_array(PackedStringArray(["--no-zombies","--no-derived-cache"]));browser._open_game(command.args)
	check(root.get_node("WorldSession").transitioning,"world resource loading starts in the same window")
	if not check(await wait_for(game_ready,100),"gameplay opens windowed after loading"):await finish();return
	current_scene.session_menu.set_open(true);current_scene.session_menu.show_page("Graphics")
	check(not current_scene.session_menu.fullscreen_toggle.button_pressed,"Graphics toggle reflects windowed state")
	current_scene.session_menu.confirmation.popup_centered();await ticks()
	check(current_scene.session_menu.confirmation.is_embedded() and DisplayServer.get_window_list().size()==1,"dialogs remain inside windowed host")
	current_scene.session_menu.confirmation.hide()
	watch_windowed=false;f11();await ticks()
	check(current_scene.session_menu.fullscreen_toggle.button_pressed,"F11 updates an already-open Graphics toggle")
	f11();await ticks();watch_windowed=true
	check(not current_scene.session_menu.fullscreen_toggle.button_pressed,"F11 restores open Graphics toggle to windowed")
	watch_windowed=false;current_scene.session_menu.fullscreen_toggle.button_pressed=true;await ticks()
	check(Policy.fullscreen_enabled(),"Graphics toggle enables fullscreen")
	current_scene.session_menu.fullscreen_toggle.button_pressed=false;await ticks();watch_windowed=true
	Policy.apply(root);await ticks()
	check(not Policy.fullscreen_enabled(),"Graphics windowed toggle survives policy reapplication")
	await photograph("gameplay_windowed")
	if not check(await leave(),"save and return retains windowed mode"):await finish();return
	command=Launch.command(slot,false,1,1703,true)
	command.args.append_array(PackedStringArray(["--no-zombies","--no-derived-cache"]))
	current_scene._open_game(command.args)
	if not check(await wait_for(game_ready,100),"saved world reopens windowed"):await finish();return
	check(await leave(),"second return retains windowed mode")
	# Recover an externally overridden stage on focus return.
	watch_windowed=false;root.mode=Window.MODE_FULLSCREEN
	root.focus_entered.emit();await ticks();watch_windowed=true
	check(DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_WINDOWED,DisplayServer.WINDOW_MODE_MAXIMIZED],"focus return restores selected windowed mode")
	Policy.set_fullscreen(root,false,false);Policy.apply(root);await ticks()
	check(not Policy.fullscreen_enabled(),"temporary policy application retains session choice")
	check(mode_violations==0 and samples>30,"every observed browser, generation, loading, gameplay and return frame stays windowed (%d samples, %d violations)"%[samples,mode_violations])
	check(windows_stable,"all stages preserve original native window handle")
	await photograph("browser_returned_windowed")
	await finish()
func finish()->void:
	watch_windowed=false
	DirAccess.remove_absolute(settings_file)
	print("WINDOWED_STAGES checks=",checks," failures=",failures," samples=",samples," violations=",mode_violations)
	await super.finish()

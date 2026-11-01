# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var failures:=0
var checks:=0
var output:="res://reports/entry_fly_in"
var source_path:=""
var source_hash:=""
var record_video:=false
var browser_entry:=false
var movie:Array[Image]=[]
var movie_times:Array[float]=[]
var last_movie_usec:=0
var photos:Dictionary={}
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func wait_for(predicate:Callable,seconds:float=15)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func photo(name:String)->void:
	await RenderingServer.frame_post_draw
	# PNG compression must not stall the very three-second motion under review.
	photos[name]=root.get_texture().get_image()
func key(code:int,pressed:bool=true)->void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
func movie_frame()->void:
	if not is_instance_valid(game) or not game.player_view.entry.active:return
	var now:=Time.get_ticks_usec()
	if now-last_movie_usec<40000:return
	last_movie_usec=now
	var frame:=root.get_texture().get_image();frame.resize(960,540,Image.INTERPOLATE_BILINEAR)
	movie.append(frame);movie_times.append(game.player_view.entry.elapsed)
func browser_world_added(node:Node)->void:
	if node.scene_file_path!="res://demo/world.tscn":return
	game=node;game.player_view.settings_path="";game.background_fps=60
	# Exercise ordinary persistent launch and default eligibility in _ready, then
	# contain OS mouse ownership for the automated renderer after that boundary.
	game.ready.connect(func():ProjectSettings.set_setting("terraforest/offscreen_session",true),CONNECT_ONE_SHOT)
func run()->void:
	var args:=PackedStringArray(["--temporary","--entry-fly-in","--no-zombies","--gameplay-construction","--ground-cover"])
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--entry-output="):output=arg.trim_prefix("--entry-output=")
		elif arg=="--entry-video":record_video=true
		elif arg=="--entry-browser":browser_entry=true
		elif arg.begins_with("--entry-slot="):
			var slot:=arg.trim_prefix("--entry-slot=")
			if not preload("res://demo/world_launch.gd").valid_slot(slot):push_error("Invalid read-only fixture slot");quit(1);return
			source_path="user://worlds/"+slot+".trw"
			args.append("--world-slot="+slot);args.append("--snapshot-readonly")
		elif arg.begins_with("--derived-cache="):args.append(arg)
	if not source_path.is_empty():
		if not FileAccess.file_exists(source_path):push_error("Missing read-only fixture");quit(1);return
		source_hash=FileAccess.get_sha256(source_path)
	preload("res://addons/world_runtime/session_options.gd").set_arguments(args,true)
	DirAccess.make_dir_recursive_absolute(output)
	if browser_entry:
		check(source_path.is_empty(),"ordinary browser check owns a new world instead of using a player save")
		if not source_path.is_empty():quit(1);return
		change_scene_to_file("res://demo/worlds.tscn");await scene_changed
		await wait_for(func():return not current_scene.library.loading,30)
		var slot:="entry_browser_"+Crypto.new().generate_random_bytes(8).hex_encode()
		FileAccess.open(output.path_join("created_slot.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":slot}))
		var command:Dictionary=preload("res://demo/world_launch.gd").command(slot,true,1,1703,true)
		command.args.append("--no-zombies")
		for arg:String in args:if arg.begins_with("--derived-cache="):command.args.append(arg)
		node_added.connect(browser_world_added);current_scene._open_game(command.args)
		if not await wait_for(func():return is_instance_valid(game) and game.is_node_ready(),30):check(false,"browser opened world");quit(1);return
		node_added.disconnect(browser_world_added)
		check(not game.temporary_world and not "--entry-fly-in" in preload("res://addons/world_runtime/session_options.gd").arguments(),"normal browser launches a persistent world without entry diagnostic flags")
	else:
		game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60
		game.player_view.settings_path="";root.add_child(game)
	if record_video:RenderingServer.frame_post_draw.connect(movie_frame)
	var view=game.player_view;var entry=view.entry
	check(entry.enabled and game.session_menu.entry_fly_in_toggle.button_pressed,"fresh preference enables world entry by default")
	check(entry.pending and not entry.active and game.loading_active,"entry waits behind actual world loading")
	if not await wait_for(func():game.app_focused=true;return entry.active or (not entry.pending and not game.loading_active),160):
		check(false,"world and entry became ready: "+game.loading_stage_text);await finish();return
	check(entry.active and not game.needs_floor_spawn and not game.waiting_spawn,"normal world-ready lifecycle starts only after grounded spawn")
	if not entry.active:print("ENTRY_SKIPPED eye=",game.camera.global_position);await finish();return
	var body:Transform3D=game.player.global_transform
	var eye:Transform3D=game.camera.transform
	var collision_focus:Vector3=game.terrain.focus
	var saved:PackedByteArray=game._capture_player_pose()
	var environment:Environment=game.camera.environment if game.camera.environment!=null else game.get_world_3d().environment
	var fog:=environment.fog_density
	var storage:Dictionary=game.structures.blocks.capture_storage_state()
	var start:=Time.get_ticks_usec();var previous:=start;var frames:Array[float]=[]
	check(game.terrain.root_coverage==64 and game.ecosystem.coverage_status().ready,"actual terrain and forest coverage ready before aerial entry")
	check(root.get_camera_3d()==entry.camera and entry.camera.global_position.y-game.camera.global_position.y>900,"real viewport begins high above the player")
	check(game.vegetation.collision_camera==game.camera and game.ecosystem.camera==game.camera and game.ground_cover.camera==game.camera,"aerial view leaves collision and near ecology at the player")
	check(game.tool_view.human.third_person and not game._model_edit_available() and not game._movement_input_available(),"single current player body is visible and world actions are suspended")
	await photo("01_aerial")
	var samples:=0;var invariant:=true
	while entry.active:
		game.app_focused=true
		invariant=invariant and game.player.global_transform.is_equal_approx(body) and game.camera.transform.is_equal_approx(eye) and game.terrain.focus.is_equal_approx(collision_focus) and game._capture_player_pose()==saved
		var now:=Time.get_ticks_usec();frames.append((now-previous)/1000.0);previous=now
		if samples==0 and entry.elapsed>1.15:samples+=1;await photo("02_descent")
		elif samples==1 and entry.elapsed>2.0:samples+=1;await photo("03_approach")
		elif samples==2 and entry.elapsed>2.45:samples+=1;await photo("04_handoff")
		await process_frame
	var seconds:float=(Time.get_ticks_usec()-start)/1000000.0
	check(invariant,"entire flight preserves player, eye, save pose and physical focus")
	check(seconds>=2.85 and seconds<3.65 and is_equal_approx(entry.elapsed,3.0),"fly-in completes in three seconds: %.3f"%seconds)
	check(game.camera.current and not view.active and not game.tool_view.human.third_person and game.tool_view.transform.is_equal_approx(Transform3D.IDENTITY),"exact first-person camera and body transform restored")
	check(game.terrain.render_view==Vector3.INF and game.player_hud.visible and not view.is_processing(),"render focus and HUD restored; idle first person has no camera processing")
	check(game.structures.blocks.capture_storage_state()==storage and environment.fog_density==fog,"fly-in does not hydrate distant buildings or mutate the saved atmosphere")
	check(game.vegetation.camera==game.camera and game.water_camera.camera==game.camera and game.vegetation.renderer.far_distance==game.vegetation.draw_distance,"render and water cameras and normal vegetation distance restored")
	await photo("05_first_person")
	if record_video:
		RenderingServer.frame_post_draw.disconnect(movie_frame)
		for i in movie.size():movie[i].save_png(output.path_join("frame_%03d.png"%i))
		FileAccess.open(output.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify(movie_times))
		movie.clear()
	frames.sort();var report:={"duration_seconds":seconds,"frames":frames.size(),"frame_p95_ms":frames[int((frames.size()-1)*.95)] if not frames.is_empty() else 0,"terrain_roots":game.terrain.root_coverage,"forest_owners":game.ecosystem.resident.size()}
	FileAccess.open(output.path_join("flight.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	# Actual input routing: a skip cannot also jump, swing or capture the pointer.
	var mouse_mode:=Input.mouse_mode
	check(entry.begin(),"entry may start for isolated skip check")
	key(KEY_SPACE);key(KEY_SPACE,false)
	check(not entry.active and game.camera.current and game.controls.direction()==Vector3.ZERO and Input.mouse_mode==mouse_mode,"Space skips without movement or mouse ownership changes")
	entry.begin();key(KEY_ESCAPE);key(KEY_ESCAPE,false)
	check(not entry.active and game.session_menu.opened,"Escape cancels flight and opens the ordinary pause menu")
	game.session_menu.show_page("Player");await photo("06_setting")
	game.session_menu.set_open(false);game.app_focused=true
	entry.begin();game.app_focused=false;entry.step(.016)
	check(not entry.active and game.camera.current,"focus loss returns immediately to first person")
	game.app_focused=true
	# A known physical roof verifies the indoor fallback without modifying a save.
	var roof:=StaticBody3D.new();roof.collision_layer=2;game.add_child(roof)
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(5,.2,5);shape.shape=box;roof.add_child(shape)
	roof.global_position=game.camera.global_position+Vector3.UP*2
	await physics_frame;await physics_frame
	check(not entry.begin() and game.camera.current,"covered indoor spawn skips instead of flying through its roof")
	roof.queue_free();await physics_frame;await physics_frame
	entry.set_enabled(false,false);entry.arm()
	check(not entry.pending and not entry.active,"disabled option bypasses entry on later load")
	entry.set_enabled(true,false)
	if browser_entry:ProjectSettings.set_setting("terraforest/offscreen_session",false)
	entry.arm()
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	check(entry.pending,"enabled option rearms for a later world reload")
	entry.pending=false;view.refresh_processing()
	# Use a unique config, keeping the real user preference untouched.
	var path:="user://entry_check_%d.cfg"%OS.get_process_id();var config:=ConfigFile.new()
	config.set_value("camera","third_person",true);config.save(path)
	view.settings_path=path;ProjectSettings.set_setting("terraforest/offscreen_session",false)
	entry.set_enabled(false);config.load(path)
	check(not config.get_value("camera","entry_fly_in",true) and config.get_value("camera","third_person",false),"preference persists without overwriting third-person choice")
	ProjectSettings.set_setting("terraforest/offscreen_session",true);view.settings_path="";DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	view.set_enabled(true,false);view.update()
	check(view.third_camera.current and view.active,"existing third-person view still works after entry")
	view.set_enabled(false,false);view.set_overview(true)
	check(view.third_camera.current and view.overview,"existing overview still works after entry")
	view.set_overview(false)
	if not source_path.is_empty():check(FileAccess.get_sha256(source_path)==source_hash,"read-only existing world remains byte-for-byte unchanged")
	await finish()
func finish()->void:
	game.player_view.entry.finish();game.shutdown_requested=true
	for name:String in photos:photos[name].save_png(output.path_join(name+".png"))
	photos.clear()
	await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("ENTRY_FLY_IN checks=",checks," failures=",failures);quit(1 if failures else 0)

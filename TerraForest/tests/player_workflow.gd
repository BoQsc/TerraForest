extends SceneTree
class SessionWorld extends "res://demo/world.gd":
	var close_requests:=0
	func _notification(what:int)->void:
		if what==NOTIFICATION_WM_CLOSE_REQUEST:close_requests+=1
		else:super._notification(what)
var game:Node
var failures:=0
var checks:=0
var folder:="res://reports/player_workflow"
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->bool:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
	return ok
func wait_for(predicate:Callable,seconds:int=10)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func key(code:int,down:bool)->void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=down;Input.parse_input_event(event);Input.flush_buffered_events()
func tap(code:int)->void:key(code,true);key(code,false)
func ticks(count:int)->void:
	for frame in count:await physics_frame
func picture(name:String)->void:
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func amount(item:int)->int:
	var count:=0
	for row:Dictionary in game.player_hud.inventory.snapshot().slots:
		if row.item==item:count+=row.count
	return count
func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--workflow-evidence="):folder=argument.trim_prefix("--workflow-evidence=")
	DirAccess.make_dir_recursive_absolute(folder)
	game=SessionWorld.new();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,60),"temporary player world becomes playable"):await finish();return
	game.app_focused=true;game.zombies.population_enabled=false;game.zombies.clear();game.session_menu.set_open(false)
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game._clear_motion();Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	key(KEY_W,true);await ticks(10)
	tap(KEY_M);await ticks(35)
	var start:Vector3=game.player.position
	check(game.world_map.opened and not game.player_hud.inventory_open and not game.session_menu.pauses_world() and game.controls.held.has(KEY_W),"M opens a non-pausing map without discarding held walking input")
	await ticks(35)
	check(game.player.position.distance_to(start)>1.5 and game.world_map.opened,"actual player continues walking while the world map is visible")
	key(KEY_W,false);await ticks(3);start=game.player.position;await ticks(10)
	check(Vector2(game.player.position.x-start.x,game.player.position.z-start.z).length()<.02 and not game.world_attack.attack(),"map key release stops movement and map mouse access cannot attack")
	await picture("map_walking");tap(KEY_M);await ticks(2)
	check(not game.world_map.opened and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"M closes the map and restores mouse look")
	var rig:Skeleton3D=game.tool_view.human.model.find_children("*","Skeleton3D",true,false)[0]
	var hips:int=rig.find_bone("Hips");var standing_hips:float=rig.get_bone_global_pose(hips).origin.y
	key(KEY_CTRL,true);await ticks(15)
	check(game.crouched and absf(game.camera.position.y-1.0)<.01,"Ctrl crouches the real player and lowers the eye")
	game.player_view.set_enabled(true,false);await ticks(12)
	check(game.tool_view.human.active_clip in ["Player_Crouch","Player_Pickaxe_Crouch"] and standing_hips-rig.get_bone_global_pose(hips).origin.y>.6,"third-person crouch visibly lowers the body rather than selecting a standing placeholder clip")
	await picture("third_person_crouch");game.player_view.set_enabled(false,false)
	key(KEY_CTRL,false);await ticks(15)
	check(not game.crouched and absf(game.camera.position.y-1.68)<.01,"Ctrl release stands and restores the eye when unobstructed")
	tap(KEY_ESCAPE);await ticks(2);game.session_menu.show_page("Graphics")
	check(game.session_menu.pages.Graphics.visible,"ESC offers a dedicated Graphics settings page")
	print("GRAPHICS_BEFORE ",JSON.stringify({"pressed":game.session_menu.fullscreen_toggle.button_pressed,"mode":DisplayServer.window_get_mode(),"window_mode":game.get_window().mode}))
	game.session_menu.fullscreen_toggle.button_pressed=false
	check(await wait_for(func():return DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_WINDOWED,DisplayServer.WINDOW_MODE_MAXIMIZED] and not game.get_window().borderless,2),"graphics toggle changes the same game window to decorated windowed mode")
	print("GRAPHICS_AFTER ",JSON.stringify({"pressed":game.session_menu.fullscreen_toggle.button_pressed,"mode":DisplayServer.window_get_mode(),"window_mode":game.get_window().mode}))
	await picture("graphics_windowed")
	game.session_menu.fullscreen_toggle.button_pressed=true;await ticks(3)
	check(DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN,"graphics toggle restores fullscreen without another game process")
	game.session_menu.show_page("Session")
	for button:Button in game.session_menu.pages.Session.find_children("*","Button",true,false):
		if button.text=="Save and quit":button.pressed.emit()
	check(game.close_requests==1 and not game.session_menu.confirmation.visible,"Save and quit requests normal shutdown directly without a confirmation")
	game.session_menu.set_open(false)
	var inventory:PackedByteArray=game.player_hud.inventory.capture_storage_snapshot()
	key(KEY_QUOTELEFT,true)
	check(await wait_for(func():return game.session_menu.player_actions.opened,2),"holding backtick opens the player action wheel")
	await picture("player_actions")
	Input.warp_mouse(root.get_visible_rect().size*.5+Vector2(0,-110))
	await wait_for(func():return game.session_menu.player_actions.choice==0,2)
	print("WHEEL_BEFORE ",JSON.stringify({"opened":game.session_menu.player_actions.opened,"choice":game.session_menu.player_actions.choice,"focused":game.app_focused,"mouse":str(game.session_menu.player_actions.view.get_global_mouse_position()),"size":str(root.get_visible_rect().size)}))
	key(KEY_QUOTELEFT,false);await ticks(2)
	check(game.fly and not game.session_menu.developer and inventory==game.player_hud.inventory.capture_storage_snapshot(),"fly action works in gameplay without switching belts or changing inventory")
	key(KEY_QUOTELEFT,true);await wait_for(func():return game.session_menu.player_actions.opened,2);tap(KEY_ESCAPE);key(KEY_QUOTELEFT,false);await ticks(2)
	check(game.fly and not game.session_menu.player_actions.opened,"ESC cancels the wheel without changing flight")
	game.session_menu.toggle_flight();game._clear_motion()
	game.set_physics_process(false);game.needs_floor_spawn=false
	var feet:Vector3=game.player.global_position
	var floor_hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(feet+Vector3(0,4,-2),feet+Vector3(0,-5,-2),1))
	if not check(not floor_hit.is_empty(),"placement fixture finds real streamed ground"):await finish();return
	game.player_hud.inventory.grant_items(PackedInt64Array([204,4,101,8,211,20]),game.player_hud.inventory.snapshot().revision);game.player_hud.refresh()
	game.camera.look_at(floor_hit.position);game.player_hud.equip_item(204)
	game.ground_preview.remaining=0;game.ground_preview.update(game,.1)
	check(game.ground_preview.visible and game.ground_preview.ghost.mesh!=null,"carried vegetation has an actual species ghost even when a spot is rejected")
	await picture("vegetation_ghost")
	game.player_hud.equip_item(101)
	var matching:=0;var costs_before:=amount(101);var elapsed_us:=0
	for frame in 45:
		game.player.position.x+=.06
		game._prefab_preview_timer=1.0
		var began:=Time.get_ticks_usec();game._update_prefab_preview(1.0/60);elapsed_us+=Time.get_ticks_usec()-began
		var target:Dictionary=game._structure_target(false)
		if not target.is_empty() and game.prefab_preview.visible and game.prefab_preview.position==Vector3(target.target):matching+=1
		await process_frame
	print("PREVIEW_MOTION ",JSON.stringify({"matched_frames":matching,"frames":45,"average_update_us":elapsed_us/45.0}))
	check(matching>=43 and amount(101)==costs_before and game._prefab_preview_material.no_depth_test,"moving block preview updates its exact grid outline without spending items or disappearing into terrain")
	game.player.position=feet;game.camera.global_position=feet+Vector3.UP*1.68;game.camera.look_at(floor_hit.position);game.player_hud.equip_item(211)
	if check(await wait_for(func():return game.terrain_placement.target(game).get("ok",false),5),"continuous terrain fixture begins with a valid carried topsoil target"):
		var before:=amount(211);var started:=Time.get_ticks_msec()
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_RIGHT;event.pressed=true;game._unhandled_input(event)
		var deadline:=Time.get_ticks_msec()+12000
		var distance:=0.0
		while amount(211)>before-2 and Time.get_ticks_msec()<deadline:
			distance+=.0125;game.player.position=feet+Vector3(distance,0,0);game.camera.global_position=game.player.position+Vector3.UP*1.68;game.camera.look_at(floor_hit.position+Vector3(distance,0,0))
			await process_frame
		check(amount(211)<=before-2,"one held right mouse input places consecutive terrain samples without repeated clicking")
		print("HELD_TARGET ",JSON.stringify({"target":game.terrain_placement.target(game),"held":game.terrain_placement.held,"last_cell":str(game.terrain_placement.last_held_cell),"pending":game.terrain.pending_edit}))
		print("HELD_TERRAIN ",JSON.stringify({"spent":before-amount(211),"elapsed_ms":Time.get_ticks_msec()-started}))
		event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_RIGHT;game._input(event)
		await wait_for(func():return not game.terrain.pending_edit,20);await ticks(5)
		var released:=amount(211);await ticks(30)
		check(not game.terrain_placement.held and amount(211)==released,"releasing terrain placement stops further edits and charges")
	check(game.storage.store.snapshot(123).capacity==16,"world chests use sixteen slots rather than a player-sized bag")
	await finish()
func finish()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("PLAYER_WORKFLOW checks=",checks," failures=",failures);quit(1 if failures else 0)

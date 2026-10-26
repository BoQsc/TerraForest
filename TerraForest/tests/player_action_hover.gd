extends SceneTree

var game:Node
var checks:=0
var failures:=0
var samples:Array=[]
var folder:="res://reports/player_action_hover"

func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->bool:
	checks+=1;print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
	return condition
func key(code:int,pressed:bool)->void:
	if code==KEY_QUOTELEFT and not pressed:sample("before-release")
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=pressed;Input.parse_input_event(event);Input.flush_buffered_events()
	if code==KEY_QUOTELEFT and not pressed:sample("after-release")
func sample(label:String)->void:
	var actions:CanvasLayer=game.session_menu.player_actions
	var row:={"phase":label,"cursor":str(root.get_mouse_position()),"center":str(root.get_visible_rect().size*.5),"choice":actions.choice,"opened":actions.opened,"focused":game.app_focused,"held_since":game.session_menu.tilde_down,"mouse_mode":Input.mouse_mode,"available":actions.available(),"fly":game.fly}
	samples.append(row);print("PLAYER_ACTION_STATE ",JSON.stringify(row))
func pointer(point:Vector2)->void:
	Input.warp_mouse(point)
	check(await wait_for(func():return root.get_mouse_position().distance_to(point)<8),"actual cursor reaches the requested wheel region")
	await process_frame
func click(button:int)->void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=pressed;event.position=root.get_mouse_position();event.global_position=event.position;Input.parse_input_event(event);Input.flush_buffered_events()
func wait_for(predicate:Callable,seconds:float=3)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func hold()->bool:
	key(KEY_QUOTELEFT,true)
	return check(await wait_for(func():return game.session_menu.player_actions.opened),"holding backtick opens the actual player action wheel")
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	sample(label)
	check(root.get_texture().get_image().save_png(folder.path_join(label+".png"))==OK,"capture saved: "+label)
func finish()->void:
	if game!=null:
		game.session_menu.player_actions.cancel();await game.terrain.shutdown_after_edits();game.queue_free();await process_frame;await process_frame
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples},"  "))
	print("PLAYER_ACTION_HOVER checks=",checks," failures=",failures);quit(1 if failures else 0)
func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--hover-evidence="):folder=argument.trim_prefix("--hover-evidence=")
	folder=ProjectSettings.globalize_path(folder);DirAccess.make_dir_recursive_absolute(folder)
	if DisplayServer.get_name()=="headless":check(false,"hover regression requires a graphical viewport");await finish();return
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,60),"temporary world is playable"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.zombies.population_enabled=false;game.zombies.clear();game.session_menu.set_open(false)
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.fly=false;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var actions:CanvasLayer=game.session_menu.player_actions
	var inventory:PackedByteArray=game.player_hud.inventory.capture_storage_snapshot()
	if not await hold():await finish();return
	await capture("stationary-center")
	check(root.get_mouse_position().distance_to(root.get_visible_rect().size*.5)<48 and actions.choice==0,"opening selects the Fly action inside the former centre dead zone")
	key(KEY_QUOTELEFT,false)
	if not check(game.fly and not actions.opened and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"stationary release enables flight and restores camera control"):await finish();return
	if not await hold():await finish();return
	key(KEY_QUOTELEFT,false)
	check(not game.fly,"stationary release also returns to walking")
	if not await hold():await finish();return
	await pointer(root.get_visible_rect().size*.5+Vector2(300,0));actions.choice=0;key(KEY_QUOTELEFT,false)
	check(not game.fly and not actions.opened,"release outside the wheel cancels without waiting for another process frame")
	if not await hold():await finish();return
	await pointer(root.get_visible_rect().size*.5+Vector2(300,0));actions._process(0)
	check(actions.choice==-1,"moving outside clears selection")
	await pointer(root.get_visible_rect().size*.5);actions.choice=-1;key(KEY_QUOTELEFT,false)
	check(game.fly,"moving back to the centre and releasing in the same frame selects Fly")
	if not await hold():await finish();return
	click(MOUSE_BUTTON_LEFT);key(KEY_QUOTELEFT,false)
	check(not game.fly and not actions.opened,"clicking the centred Fly action toggles only once")
	if not await hold():await finish();return
	key(KEY_ESCAPE,true);key(KEY_ESCAPE,false);key(KEY_QUOTELEFT,false)
	check(not game.fly and not game.session_menu.opened and not actions.opened,"Escape cancels the wheel without activating flight or opening pause")
	if not await hold():await finish();return
	click(MOUSE_BUTTON_RIGHT);key(KEY_QUOTELEFT,false)
	check(not game.fly and not actions.opened,"right click cancels the selected action")
	if not await hold():await finish();return
	await pointer(root.get_visible_rect().size*.5+Vector2(300,0));actions._process(0)
	key(KEY_F,true);key(KEY_F,false);key(KEY_QUOTELEFT,false)
	check(game.fly and not actions.opened,"keyboard selection still works when the cursor is outside")
	check(not game.session_menu.developer and inventory==game.player_hud.inventory.capture_storage_snapshot(),"Fly actions preserve gameplay mode and inventory")
	game.session_menu.toggle_flight();key(KEY_QUOTELEFT,true);key(KEY_QUOTELEFT,false)
	check(game.session_menu.developer,"a short backtick tap still toggles developer mode")
	await finish()

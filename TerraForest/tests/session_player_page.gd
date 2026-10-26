extends SceneTree

var game:Node
var checks:=0
var failures:=0
var folder:="res://reports/session_player_page"

func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->bool:
	checks+=1;print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
	return condition
func key(pressed:bool)->void:
	var event:=InputEventKey.new();event.physical_keycode=KEY_ESCAPE;event.pressed=pressed;Input.parse_input_event(event);Input.flush_buffered_events()
func capture(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label+".png"))==OK,"capture saved: "+label)
func finish()->void:
	if game!=null:
		game.session_menu.set_open(false);await game.terrain.shutdown_after_edits();game.queue_free();await process_frame;await process_frame
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("SESSION_PLAYER_PAGE checks=",checks," failures=",failures);quit(1 if failures else 0)
func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--player-page-evidence="):folder=argument.trim_prefix("--player-page-evidence=")
	folder=ProjectSettings.globalize_path(folder);DirAccess.make_dir_recursive_absolute(folder)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while (game.loading_active or game.needs_floor_spawn) and Time.get_ticks_msec()<deadline:await process_frame
	if not check(not game.loading_active and not game.needs_floor_spawn,"temporary world is playable"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.zombies.population_enabled=false;game.zombies.clear()
	var menu:CanvasLayer=game.session_menu;menu.set_open(true)
	check(menu.current_page=="Session" and menu.pages.Session.visible,"ESC menu still opens on Session")
	if not check(menu.navigation.has("Player") and menu.pages.has("Player"),"Player has a dedicated sidebar entry and page"):await finish();return
	check(menu.pages.Session.find_children("*","CheckButton",true,false).is_empty(),"Session no longer contains the two player switches")
	menu.navigation.Player.pressed.emit()
	check(menu.current_page=="Player" and menu.pages.Player.visible and not menu.pages.Session.visible,"Player navigation opens only the Player page")
	check(menu.pages.Player.find_children("*","CheckButton",true,false).size()==2,"Player contains exactly the two moved switches")
	check(menu.third_person_toggle.get_parent()==menu.pages.Player,"third-person switch belongs to Player")
	var grid:Node=menu.pages.Player.get_node_or_null("BuildingGridFit")
	if not check(grid!=null,"building-grid preference and explanation move together"):await finish();return
	var burial:CheckButton=grid.find_children("*","CheckButton",true,false)[0]
	var camera_before:bool=game.player_view.enabled
	menu.third_person_toggle.button_pressed=not camera_before
	check(game.player_view.enabled==not camera_before and game.player_view.active==not camera_before,"moved camera switch still changes the actual player view")
	menu.third_person_toggle.button_pressed=camera_before
	check(game.player_view.enabled==camera_before,"camera switch restores its original state")
	var embedding_before:bool=game.prefer_block_burial
	burial.button_pressed=not embedding_before
	check(game.prefer_block_burial==not embedding_before,"moved embedding switch still updates placement preference")
	burial.button_pressed=embedding_before
	check(game.prefer_block_burial==embedding_before,"embedding switch restores its original state")
	await capture("player")
	menu.navigation.Session.pressed.emit()
	var actions:Array[String]=[]
	for control:Button in menu.pages.Session.find_children("*","Button",true,false):actions.append(control.text)
	check("Save world" in actions and "Load saved world" in actions and "Save and quit" in actions,"Session retains save, load and quit actions")
	check(menu.current_page=="Session" and not menu.pages.Player.visible,"Session navigation hides Player settings")
	await capture("session")
	menu.navigation.Player.pressed.emit();key(true);key(false)
	check(not menu.opened and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"ESC closes Player settings and returns camera control")
	key(true);key(false)
	check(menu.opened and menu.current_page=="Session","fresh ESC still returns to Session")
	await finish()

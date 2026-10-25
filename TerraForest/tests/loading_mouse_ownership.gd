extends SceneTree

const Options=preload("res://addons/world_runtime/session_options.gd")
const Mouse=preload("res://addons/world_runtime/mouse_ownership.gd")
var checks:=0
var failures:=0
var game:Node
var background:SubViewport

func _initialize()->void:run.call_deferred()

func check(condition:bool,label:String)->void:
	checks+=1
	if not condition:failures+=1
	print("PASS " if condition else "FAIL ",label)

func run()->void:
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	background=SubViewport.new();background.size=Vector2i(640,360)
	background.own_world_3d=true;background.gui_disable_input=true;root.add_child(background)
	Options.set_arguments(OS.get_cmdline_user_args(),true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60
	background.add_child(game)
	var deadline:=Time.get_ticks_msec()+90000
	while game.loading_active and game.terrain.latest_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active and game.terrain.latest_error.is_empty(),"hidden photograph world becomes ready")
	if game.loading_active:await finish();return
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"hidden world finishing loading cannot capture the main cursor")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var cursor:=Vector2(180,140)
	Input.warp_mouse(cursor);await process_frame
	cursor=root.get_mouse_position()
	game.world_map.set_open(true);game.world_map.set_open(false)
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"hidden map preparation cannot capture the main cursor")
	game.session_menu.set_open(true);game.session_menu.set_open(false)
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"hidden menu cleanup cannot capture the main cursor")
	game.player_hud.enabled=true;game.player_hud.set_open(true);game.player_hud.set_open(false)
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"hidden inventory cleanup cannot capture the main cursor")
	check(root.get_mouse_position().distance_to(cursor)<2,"hidden preparation leaves the visible cursor at its original position")
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	game._begin_loading("Hidden camera destination")
	check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"background loading cannot release another scene's captured cursor")
	game.session_menu.set_open(true)
	check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"background menu cannot release another scene's captured cursor")
	check(DisplayServer.get_window_list().size()==1,"background world owns no additional operating-system window")
	check(Mouse.captures==0 and Mouse.mode_changes==0,"background world makes zero global mouse-mode changes")
	var owner:=Node.new();root.add_child(owner)
	Mouse.set_mode(owner,Input.MOUSE_MODE_VISIBLE)
	var changes:=Mouse.mode_changes
	for attempt in 5:Mouse.set_mode(owner,Input.MOUSE_MODE_CAPTURED)
	check(Mouse.captures==1 and Mouse.mode_changes==changes+1,"repeated foreground capture requests apply only one real transition")
	Mouse.set_mode(owner,Input.MOUSE_MODE_VISIBLE);owner.free()
	await finish()

func finish()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits()
	background.free();Options.reset();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await process_frame
	print("LOADING_MOUSE_OWNERSHIP checks=",checks," failures=",failures)
	quit(1 if failures else 0)

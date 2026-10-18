# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func key(code: int,pressed: bool) -> void:
	var e:=InputEventKey.new();e.physical_keycode=code;e.pressed=pressed;Input.parse_input_event(e);Input.flush_buffered_events()
func tap(code: int) -> void:key(code,true);key(code,false)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.ground_enabled=true;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+45000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"world ready")
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	if game.session_menu.developer:game.session_menu.toggle_developer()
	var hud=game.player_hud;hud.equip(1)
	var before: PackedByteArray=hud.capture_snapshot()
	key(KEY_W,true);tap(KEY_QUOTELEFT)
	check(hud.developer_belt and game.session_menu.developer and hud.belt[0].text.contains("Sculpt sphere"),"tilde replaces gameplay items with development belt")
	check(game.controls.direction()!=Vector3.ZERO,"mode switch preserves held movement")
	for pair in [[KEY_1,3],[KEY_2,2],[KEY_3,1]]:
		tap(pair[0]);check(game.editor_tool_active and game.tool==pair[1] and game.equipped_tool==0,"dev number selects editor brush "+str(pair[1]))
	tap(KEY_4);check(game.structure_mode and not game.model_tool.active and game.editor_tool_active,"development block tool")
	tap(KEY_5);check(game.model_tool.active and game.editor_tool_active,"development object tool")
	tap(KEY_6);check(game.ground_mode and game.editor_tool_active,"development vegetation tool")
	tap(KEY_7);check(not game.session_menu.visible_ui() and hud.developer_slot==6,"road slot selects without interrupting movement")
	tap(KEY_ESCAPE);check(game.session_menu.workspace and game.session_menu.current_page=="Roads","Escape configures selected road tool")
	game.session_menu.set_open(false);tap(KEY_8);check(not game.session_menu.visible_ui() and hud.developer_slot==7,"world tools select without opening a modal")
	tap(KEY_ESCAPE);check(game.session_menu.current_page=="Development" and game.session_menu.opened,"Escape opens selected world settings")
	game.session_menu.set_open(false);tap(KEY_0)
	var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;Input.parse_input_event(wheel);Input.flush_buffered_events()
	check(hud.developer_slot==0 and game.tool==3 and game.editor_tool_active,"wheel wraps development slots")
	hud.set_open(true)
	check(hud.drag_data("player",0).is_empty() and not hud.accepts_drag("player",0,{"owner":hud.get_instance_id()}),"dev tools cannot be dragged into inventory or overwritten with items")
	hud.set_open(false);tap(KEY_2)
	DirAccess.make_dir_recursive_absolute("res://reports/developer_belt")
	for i in 4:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/developer_belt/development.png")
	tap(KEY_QUOTELEFT)
	check(not hud.developer_belt and hud.active_slot==1 and game.equipped_tool==2 and hud.belt[0].item_label.text=="Pickaxe","leaving dev restores gameplay belt and previously selected item")
	check(hud.capture_snapshot()==before,"editor actions do not mutate carried inventory")
	tap(KEY_QUOTELEFT);check(hud.developer_slot==1 and game.tool==2,"returning to dev restores its previous selection")
	tap(KEY_QUOTELEFT);key(KEY_W,false)
	for i in 4:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/developer_belt/gameplay.png")
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"clean shutdown")
	game.free();await process_frame;await process_frame
	print("DEVELOPER_BELT checks=",checks," failures=",failures);quit(1 if failures else 0)

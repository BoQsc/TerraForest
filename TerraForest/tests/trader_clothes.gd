# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"

func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true)
	node_added.connect(func(node:Node):
		if node.scene_file_path=="res://demo/world.tscn":ProjectSettings.set_setting("terraforest/offscreen_session",true))
	super._initialize()

func appearance(game:Node)->Node:
	for child in game.trader.actor.get_children():
		if child.get_script()==preload("res://addons/characters/runtime/human_view.gd"):return child
	return null

func run()->void:
	var receipt:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("world.json")))
	if not check(str(receipt.slot).begins_with("TraderClothes_"),"only an owned copy of a generated fixture can be opened"):await finish();return
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed;await wait_for(browser_catalog_ready)
	if not check(await open_world(receipt.slot,false,1,1703,true),"existing generated world opens normally"):await finish();return
	var game:=current_scene;game.background_fps=30;game.app_focused=true;game.set_physics_process(false);game._clear_motion()
	var point:=Vector3.INF
	for place:Dictionary in game.generated_region.store.get_plan().get("places",[]):
		if place.id==game.trader.PLACE:point=place.position;break
	if not check(point.is_finite(),"retained generated plan contains the resident trader"):await finish();return
	var stock:PackedByteArray=game.trader.trader.stock.capture_storage_snapshot()
	var inventory:PackedByteArray=game.player_hud.inventory.capture_storage_snapshot()
	game.teleport(point+Vector3(0,0,1.6))
	if not check(await wait_for(func():return not game.loading_active and is_instance_valid(game.trader.actor),90),"real collision residency admits the trader"):await finish();return
	var human:=appearance(game)
	check(human!=null and human.clothing.worn==PackedInt32Array([301,302,303]),"resident trader wears the approved full woven outfit")
	for id in [301,302,303]:check(human.clothing.garments[id].is_visible_in_tree(),"trader displays garment %d"%id)
	check(human.animation_player.is_playing(),"trader retains authored idle animation")
	var reachable:=false
	for offset in [Vector3(0,0,1.6),Vector3(0,0,-1.6),Vector3(1.6,0,0),Vector3(-1.6,0,0)]:
		game.player.global_position=point+offset;game.camera.position=Vector3(0,1.65,0);game.camera.look_at(point+Vector3.UP*1.45)
		for i in 5:await physics_frame
		game.app_focused=true
		if game.trader.reachable():reachable=true;break
	check(reachable,"dressed trader remains reachable through the actual scene ray")
	await photograph("trader-woven")
	check(game.trader.try_open({"collider":game.trader.actor}),"ordinary interaction still opens the finite-stock shop")
	game.trader.ui.close()
	var original:WeakRef=weakref(game.trader.actor)
	game.player.global_position=point+Vector3(100,0,0)
	check(await wait_for(func():return not is_instance_valid(game.trader.actor),10),"distant trader visual retires")
	game.player.global_position=point+Vector3(0,0,1.6)
	check(await wait_for(func():return is_instance_valid(game.trader.actor),20),"return recreates the resident trader")
	check(original.get_ref()==null and appearance(game).clothing.worn==PackedInt32Array([301,302,303]),"new trader instance restores its role outfit")
	check(game.trader.trader.stock.capture_storage_snapshot()==stock and game.player_hud.inventory.capture_storage_snapshot()==inventory,"appearance, interaction and streaming do not consume or refill inventory")
	await finish()

func finish()->void:
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED and preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"review never captures the pointer")
	if game_ready():
		current_scene.shutdown_requested=true;check(await current_scene.terrain.shutdown_after_edits(),"owned copied fixture closes durably")
	if is_instance_valid(current_scene):current_scene.free()
	print("TRADER_CLOTHES checks=",checks," failures=",failures);quit(1 if failures else 0)

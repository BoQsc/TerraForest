# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"
var slot:=""
var restoring:=false
var outfit:=PackedInt32Array([301,302,303])
var fibre_cost:=9
var recipes:=[4,5,6]

func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true)
	node_added.connect(func(node:Node):
		if node.scene_file_path=="res://demo/world.tscn":ProjectSettings.set_setting("terraforest/offscreen_session",true))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--woven-slot="):slot=argument.trim_prefix("--woven-slot=")
		restoring=restoring or argument=="--restore"
		if argument=="--trail":outfit=PackedInt32Array([304,305,306]);fibre_cost=14;recipes=[15,16,17]
	super._initialize()

func run()->void:
	if not check(slot.begins_with("Woven_") and slot.length()<48,"only a dedicated clothing fixture can be opened"):await finish();return
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed;await wait_for(browser_catalog_ready)
	if not check(await open_world(slot,not restoring,1,1703,true),"ordinary world entry reaches gameplay"):await finish();return
	var game:=current_scene;game.background_fps=30;game.app_focused=true;game.set_physics_process(false);game._clear_motion()
	var hud:Node=game.player_hud
	if not restoring:
		check(hud.inventory.grant_items(PackedInt64Array([204,fibre_cost]),hud.inventory.snapshot().revision).ok,"fixture supplies recipe fibres")
		for recipe in recipes:check(preload("res://addons/player_runtime/crafting.gd").craft(hud.inventory,recipe,1,hud.inventory.snapshot().revision).ok,"paid recipe crafts %d"%recipe)
		hud.refresh();hud.set_open(true);hud.show_side("Character")
		for id in outfit:
			var source:=-1
			for i in 32:
				if hud.inventory.snapshot().slots[i].item==id:source=i;break
			if not check(source>=0,"crafted item is in the backpack"):await finish();return
			hud.character_panel.drop_stack("equipment",preload("res://addons/characters/wearables/clothing.gd").SLOTS[id],hud.drag_data("player",source))
	check(game.tool_view.human.clothing.worn==outfit,"production player_view binding presents equipped clothes after "+("fresh-process restore" if restoring else "craft/equip"))
	hud.set_open(true);hud.show_side("Character")
	for i in 6:await process_frame
	check(hud.character_panel.clothing.worn==game.tool_view.human.clothing.worn,"world portrait and animated player agree")
	await photograph("world-character")
	hud.set_open(false);game.player_view.set_enabled(true,false)
	for i in 5:await process_frame
	check(game.player_view.active and game.tool_view.human.clothing.garments[outfit[0]].visible,"actual third-person camera includes hood")
	await photograph("world-third-person")
	game.player_view.set_enabled(false,false)
	check(not game.tool_view.human.clothing.garments[outfit[0]].visible,"return to first person hides hood")
	check(await leave(),"normal save and return publishes owned fixture")
	await finish()

func finish()->void:
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED and preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"world review never captures the pointer")
	if game_ready():
		current_scene.shutdown_requested=true;await current_scene.terrain.shutdown_after_edits()
	if is_instance_valid(current_scene):current_scene.free()
	print("WOVEN_CLOTHES_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)

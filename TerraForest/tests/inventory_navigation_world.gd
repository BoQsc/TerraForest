# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"
var game:Node
func press(keycode:int)->void:
	var event:=InputEventKey.new();event.physical_keycode=keycode;event.pressed=true;root.push_input(event,true);await process_frame
	event=InputEventKey.new();event.physical_keycode=keycode;event.pressed=false;root.push_input(event,true);await process_frame
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true)
	node_added.connect(func(node:Node):
		if node.scene_file_path=="res://demo/world.tscn":ProjectSettings.set_setting("terraforest/offscreen_session",true))
	super._initialize()
func run()->void:
	var receipt:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("world.json")))
	if not check(str(receipt.slot).begins_with("Survival_"),"only owned generated survival fixture is opened"):await finish();return
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed;await wait_for(browser_catalog_ready)
	var browser=current_scene;var selected:=-1
	for index in browser.worlds.item_count:
		if browser.worlds.get_item_metadata(index)==receipt.slot:selected=index;break
	if not check(selected>=0,"ordinary selector lists fixture"):await finish();return
	browser.worlds.select(selected);browser.launch_selected(false)
	if not check(await wait_for(game_ready,100),"normal loading reaches gameplay"):await finish();return
	game=current_scene;game.background_fps=60;game.app_focused=true;game.set_physics_process(false);game._clear_motion();game.zombies.update(0,game.player.global_position,false)
	var hud:Node=game.player_hud
	var inventory:PackedByteArray=hud.inventory.capture_storage_snapshot();var equipment:PackedByteArray=hud.equipment.capture_storage_snapshot()
	hud.set_open(true)
	check(not game._movement_input_available(),"inventory owns movement independently of cursor capture")
	var before:=Time.get_ticks_usec();hud.show_side("Character");print("WORLD_PORTRAIT_BUILD_US ",Time.get_ticks_usec()-before)
	for frame in 6:await process_frame
	var portrait:Control=hud.character_panel.portrait
	check(portrait.model_resource==game.tool_view.human.MODEL,"portrait shares the actual current player model resource")
	check(portrait.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"portrait stops rendering after its requested view")
	await photograph("character-world")
	portrait.rotate_view(-1)
	for frame in 3:await process_frame
	await photograph("character-rotated")
	hud.show_side("Map")
	for frame in 5:await process_frame
	check(game.world_map.opened and game.world_map.embedded and hud.inventory_open and hud.enabled and hud.modal.visible,"Map tab preserves one navigation owner and visible top bar")
	check(not hud.backpack_panel.visible and not hud.crafting_panel.visible and not game.world_map.close_button.visible,"embedded map replaces content without duplicate close buttons")
	check(game.world_map.destination_picker.visible and game.world_map.destination_picker.item_count==game.world_map.places.size() and not game.world_map.destination_scroll.visible,"compact map retains every public destination without a clipped scroll list")
	check(game.world_map.texture!=null and game.world_map.view.size.x>=1000 and game.world_map.panel.size.x<=1480 and game.world_map.panel.size.y<=650,"actual generated map is reused within inventory content bounds")
	check(not game._movement_input_available(),"inventory Map tab does not move the player behind the menu")
	await photograph("inventory-map")
	var center:Vector2=game.world_map.view.get_global_rect().get_center();var pixel:Color=root.get_texture().get_image().get_pixel(int(center.x),int(center.y))
	check(pixel.g>.25,"first embedded map actually draws its centered player marker rather than a blank cached canvas")
	var renders:int=portrait.renders
	hud.show_side("Skills");check(not game.world_map.opened and hud.inventory_open and hud.skills_panel.visible,"Skills closes embedded map without closing inventory")
	hud.show_side("Journal");check(hud.journal_panel.visible and hud.journal_panel.choices.item_count>0,"actual saved reading history remains accessible")
	await photograph("inventory-journal")
	hud.show_side("Map")
	await press(KEY_ESCAPE)
	check(not game.world_map.opened and not hud.inventory_open and not game.session_menu.visible_ui(),"first Escape closes embedded map and inventory, not opening ESC menu")
	await press(KEY_ESCAPE)
	check(game.session_menu.opened,"next Escape opens ESC only after other UI has closed")
	await press(KEY_ESCAPE)
	await press(KEY_M)
	check(game.world_map.opened and not game.world_map.embedded and not hud.inventory_open and game._movement_input_available(),"standalone M map still permits movement as requested")
	await photograph("standalone-map")
	await press(KEY_M);hud.set_open(true);hud.show_side("Character")
	for frame in 3:await process_frame
	check(portrait.renders==renders+1 and portrait.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"returning to Character reuses its bounded cached scene")
	check(hud.inventory.capture_storage_snapshot()==inventory and hud.equipment.capture_storage_snapshot()==equipment,"navigation never moves or consumes carried or equipped items")
	hud.set_open(false)
	await finish()
func finish()->void:
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED and preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"world checks never capture or reposition desktop pointer")
	if game_ready():
		current_scene.shutdown_requested=true;check(await current_scene.terrain.shutdown_after_edits(),"owned test world closes durably")
	if is_instance_valid(current_scene):current_scene.free()
	print("INVENTORY_NAVIGATION_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)

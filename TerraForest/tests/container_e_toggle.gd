extends "res://tests/combined_resource_route.gd"

func press(code:Key,echoed:bool=false)->void:
	game.app_focused=true
	var event:=InputEventKey.new();event.physical_keycode=code;event.keycode=code;event.pressed=true;event.echo=echoed
	Input.parse_input_event(event);Input.flush_buffered_events()
	await process_frame

func release(code:Key)->void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.keycode=code
	Input.parse_input_event(event);Input.flush_buffered_events()
	await process_frame

func picture(name:String)->void:
	await RenderingServer.frame_post_draw
	var folder:=ProjectSettings.globalize_path("res://reports/interaction_workflow")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(name+".png"))==OK,"workflow evidence saved: "+name)

func exercise(ui:CanvasLayer,label:String)->void:
	await press(KEY_E)
	check(ui.opened and game.player_hud.inventory_open and not game.player_hud.enabled,"E opens "+label)
	var visible_slots:=0
	for index in ui.player_list.buttons.size():
		if ui.player_list.buttons[index].visible:visible_slots+=1
		if index<10:check(not ui.player_list.buttons[index].visible,"%s inventory excludes belt slot %d"%[label,index])
	check(visible_slots==22,"%s shows exactly 22 backpack slots"%label)
	if label=="corpse loot":await picture("corpse-open")
	await press(KEY_E,true)
	check(ui.opened,"held E does not immediately close "+label)
	await release(KEY_E)
	check(ui.opened,"E release leaves "+label+" open")
	ui.quantity.get_line_edit().grab_focus()
	var before:PackedByteArray=game.player_hud.capture_snapshot()
	await press(KEY_E)
	check(not ui.opened and not game.player_hud.inventory_open and game.player_hud.enabled,"second E closes "+label+" and restores gameplay HUD")
	check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"closing "+label+" restores camera capture")
	check(game.player_hud.capture_snapshot()==before,"closing "+label+" does not move inventory items")
	if label=="corpse loot":await picture("corpse-closed-with-e")
	await release(KEY_E)
	for frame in 3:await process_frame
	check(not ui.opened,"close input is consumed instead of reopening "+label)
	await press(KEY_E);await release(KEY_E)
	check(ui.opened,"fresh E can reopen "+label)
	await press(KEY_TAB);await release(KEY_TAB)
	check(not ui.opened and not game.player_hud.inventory_open,"Tab close remains available for "+label)

func run()->void:
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"temporary world loads"):await finish();return
	game.set_physics_process(false);game._clear_motion()
	var origin:Vector3=game.player.position+Vector3(0,8,-3)
	var chest:Node3D=game.storage.collection
	var identity:int=chest.insert_instance(game.model_tool.records(Transform3D(Basis.IDENTITY,origin),chest),AABB())
	if not check(identity>0,"actual chest inserted"):await finish();return
	chest.set_collision_focus(origin)
	aim(origin+Vector3(0,0.05,2),origin+Vector3(0,0.4,0))
	for frame in 12:await physics_frame;await process_frame
	await exercise(game.storage,"chest")
	chest.remove_instances(PackedInt64Array([identity]))
	for frame in 12:await physics_frame;await process_frame
	var corpse:int=game.corpse_loot.store.create_corpse(origin,0,1703)
	if not check(corpse>0,"native corpse loot fixture created"):await finish();return
	var original_picker:Callable=game.corpse_loot.ui.external_picker
	game.corpse_loot.ui.external_picker=func(_hit:Variant=null)->int:return corpse
	await exercise(game.corpse_loot.ui,"corpse loot")
	game.corpse_loot.ui.external_picker=original_picker
	await finish()

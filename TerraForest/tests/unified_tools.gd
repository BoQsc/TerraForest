# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func drag(source: Control,target: Control) -> void:
	var start:=source.get_global_rect().get_center();var end:=target.get_global_rect().get_center()
	Input.warp_mouse(start)
	var motion:=InputEventMouseMotion.new();motion.position=start;motion.global_position=start;Input.parse_input_event(motion)
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=start;click.global_position=start;Input.parse_input_event(click)
	for i in 2:await process_frame
	motion=InputEventMouseMotion.new();motion.position=start+Vector2(25,0);motion.global_position=motion.position;motion.relative=Vector2(25,0);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(motion)
	for i in 2:await process_frame
	motion=InputEventMouseMotion.new();motion.position=end;motion.global_position=end;motion.relative=end-start;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(motion)
	for i in 2:await process_frame
	click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=false;click.position=end;click.global_position=end;Input.parse_input_event(click)
	for i in 3:await process_frame
func click_control(control: Control) -> void:
	await RenderingServer.frame_post_draw
	var point:=control.get_global_rect().get_center();Input.warp_mouse(point)
	await RenderingServer.frame_post_draw
	var received: Array=[]
	var down:=func():received.append("down")
	var up:=func():received.append("up")
	control.button_down.connect(down);control.button_up.connect(up)
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;Input.parse_input_event(motion)
	var mouse:=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.button_mask=MOUSE_BUTTON_MASK_LEFT;mouse.position=point;mouse.global_position=point;mouse.pressed=true;Input.parse_input_event(mouse);Input.flush_buffered_events()
	await RenderingServer.frame_post_draw
	mouse=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.position=point;mouse.global_position=point;mouse.pressed=false;Input.parse_input_event(mouse);Input.flush_buffered_events()
	await RenderingServer.frame_post_draw
	control.button_down.disconnect(down);control.button_up.disconnect(up)
	print("GUI_CLICK ",control.text," ",point," ",received)
func key(code: int) -> void:
	var event:=InputEventKey.new();event.pressed=true;event.physical_keycode=code;Input.parse_input_event(event)
	event=InputEventKey.new();event.physical_keycode=code;Input.parse_input_event(event)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"main world ready")
	game.set_physics_process(false);game._clear_motion();game.app_focused=true
	var base: Vector3i=Vector3i(game.player.position.snapped(Vector3.ONE))+Vector3i(0,12,0)
	game.player.position=Vector3(base)+Vector3(12,1,12);game.needs_floor_spawn=false
	var inv: RefCounted=game.player_hud.inventory
	check(inv.grant_items(PackedInt64Array([101,5000,102,5000,103,5000,104,5000]),inv.snapshot().revision).ok,"supply paid interior fixture")
	var asset: Resource=game.structure_prefabs[4]
	check(asset.get_model_attachments().size()==4,"normal palette furnished cottage includes chest")
	check(game._place_combined_prefab(asset,base,0),"normal paid prefab route places furnished storage interior")
	var target:=Vector3(base)+Vector3(2.5,1,0)
	game.player.position=target+Vector3(0,0.05,1.6);game.fly=false
	game.structures.set_model_focus(target);game.structures.blocks.set_focus(target)
	for i in 60:await physics_frame
	game.camera.global_position=target+Vector3(0,1.67,1.6);game.camera.look_at(target+Vector3(0,0.4,0))
	game._set_player_tool_mode(false,false,1);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for i in 5:await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://reports/unified_tools")
	root.get_texture().get_image().save_png("res://reports/unified_tools/exterior.png")
	var event:=InputEventKey.new();event.pressed=true;event.physical_keycode=KEY_E;game._unhandled_input(event)
	check(game.storage.opened,"E reaches chest inside furnished cottage")
	if game.storage.opened:
		var original_chest_slots:Array=game.storage.store.snapshot(game.storage.identity).slots
		var slot:=-1
		for i in 32:
			if inv.snapshot().slots[i].item==102:slot=i
		game.storage.player_list.select(slot);game.storage.quantity.get_line_edit().text="2"
		check(game.storage.move_selected(true),"interior chest accepts wood through normal UI")
		for i in 5:await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/unified_tools/open.png")
		# Supply grants may fill slot 28. This case tests withdrawal to an empty slot;
		# occupied-slot swaps are a different interaction.
		var target_stack:Dictionary=inv.snapshot().slots[28]
		if target_stack.count>0:check(inv.consume(28,target_stack.count,inv.snapshot().revision).ok,"empty supplied fixture target before withdrawal")
		game.storage.refresh()
		await drag(game.storage.storage_list.buttons[0],game.storage.player_list.buttons[28])
		check(inv.snapshot().slots[28].count==2 and game.storage.store.snapshot(game.storage.identity).slots==original_chest_slots,"real mouse drag withdraws to exact player slot and preserves original chest supplies")
		await drag(game.storage.player_list.buttons[28],game.storage.storage_list.buttons[31])
		check(game.storage.store.snapshot(game.storage.identity).slots[31].count==2 and game.storage.collection.is_removal_protected(game.storage.identity),"real mouse drag deposits to exact chest slot and protects contents")
		await drag(game.storage.storage_list.buttons[31],game.storage.storage_list.buttons[30])
		check(game.storage.store.snapshot(game.storage.identity).slots[30].count==2,"real mouse drag rearranges chest slots")
		var shift:=InputEventKey.new();shift.physical_keycode=KEY_SHIFT;shift.keycode=KEY_SHIFT;shift.pressed=true;Input.parse_input_event(shift)
		await process_frame
		await drag(game.storage.storage_list.buttons[30],game.storage.player_list.buttons[29])
		shift=InputEventKey.new();shift.physical_keycode=KEY_SHIFT;shift.keycode=KEY_SHIFT;Input.parse_input_event(shift)
		await process_frame
		check(inv.snapshot().slots[29].count==1 and game.storage.store.snapshot(game.storage.identity).slots[30].count==1,"real Shift-drag splits chest stack in half")
		key(KEY_ESCAPE);await process_frame
		check(not game.storage.opened and not game.session_menu.opened,"Escape closes chest before opening menu")
	key(KEY_ESCAPE);await process_frame
	check(game.session_menu.opened and game.player_hud.inventory_open and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"Escape menu owns input and releases cursor")
	for i in 3:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/unified_tools/menu.png")
	key(KEY_QUOTELEFT);await process_frame
	check(game.session_menu.developer and not game.construction_inventory.gameplay and not game.mining_rewards.enabled,"development mode enables free authoring without mining rewards")
	game.session_menu.open_tool_page("World tools");game.session_menu.tool_workspace.fly_button.pressed.emit();check(game.fly,"world tool flight button works outside session")
	for i in 3:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/unified_tools/developer.png")
	key(KEY_QUOTELEFT);await process_frame
	check(not game.fly and game.construction_inventory.gameplay and game.mining_rewards.enabled,"leaving development restores gameplay and walking")
	var held:=InputEventKey.new();held.physical_keycode=KEY_QUOTELEFT;held.pressed=true;Input.parse_input_event(held)
	await process_frame
	var hold_start:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-hold_start<500:await process_frame
	held=InputEventKey.new();held.physical_keycode=KEY_QUOTELEFT;Input.parse_input_event(held)
	await process_frame
	print("HOLD_STATE ",game.session_menu.developer," ",game.fly," ",game.session_menu.message.text)
	check(game.session_menu.developer and game.fly,"holding tilde enters development and toggles flight")
	key(KEY_QUOTELEFT)
	game.session_menu.set_open(false)
	var carried_slot:int=game.player_hud.active_slot
	game.player_hud.active_slot=-1;game._equip_player_tool(0)
	key(KEY_G);await process_frame;check(not game.fly,"G with empty hands does not enable flight")
	game.player_hud.equip(carried_slot)
	game.player_hud.set_open(true)
	for i in 3:await process_frame
	check(game.player_hud.belt.size()==10,"ten toolbelt slots")
	await drag(game.player_hud.belt[0],game.player_hud.belt[9])
	check(inv.snapshot().slots[9].item==1,"real inventory drag swaps tool into tenth belt slot")
	for i in 3:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/unified_tools/inventory.png")
	game.player_hud.set_open(false)
	var equipped: Array=[];game.player_hud.tool_requested.connect(func(item: int):equipped.append(item))
	key(KEY_0);await process_frame
	check(equipped==[1],"zero key equips tenth belt slot")


	# Empty slots and resources are equipment states, never editor mode selectors.
	check(game.player_hud.CATALOG=={1:"Pickaxe",2:"Hatchet",3:"Repair hammer",4:"Assembly tool",5:"Shovel"},"saved tool IDs stay stable and shovel has its own item ID")
	check(inv.transfer(9,30,1,inv.snapshot().revision).ok,"move equipped pickaxe out of belt")
	game.player_hud.refresh()
	check(game.equipped_tool==0 and game.tool_view.current==0,"moving the equipped tool away puts it down")
	key(KEY_0);await process_frame
	check(game.player_hud.active_slot==9 and game.equipped_tool==0 and not game.structure_mode and not game.model_tool.active,"empty tenth slot selects empty hands and clears placement")
	var material_slot:=-1
	for i in inv.snapshot().slots.size():
		if inv.snapshot().slots[i].item==101:material_slot=i;break
	check(material_slot>=0 and inv.transfer(material_slot,8,inv.snapshot().slots[material_slot].count,inv.snapshot().revision).ok,"put known terrain material stack into empty ninth belt slot")
	key(KEY_9);await process_frame
	check(game.equipped_tool==101 and game.structure_mode and not game.model_tool.active and not game.editor_tool_active,"held building material enables paid right-click placement without developer tools")
	key(KEY_M);await process_frame
	check(game.world_map.opened and not game.model_tool.active,"M opens world map without changing tool mode")
	key(KEY_M);await process_frame
	check(not game.world_map.opened,"M returns from map before editor chords")
	var light_before: bool=game.headlamp.visible
	var chord:=InputEventKey.new();chord.physical_keycode=KEY_QUOTELEFT;chord.pressed=true;Input.parse_input_event(chord);await process_frame
	key(KEY_F);await process_frame
	chord=InputEventKey.new();chord.physical_keycode=KEY_QUOTELEFT;Input.parse_input_event(chord);await process_frame
	check(game.session_menu.developer and game.fly and game.headlamp.visible==light_before,"tilde plus F toggles flight once without toggling headlamp")
	key(KEY_QUOTELEFT);await process_frame
	check(not game.fly and not game.session_menu.developer,"return from development resets flight and equipment")
	key(KEY_ESCAPE);await process_frame
	check(not game.session_menu.navigation.has("Toolbelt") and not game.session_menu.navigation.has("Building"),"session has no equipment or editor navigation")
	key(KEY_ESCAPE);await process_frame
	var belt_alt:=InputEventKey.new();belt_alt.pressed=true;belt_alt.physical_keycode=KEY_ALT;Input.parse_input_event(belt_alt);await process_frame
	await click_control(game.player_hud.belt[9])
	belt_alt=InputEventKey.new();belt_alt.physical_keycode=KEY_ALT;Input.parse_input_event(belt_alt);await process_frame
	check(game.player_hud.active_slot==9 and game.equipped_tool==0 and not game.session_menu.visible_ui(),"clicking empty belt slot selects empty hands")
	game.player_hud.equip_item(3);await process_frame
	check(not game.structure_mode and game.session_menu.developer_hud.context_slot()==-1,"repair hammer has no construction controls")
	game.player_hud.equip_item(101);await process_frame
	var alt:=InputEventKey.new();alt.pressed=true;alt.physical_keycode=KEY_ALT;Input.parse_input_event(alt);await process_frame
	var detailed:Button
	for control in game.session_menu.developer_hud.content.get_children():
		if control is Button and control.text.begins_with("Prefabs /"):detailed=control
	check(detailed!=null,"building tool owns its detailed settings action")
	if detailed!=null:await click_control(detailed)
	alt=InputEventKey.new();alt.physical_keycode=KEY_ALT;Input.parse_input_event(alt);await process_frame
	check(game.session_menu.workspace and game.equipped_tool==101 and game.structure_mode and not game.player_hud.inventory_open,"Building page keeps owned building material and exposes paid controls")
	check(game.construction_palette.panel.is_visible_in_tree() and not game.construction_palette.frontage_button.is_visible_in_tree(),"gameplay building shows shape/material/rotation/prefab without editor generation")
	for i in 3:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/unified_tools/building.png")
	game.session_menu.set_open(false);game.player_hud.equip_item(4);game.session_menu.open_current_tool();await process_frame
	check(game.equipped_tool==4 and game.model_tool.panel.is_visible_in_tree() and not game.model_tool.numeric_controls.visible,"Objects page equips assembly tool with full allowed gameplay controls")
	for i in 3:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/unified_tools/objects.png")
	game.session_menu.set_open(false)
	game.camera.global_position=target+Vector3(0,1.67,1.6);game.camera.look_at(target+Vector3(0,0.4,0))
	key(KEY_E);await process_frame
	check(game.storage.opened,"assembly tool does not steal chest interaction")
	game.storage.close()
	key(KEY_QUOTELEFT);await process_frame;game.session_menu.set_open(true);game.session_menu.show_page("Building");await process_frame
	check(game.editor_tool_active and game.construction_palette.frontage_button.is_visible_in_tree() and game.construction_palette.capture_name.is_visible_in_tree(),"development keeps settlement and prefab capture in its tool workspace")
	game.session_menu.show_page("Roads");await process_frame
	check(game.road_palette.panel.is_visible_in_tree(),"road controls use a tool workspace outside session")
	game.session_menu.show_page("Development");await process_frame
	for i in 3:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/unified_tools/development.png")
	game.session_menu.set_open(false);game.player_hud.equip_item(4);game.session_menu.set_open(true)
	game.session_menu.editor_tool(3);check(game.editor_tool_active and game.equipped_tool==0,"developer brush is separate from inventory equipment")
	key(KEY_QUOTELEFT);await process_frame
	check(not game.editor_tool_active and game.equipped_tool==game.player_hud.active_item,"leaving development restores actual gameplay equipment without a brush")
	# A real nearby terrain hit and actual held mouse input exercise pickaxe excavation.
	var origin: Vector3=game.player.position+Vector3(15,50,15)
	var terrain_hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin-Vector3.UP*200,1))
	check(not terrain_hit.is_empty(),"nearby terrain available for tool input check")
	if not terrain_hit.is_empty():
		game.player_hud.equip_item(1);game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		for i in 2:await process_frame
		game.camera.global_position=terrain_hit.position+Vector3.UP*2;game.camera.look_at(terrain_hit.position,Vector3.FORWARD)
		check(game.world_attack.target().get("kind")=="terrain","pickaxe aims at terrain after cursor handoff")
		game.world_attack.next_attack=0
		var revision: int=game.terrain.density_revision
		var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;Input.parse_input_event(click);await process_frame
		game._update_edit(0.1)
		click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(click);await process_frame;game._update_edit(0.1)
		deadline=Time.get_ticks_msec()+15000
		while (not game.world_attack.pending.is_empty() or game.terrain.pending_edit) and Time.get_ticks_msec()<deadline:await process_frame
		check(game.terrain.density_revision>revision and not game.mining_rewards.failed,"pickaxe mouse input publishes real native excavation")
		for i in 3:await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/unified_tools/pickaxe.png")
		check(game.edit_reach==3.5 and game.radius==0.65 and not game.allow_terrain_add,"pickaxe has fixed local reach and cannot fill terrain")
		revision=game.terrain.density_revision
		# Equipping the backpack pickaxe above may have used empty belt slot 9.
		var held_stack:Dictionary=inv.snapshot().slots[9]
		if held_stack.count>0:check(inv.consume(9,held_stack.count,inv.snapshot().revision).ok,"empty fixture belt slot for hand attack")
		game.player_hud.equip(9)
		check(game.equipped_tool==0,"empty belt slot equips hands before shared damage check")
		var damage_before:PackedByteArray=game.world_attack.durability.capture_storage_snapshot()
		game.world_attack.next_attack=0
		click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;Input.parse_input_event(click);await process_frame;game._update_edit(0.1)
		click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(click);await process_frame
		await preload("res://tests/swing_driver.gd").finish(game)
		check(game.world_attack.durability.capture_storage_snapshot()!=damage_before and not game.terrain.pending_edit,"empty hands use shared terrain damage before reaching destruction health")

	check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample and Engine.max_fps==60,"fullscreen1080p cap60")
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"normal shutdown")
	game.free();await process_frame;await process_frame
	print("UNIFIED_TOOLS failures=",failures);quit(1 if failures else 0)

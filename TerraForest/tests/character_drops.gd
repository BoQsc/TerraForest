# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func click(button: Button) -> void:
	await RenderingServer.frame_post_draw
	var point:=button.get_global_rect().get_center();Input.warp_mouse(point)
	await RenderingServer.frame_post_draw
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;Input.parse_input_event(motion)
	var e:=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.button_mask=MOUSE_BUTTON_MASK_LEFT;e.pressed=true;Input.parse_input_event(e);Input.flush_buffered_events()
	await RenderingServer.frame_post_draw
	e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(e);Input.flush_buffered_events()
	await RenderingServer.frame_post_draw
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
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+45000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"world ready")
	game.set_physics_process(false);game._clear_motion();game.fly=false;game.app_focused=true;game.player.position.y+=10
	var floor_body:=StaticBody3D.new();floor_body.collision_layer=1
	var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(8,0.2,8);collider.shape=box;floor_body.add_child(collider);game.add_child(floor_body);floor_body.global_position=game.player.global_position-Vector3.UP*0.2
	await physics_frame;await physics_frame
	var hud=game.player_hud;hud.set_open(true)
	hud.inventory.grant(204,9,hud.inventory.snapshot().revision);hud.refresh()
	for recipe in [4,5,6]:hud.craft_recipe(recipe)
	check(hud.message.text.begins_with("Crafted"),"clothing recipes use native crafting")
	var drag_before: PackedByteArray=hud.capture_snapshot()
	var candidate: Dictionary={"owner":hud.get_instance_id(),"side":"player","slot":-1,"count":1,"revision":hud.inventory.snapshot().revision,"equipment_revision":hud.equipment.snapshot(1).store_revision}
	for invalid in [-1,32,999999,"0",null]:
		candidate.slot=invalid
		check(not hud.character_panel.accepts_drag("equipment",0,candidate),"invalid equipment source slot rejects safely: "+str(invalid))
		hud.character_panel.drop_stack("equipment",0,candidate)
	candidate.erase("slot")
	check(not hud.character_panel.accepts_drag("equipment",0,candidate),"missing equipment drag field rejects")
	check(hud.character_panel.drag_data("equipment",-1).is_empty() and hud.character_panel.drag_data("equipment",3).is_empty(),"invalid equipment source controls reject")
	check(hud.capture_snapshot()==drag_before,"malformed drags preserve carried and equipped items")
	await click(hud.side_tabs.get_child(1))
	check(hud.character_panel.visible and not hud.crafting_content.visible,"Character tab replaces crafting")
	var before: PackedByteArray=hud.capture_snapshot()
	await drag(hud.belt[0],hud.character_panel.buttons[0])
	check(hud.capture_snapshot()==before and not hud.equipment.has_contents(1),"tools rejected by clothing slots without world drop")
	for slot in [0,1,2]:
		var source: int=-1
		for i in 32:
			if hud.state.slots[i].item==301+slot:source=i
		check(source>=0,"crafted wearable exists")
		if source>=0:await drag(hud.belt[source] if source<10 else hud.slots[source],hud.character_panel.buttons[slot])
		check(hud.equipment.snapshot(1).slots[slot].item==301+slot and hud.state.slots[source].count==0,"wearable moves into matching character slot")
	var captured: Dictionary=game.persistence._capture().sections
	check(captured.has("player_equipment") and hud.equipment.validate_snapshot(captured.player_equipment),"equipment saved with world")
	await drag(hud.character_panel.buttons[0],hud.slots[20])
	check(hud.state.slots[20].item==301 and hud.equipment.snapshot(1).slots[0].count==0,"unequip by dragging into backpack")
	await drag(hud.slots[20],hud.character_panel.buttons[0])
	var eq: PackedByteArray=hud.equipment.capture_storage_snapshot()
	check(hud.equipment.restore_storage_snapshot(eq) and hud.equipment.snapshot(1).slots[0].item==301,"equipment native save restore retains slots")
	hud.refresh()
	DirAccess.make_dir_recursive_absolute("res://reports/character_drops")
	for i in 3:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/character_drops/character.png")
	await click(hud.side_tabs.get_child(0))
	check(hud.crafting_content.visible and not hud.character_panel.visible,"Crafting tab returns to recipes")
	# An invisible test marker locates an outside-world target without intercepting input.
	var target:=Control.new();target.mouse_filter=Control.MOUSE_FILTER_IGNORE;target.position=Vector2(70,450);target.size=Vector2(60,60);hud.add_child(target)
	before=hud.capture_snapshot()
	await drag(hud.belt[4],hud.message)
	check(hud.capture_snapshot()==before,"release over panel whitespace cancels rather than world-dropping")
	game.app_focused=false;await drag(hud.belt[4],target)
	check(hud.capture_snapshot()==before,"unfocused world drop preserves inventory")
	game.app_focused=true
	await drag(hud.belt[4],target)
	print("DROP_NOTICE ",hud.message.text)
	check(hud.state.slots[4].count==0 and game.pickups.stores[101].statistics().active==1,"outside release drops full stack as one world pickup")
	var ids: PackedInt64Array=game.pickups.stacks[101].get_ids()
	check(ids.size()==1 and game.pickups.stacks[101].snapshot(ids[0]).slots[0].count==64,"world pickup carries full stack count")
	var saved: Dictionary=game.persistence._capture().sections
	check(saved.size()<64,"all component sections plus terrain fit native archive limit")
	check(saved.has("pickup_stacks_101") and game.pickups.stacks[101].restore_storage_snapshot(saved.pickup_stacks_101),"drop count survives native persistence")
	var result: Dictionary=game.pickups.collect_near(game.player.global_position+Vector3.UP*0.5,hud.inventory,game._pickup_reachable);hud.refresh()
	check(result.ok and hud.state.slots[4].count==64 and game.pickups.stores[101].statistics().active==0,"recollection conserves entire stack")
	var shift:=InputEventKey.new();shift.keycode=KEY_SHIFT;shift.physical_keycode=KEY_SHIFT;shift.pressed=true;Input.parse_input_event(shift)
	await drag(hud.belt[4],target)
	shift=InputEventKey.new();shift.keycode=KEY_SHIFT;shift.physical_keycode=KEY_SHIFT;Input.parse_input_event(shift)
	ids=game.pickups.stacks[101].get_ids()
	check(hud.state.slots[4].count==32 and ids.size()==1 and game.pickups.stacks[101].snapshot(ids[0]).slots[0].count==32,"Shift outside drag drops half as one pickup")
	# Remove the elevated support so every candidate has no reachable ground.
	floor_body.collision_layer=0
	await physics_frame;await physics_frame
	before=hud.capture_snapshot();await drag(hud.belt[0],target)
	check(hud.capture_snapshot()==before,"drop without reachable ground preserves tool")
	floor_body.collision_layer=1
	await physics_frame;await physics_frame
	game.pickups.collect_near(game.player.global_position+Vector3.UP*0.5,hud.inventory,game._pickup_reachable);hud.refresh()
	await drag(hud.belt[0],target)
	check(hud.state.slots[0].count==0 and game.pickups.stores[1].statistics().active==1,"tools can be dropped by outside release")
	for i in 3:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/character_drops/crafting.png")
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"clean shutdown")
	game.free();await process_frame;await process_frame
	print("CHARACTER_DROPS checks=",checks," failures=",failures);quit(1 if failures else 0)

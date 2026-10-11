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
	DirAccess.make_dir_recursive_absolute("res://reports/storage_interior")
	root.get_texture().get_image().save_png("res://reports/storage_interior/exterior.png")
	var event:=InputEventKey.new();event.pressed=true;event.physical_keycode=KEY_E;game._unhandled_input(event)
	check(game.storage.opened,"E reaches chest inside furnished cottage")
	if game.storage.opened:
		var slot:=-1
		for i in 32:
			if inv.snapshot().slots[i].item==102:slot=i
		game.storage.player_list.select(slot);game.storage.quantity.get_line_edit().text="2"
		check(game.storage.move_selected(true),"interior chest accepts wood through normal UI")
		for i in 5:await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/storage_interior/open.png")
		await drag(game.storage.storage_list.buttons[0],game.storage.player_list.buttons[28])
		check(inv.snapshot().slots[28].count==2 and not game.storage.store.has_contents(game.storage.identity),"real mouse drag withdraws to exact player slot")
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
	root.get_texture().get_image().save_png("res://reports/storage_interior/menu.png")
	key(KEY_QUOTELEFT);await process_frame
	check(game.session_menu.developer and not game.construction_inventory.gameplay and not game.mining_rewards.enabled,"development mode enables free authoring without mining rewards")
	game.session_menu.fly_button.pressed.emit();check(game.fly,"development flight button works")
	for i in 3:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/storage_interior/developer.png")
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
	key(KEY_G);await process_frame;check(not game.fly,"legacy flight shortcut is blocked in gameplay")
	game.player_hud.set_open(true)
	for i in 3:await process_frame
	check(game.player_hud.belt.size()==10,"ten toolbelt slots")
	await drag(game.player_hud.belt[0],game.player_hud.belt[9])
	check(inv.snapshot().slots[9].item==1,"real inventory drag swaps tool into tenth belt slot")
	for i in 3:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/storage_interior/inventory.png")
	game.player_hud.set_open(false)
	var equipped: Array=[];game.player_hud.tool_requested.connect(func(item: int):equipped.append(item))
	key(KEY_0);await process_frame
	check(equipped==[1],"zero key equips tenth belt slot")

	check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample and Engine.max_fps==60,"fullscreen1080p cap60")
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"normal shutdown")
	game.free();await process_frame;await process_frame
	print("PLAYER_UI failures=",failures);quit(1 if failures else 0)

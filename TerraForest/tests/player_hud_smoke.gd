# SPDX-License-Identifier: 0BSD
extends SceneTree
const Scene=preload("res://demo/world.tscn")
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func press(code: int,alt: bool=false) -> void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.alt_pressed=alt;event.pressed=true
	Input.parse_input_event(event)
	await process_frame
	event=InputEventKey.new();event.physical_keycode=code;event.alt_pressed=alt;event.pressed=false
	Input.parse_input_event(event)
	await process_frame
func run() -> void:
	var game=Scene.instantiate();game.temporary_world=true
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active,"world ready")
	if game.loading_active:
		game.terrain.shutdown();game.free();quit(1);return
	var hud=game.player_hud
	var original_fly: bool=game.fly
	var original_position: Vector3=game.player.position
	game.fly=true
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	game.controls.set_key(KEY_W,true,Time.get_ticks_usec())
	for i in range(3): await physics_frame
	check(game.player.position.distance_to(original_position)>0.01,"native flight calculation moves integrated controller")
	game._clear_motion()
	var stopped: Vector3=game.player.position
	for i in range(3): await physics_frame
	check(game.player.position.is_equal_approx(stopped),"integrated flight stops after input clear")
	game.player.position=original_position;game.fly=original_fly
	hud.equip(2)
	check(game.structure_mode and not game.model_tool.active,"toolbelt selects block construction")
	hud.equip(3)
	check(game.structure_mode and game.model_tool.active,"toolbelt selects object placement")
	hud.equip(0)
	check(not game.structure_mode and not game.model_tool.active and game.tool==3,"toolbelt selects sphere sculpting")
	await press(KEY_B)
	check(game.structure_mode and hud.active_item==3,"keyboard building mode updates active toolbelt")
	var palette=game.construction_palette
	check(palette.panel.visible,"construction palette appears in building mode")
	palette.shape.item_selected.emit(2)
	palette.material.item_selected.emit(1)
	palette.rotation_choice.item_selected.emit(1)
	check(game.structure_shape==3 and game.structure_material==1 and game.structure_rotation==1,"palette selects stairs wood and quarter-turn")
	await press(KEY_4)
	check(game.structure_shape==4 and palette.shape.selected==3,"keyboard shape selection synchronizes palette")
	palette.prefab.item_selected.emit(1)
	check(game.structure_prefab_index==0 and palette.shape.disabled and palette.material.disabled,"prefab selection shows authored material and shape constraints")
	palette.prefab.item_selected.emit(0)
	check(game.structure_prefab_index==-1 and not palette.shape.disabled,"single-block mode restores shape controls")
	await process_frame;await RenderingServer.frame_post_draw
	if DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute("res://reports/player_runtime")
		root.get_texture().get_image().save_png("res://reports/player_runtime/construction.png")
	await press(KEY_M)
	check(game.model_tool.active and hud.active_item==4,"keyboard objects mode updates active toolbelt")
	check(not palette.panel.visible,"construction palette hides for object placement")
	await press(KEY_1,true)
	check(not game.structure_mode and game.tool==3 and hud.active_item==1,"Alt shortcut routes through toolbelt without shape shortcut leaking")
	await press(KEY_1)
	check(game.tool==1 and hud.active_item==2,"terrain shape shortcut updates active toolbelt")
	var original_pending: bool=game.terrain.pending_edit
	game.terrain.pending_edit=true
	hud.equip(2)
	check(game.structure_mode and hud.active_item==3,"accepted edit does not lock tool switching")
	game.terrain.pending_edit=original_pending
	hud.equip(0)
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	await press(KEY_TAB)
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE and hud.inventory_open and game.player.velocity==Vector3.ZERO,"inventory releases mouse and clears movement")
	await press(KEY_M)
	check(not game.model_tool.active and hud.active_item==1,"inventory blocks world mode shortcuts")
	hud.select_slot(0);hud.select_slot(5)
	check(hud.state.slots[0].item==0 and hud.state.slots[5].item==1,"inventory movement updates native loadout")
	hud.equip(5)
	check(game.tool==3 and not game.structure_mode,"reassigned toolbelt slot invokes the same tool")
	var saved: Dictionary=game.persistence._capture()
	check(saved.sections.has("player_loadout"),"compound world capture includes player loadout")
	hud.select_slot(5);hud.select_slot(0)
	game.persistence._restore(saved.sections,game.persistence._restored_epoch)
	check(hud.state.slots[0].item==0 and hud.state.slots[5].item==1,"compound world restore refreshes loadout UI")
	check(hud.restore_snapshot(hud.default_loadout) and hud.state.slots[0].item==1,"legacy world default restores starter tools")
	hud.restore_snapshot(saved.sections.player_loadout)
	await process_frame;await RenderingServer.frame_post_draw
	if DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute("res://reports/player_runtime")
		check(root.get_texture().get_image().save_png("res://reports/player_runtime/inventory.png")==OK,"inventory screenshot saved")
	hud.set_open(false)
	check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"closing inventory restores capture")
	await process_frame;await RenderingServer.frame_post_draw
	if DisplayServer.get_name()!="headless": root.get_texture().get_image().save_png("res://reports/player_runtime/toolbelt.png")
	var saved_position: Vector3=game.player.position
	game.fly=true;game.yaw=0.4;game.pitch=-0.2
	hud.equip(2)
	var pose: PackedByteArray=game._capture_player_pose()
	check(not pose.is_empty() and game.persistence._capture().sections.has("player_pose"),"compound capture includes player position and view")
	game.player.position+=Vector3(5,5,5);game.yaw=0;game.pitch=0
	check(game._restore_player_pose(pose),"saved pose accepted")
	game._terrain_initialized("Test player pose restore")
	check(game.loading_active and game.waiting_spawn,"pose restoration uses destination loading gate")
	deadline=Time.get_ticks_msec()+15000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active and game.player.position.is_equal_approx(saved_position) and is_equal_approx(game.yaw,0.4) and is_equal_approx(game.pitch,-0.2) and hud.active_item==3,"saved position view and tool restored after readiness")
	game.terrain.shutdown();game.free()
	quit(1 if failures else 0)

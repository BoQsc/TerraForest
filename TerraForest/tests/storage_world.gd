# SPDX-License-Identifier: 0BSD
extends SceneTree
var game: Node
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: run.call_deferred()
func aim(base: Vector3) -> void:
	game.player.position=base+Vector3(0,0.05,1.6);game.player.rotation=Vector3.ZERO
	game.camera.transform=Transform3D(Basis.IDENTITY,Vector3(0,1.62,0));game.camera.look_at(base+Vector3(0,0.4,0))
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func use() -> void:
	var event:=InputEventKey.new();event.pressed=true;event.physical_keycode=KEY_E;game._unhandled_input(event)
func run() -> void:
	var slot:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
	if not slot.begins_with("storage_world_") or not slot.is_valid_identifier():quit(2);return
	var reopening: bool="--reopen-loop" in OS.get_cmdline_user_args()
	var dir:="res://reports/storage_world/";DirAccess.make_dir_recursive_absolute(dir)
	var expected_path:=dir+slot+".expected"
	if not reopening and (FileAccess.file_exists("user://worlds/"+slot+".trw") or FileAccess.file_exists(expected_path)):quit(2);return
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=false;game.max_fps=60;game.background_fps=60;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active and game.terrain.world_ready and game.terrain.save_slot==slot,"isolated persistent world ready")
	game.set_physics_process(false);game._clear_motion();game.app_focused=true
	var chest: Node3D=game.storage.collection
	var base: Vector3=game.player.position.snapped(Vector3.ONE)+Vector3.UP*12
	var expected: Dictionary={}
	if reopening:
		expected=FileAccess.open(expected_path,FileAccess.READ).get_var();base=expected.base
		check(game.storage.store.capture_storage_snapshot()==expected.contents,"fresh process restores exact chest contents")
		check(game.player_hud.inventory.capture_storage_snapshot()==expected.inventory,"fresh process restores matching player inventory")
		check(chest.get_ids()==expected.ids and chest.is_removal_protected(expected.ids[0]),"fresh process restores chest identity and deletion protection")
	else:
		var empty: RefCounted=ClassDB.instantiate("NativePlayerInventory");check(game.player_hud.restore_snapshot(empty.capture_storage_snapshot()),"fixture clears starter loadout")
		var inv: RefCounted=game.player_hud.inventory
		check(inv.grant_items(PackedInt64Array([102,8,201,25]),inv.snapshot().revision).ok,"fixture grants chest materials and storable stone")
		var cells:=PackedInt32Array()
		for x in range(-3,4):
			for z in range(-3,4):cells.append_array(PackedInt32Array([int(base.x)+x,int(base.y)-1,int(base.z)+z,1]))
		check(game.structures.blocks.set_cells(cells),"block floor placed")
	game.player.position=base+Vector3(2,0.1,2);game.needs_floor_spawn=false
	game.structures.set_model_focus(base);game.structures.blocks.set_focus(base)
	for i in 60:await physics_frame
	if not reopening:
		game._set_player_tool_mode(true,true,game.tool);game.model_tool.edit_available=true;game.model_tool.select(7)
		game.camera.global_position=base+Vector3(0,2,2);game.camera.look_at(base)
		check(game.model_tool.edit(false)>0,"normal paid object tool places storage chest")
	for i in 30:await physics_frame
	game._set_player_tool_mode(false,false,1);game.fly=false
	aim(base)
	for i in 10:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir+slot+("_reopen_exterior.png" if reopening else "_build_exterior.png"))
	use()
	check(game.storage.opened and game.player_hud.inventory_open and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"normal E opens reachable chest and blocks player controls")
	if not game.storage.opened:
		game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();quit(1);return
	var id: int=game.storage.identity
	if not reopening:
		game.storage.player_list.select(1);game.storage.quantity.get_line_edit().text="7"
		check(game.storage.move_selected(true),"UI deposits seven stone")
		check(game.storage.store.snapshot(id).slots[0].count==7 and chest.is_removal_protected(id),"deposit creates contents and native protection")
		check(not game.model_tool.history.erase(chest,id) and not game.model_tool.history.undo(AABB()),"filled chest cannot be removed or placement-undone")
		game.storage.storage_list.select(0);game.storage.quantity.get_line_edit().text="3"
		check(game.storage.move_selected(false) and game.storage.store.snapshot(id).slots[0].count==4,"UI withdraws part of a stack")
	else:
		check(game.storage.store.snapshot(id).slots[0].count==4,"saved four stone visible in reopened UI")
	var guarded_contents: PackedByteArray=game.storage.store.capture_storage_snapshot()
	var guarded_player: PackedByteArray=game.player_hud.inventory.capture_storage_snapshot()
	game.storage.storage_list.select(0);game.storage.quantity.get_line_edit().text="1";game.player.position.z+=8
	check(not game.storage.move_selected(false) and not game.storage.opened and game.storage.store.capture_storage_snapshot()==guarded_contents and game.player_hud.inventory.capture_storage_snapshot()==guarded_player,"transfer rechecks reach and closes stale distant interaction without mutation")
	aim(base);use()
	var wall:=StaticBody3D.new();wall.collision_layer=2
	var obstruction:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1,2,0.15);obstruction.shape=box;wall.add_child(obstruction);root.add_child(wall);wall.position=base+Vector3(0,1,0.7)
	for i in 3:await physics_frame
	game.storage.storage_list.select(0)
	check(not game.storage.move_selected(false) and game.storage.store.capture_storage_snapshot()==guarded_contents and game.player_hud.inventory.capture_storage_snapshot()==guarded_player,"new obstruction prevents transfer through a wall")
	wall.free()
	for i in 3:await physics_frame
	aim(base);use()
	for i in 10:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir+slot+("_reopen.png" if reopening else "_build.png"))
	check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample and Engine.max_fps==60,"fullscreen1080p cap60")
	game.storage.close();check(not game.player_hud.inventory_open and game.player_hud.enabled,"closing storage returns normal inventory and controls")
	var region:=Vector3i(int(floor(base.x/32)),int(floor(base.y/32)),int(floor(base.z/32)))
	var packet: PackedByteArray=chest.capture_region(region)
	check(chest.unload_region(packet) and game.storage.store.capture_storage_snapshot()==guarded_contents and chest.is_removal_protected(id),"unloading chest geometry retains contents and ownership")
	check(chest.restore_region(packet) and game.storage.store.capture_storage_snapshot()==guarded_contents and chest.is_removal_protected(id),"returning chest geometry reconnects the same contents")
	for i in 30:await physics_frame
	expected={"base":base,"ids":chest.get_ids(),"contents":game.storage.store.capture_storage_snapshot(),"inventory":game.player_hud.inventory.capture_storage_snapshot()}
	var saved: Array=[];game.terrain.save_completed.connect(func(ok: bool):saved.append(ok))
	game.terrain.changed_since_save=true;game.terrain.save_world();deadline=Time.get_ticks_msec()+20000
	while saved.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(not saved.is_empty() and saved[0],"normal save publishes chest and player contents together")
	if not reopening and failures==0:
		var file:=FileAccess.open(expected_path,FileAccess.WRITE);file.store_var(expected);file.close()
	if reopening:
		aim(base);use();game.storage.storage_list.select(0);game.storage.quantity.get_line_edit().text="1"
		check(game.storage.move_selected(false) and chest.is_removal_protected(id),"partial unsaved withdrawal leaves ownership active")
		game.storage.close()
		var old_epoch: int=game.terrain.epoch;game.terrain.reload_world(false);deadline=Time.get_ticks_msec()+60000
		while (game.terrain.epoch==old_epoch or game.loading_active) and Time.get_ticks_msec()<deadline:await process_frame
		check(not game.loading_active and game.storage.store.capture_storage_snapshot()==expected.contents and chest.is_removal_protected(id) and game.player_hud.inventory.capture_storage_snapshot()==expected.inventory,"same-process reload restores saved ownership and both inventory sides")
		for i in 30:await physics_frame
		aim(base);use();game.storage.storage_list.select(0);game.storage.quantity.get_line_edit().text="4"
		check(game.storage.move_selected(false) and not game.storage.store.has_contents(id) and not chest.is_removal_protected(id),"emptying chest releases sparse contents and deletion protection")
		game.storage.close()
		check(game.model_tool.history.erase(chest,id),"empty chest can be removed normally")
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"normal shutdown drains")
	game.free();await process_frame;await process_frame
	print("STORAGE_WORLD ",JSON.stringify({"checks":checks,"failures":failures,"reopen":reopening}));quit(1 if failures else 0)

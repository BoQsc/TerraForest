# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var slot:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--world-slot="): slot=arg.trim_prefix("--world-slot=")
	if not slot.begins_with("ladder_world_") or not slot.is_valid_identifier(): quit(2);return
	var reopening: bool="--reopen-loop" in OS.get_cmdline_user_args()
	var dir:="res://reports/ladder_world/"
	DirAccess.make_dir_recursive_absolute(dir)
	var expected_path: String=dir+slot+".expected"
	if not reopening and (FileAccess.file_exists("user://worlds/"+slot+".trw") or FileAccess.file_exists(expected_path)): quit(2);return
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=false;game.max_fps=60;game.background_fps=60;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active and game.terrain.world_ready and game.terrain.save_slot==slot,"isolated persistent main world ready")
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	check(game.model_tool.catalog.size()==7 and game.construction_inventory.gameplay,"ladder catalog enabled in paid gameplay")
	var entry: Dictionary=game.model_tool.catalog[6]
	var expected: Dictionary={}
	var base: Vector3=game.player.position.snapped(Vector3.ONE)+Vector3.UP*12
	if reopening:
		expected=FileAccess.open(expected_path,FileAccess.READ).get_var();base=expected.base
		check(entry.collection.get_ids()==expected.ids,"stable ladder identity restored by normal world loader")
		check(entry.collection.capture_snapshot()==expected.ladder,"exact placement snapshot restored")
		check(game.player_hud.inventory.capture_storage_snapshot()==expected.inventory,"paid inventory restored with no starter refill")
	else:
		var empty: RefCounted=ClassDB.instantiate("NativePlayerInventory")
		check(game.player_hud.restore_snapshot(empty.capture_storage_snapshot()),"fixture clears starter inventory")
		var inv: RefCounted=game.player_hud.inventory
		check(inv.grant(102,6,inv.snapshot().revision).ok,"fixture grants exactly six wood")
		var cells:=PackedInt32Array()
		for x in range(-3,4):
			for z in range(-4,3):
				cells.append_array(PackedInt32Array([int(base.x)+x,int(base.y)-1,int(base.z)+z,1]))
				if z<0: cells.append_array(PackedInt32Array([int(base.x)+x,int(base.y)+2,int(base.z)+z,1]))
		check(game.structures.blocks.set_cells(cells),"editable block floor and upper landing placed")
	game.player.position=base+Vector3(2,0.1,2);game.needs_floor_spawn=false
	game.structures.set_model_focus(base);game.structures.blocks.set_focus(base)
	for i in 60: await physics_frame
	if not reopening:
		game._set_player_tool_mode(true,true,game.tool);game.model_tool.edit_available=true;game.model_tool.select(6)
		game.camera.global_position=base+Vector3(0,2,2);game.camera.look_at(base)
		check(game.model_tool.edit(false)>0,"normal paid object tool places ladder")
		check(game.player_hud.inventory.snapshot().slots.all(func(row: Dictionary):return row.count==0),"ladder consumes exactly six wood")
		game.camera.global_position=base+Vector3(2,2,2);game.camera.look_at(base+Vector3(2,0,0))
		check(game.model_tool.edit(false)==0 and entry.collection.get_ids().size()==1,"unaffordable second ladder is rejected")
	for i in 30: await physics_frame
	game.model_tool.set_active(false)
	game.camera.global_position=base+Vector3(5,4.8,6);game.camera.look_at(base+Vector3(0,1.7,0))
	for i in 10: await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir+slot+("_reopen.png" if reopening else "_build.png"))
	check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample and Engine.max_fps==60,"fullscreen1080p cap60")
	game.player.position=base+Vector3(0,0.05,0.55);game.player.rotation=Vector3.ZERO;game.player.velocity=Vector3.ZERO
	game.camera.transform=Transform3D(Basis.IDENTITY,Vector3(0,1.62,0));game.fly=false
	game.controls.held[KEY_W]=true
	for i in 180:
		await physics_frame
		if game.player.position.z<base.z-0.8: game.controls.held.clear()
		game._physics_process(1.0/60.0)
	game.controls.held.clear()
	check(game.player.position.z<base.z-0.7 and absf(game.player.position.y-base.y-3)<0.12,"normal world controller climbs onto upper block landing")
	print("WORLD_LANDING ",game.player.position-base)
	expected={"base":base,"ids":entry.collection.get_ids(),"ladder":entry.collection.capture_snapshot(),"inventory":game.player_hud.inventory.capture_storage_snapshot()}
	var saved: Array=[];game.terrain.save_completed.connect(func(ok: bool):saved.append(ok))
	game.terrain.changed_since_save=true;game.terrain.save_world();deadline=Time.get_ticks_msec()+20000
	while saved.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(not saved.is_empty() and saved[0],"normal save commits ladder and inventory")
	if not reopening and failures==0:
		var file:=FileAccess.open(expected_path,FileAccess.WRITE);file.store_var(expected);file.close()
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"world drains normally")
	game.free();await process_frame;await process_frame
	print("LADDER_WORLD ",JSON.stringify({"checks":checks,"failures":failures,"reopen":reopening}));quit(1 if failures else 0)

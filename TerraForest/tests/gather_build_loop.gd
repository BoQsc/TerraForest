# SPDX-License-Identifier: 0BSD
extends SceneTree
var game: Node
var failures:=0
var checks:=0
var slot:=""
var reopening:=false
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:run.call_deferred()
func amount(item: int) -> int:
	var result:=0
	for row: Dictionary in game.player_hud.inventory.snapshot().slots:
		if row.item==item:result+=int(row.count)
	return result
func finish() -> void:
	game.shutdown_requested=true
	check(await game.terrain.shutdown_after_edits(),"normal world shutdown completes")
	game.free();await process_frame
	print("GATHER_BUILD_LOOP ",JSON.stringify({"checks":checks,"failures":failures,"reopen":reopening,"slot":slot}));quit(1 if failures else 0)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
	reopening="--reopen-loop" in OS.get_cmdline_user_args()
	if not slot.begins_with("gather_loop_") or not slot.is_valid_identifier():quit(2);return
	var expected_path: String="res://reports/gather_build_loop/"+slot+".expected"
	if not reopening and (FileAccess.file_exists("user://worlds/"+slot+".trw") or FileAccess.file_exists(expected_path)):quit(2);return
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=false;game.max_fps=60;game.background_fps=60;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active and game.terrain.world_ready and not game.temporary_world and game.terrain.save_slot==slot,"persistent gameplay starts in dedicated slot")
	check(game.construction_inventory.gameplay and game.ground_enabled,"paid construction and gather path enabled")
	if failures:await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var cover: Node=game.ground_cover
	deadline=Time.get_ticks_msec()+20000
	while cover.resident.size()<49 and Time.get_ticks_msec()<deadline:await process_frame
	check(cover.resident.size()==49,"natural gathering area loaded")
	if failures:await finish();return
	var expected: Dictionary={}
	if reopening:
		var file:=FileAccess.open(expected_path,FileAccess.READ);expected=file.get_var();file.close()
		check(game.player_hud.inventory.capture_storage_snapshot()==expected.inventory,"fresh process preserves exact earned inventory")
		check(cover.removed.capture_storage_snapshot()==expected.ground,"fresh process preserves exact gathered identities")
		check(game.structures.blocks.get_cell(expected.cell)==1,"crafted paid brick survives fresh process")
		check(amount(201)==1 and amount(101)==0,"no starter top-up or spent-brick duplication on reopen")
		for id in expected.ids:check(cover.removed.contains(id) and not cover.batches[0].get_ids().has(id),"gathered natural stone remains removed")
	else:
		var empty=ClassDB.instantiate("NativePlayerInventory")
		check(game.player_hud.restore_snapshot(empty.capture_storage_snapshot()),"clear starter stock through loadout restore")
		check(amount(201)==0 and amount(101)==0,"no free materials can fund the fixture")
		var gathered:=PackedInt64Array();var position:=Vector3.ZERO
		var candidates: Array=[]
		for key in cover.resident:
			var row: Dictionary=cover.resident[key][0]
			for i in row.ids.size():
				var t: PackedFloat32Array=row.transforms
				candidates.append({"id":row.ids[i],"point":Vector3(t[i*12+3],t[i*12+7],t[i*12+11])})
		candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.point.distance_squared_to(game.player.position)<b.point.distance_squared_to(game.player.position))
		for candidate in candidates:
			var point: Vector3=candidate.point
			game.camera.global_position=point+Vector3.UP*2
			var result: Dictionary=game.ground_interaction.collect(game.camera.global_position,point-Vector3.UP*0.25,game.player_hud.inventory,true)
			if not result.ok:continue
			gathered.append(result.id);position=point
			if gathered.size()==3:break
		check(gathered.size()==3 and amount(201)==3,"three reachable natural stones grant exactly three stone")
		if failures:await finish();return
		game.player_hud.set_open(true);game.player_hud.recipe_buttons[0].pressed.emit()
		check(game.player_hud.message.text.begins_with("Crafted supplies") and amount(201)==1 and amount(101)==1,"inventory UI converts two gathered stone into one brick")
		game.player_hud.set_open(false)
		var cell:=Vector3i(floori(position.x),floori(position.y),floori(position.z))
		check(game.construction_inventory.place_block(game.structures.blocks,game.player_hud.inventory,cell,1),"paid construction accepts earned brick")
		check(amount(101)==0 and game.structures.blocks.get_cell(cell)==1,"construction consumes exactly one brick")
		var before: PackedByteArray=game.player_hud.inventory.capture_storage_snapshot()
		check(not game.construction_inventory.place_block(game.structures.blocks,game.player_hud.inventory,cell+Vector3i.RIGHT,1) and game.structures.blocks.get_cell(cell+Vector3i.RIGHT)==0 and game.player_hud.inventory.capture_storage_snapshot()==before,"unaffordable second block changes neither world nor inventory")
		expected={"ids":gathered,"cell":cell,"inventory":before,"ground":cover.removed.capture_storage_snapshot()}
	var key:=InputEventKey.new();key.pressed=true;key.physical_keycode=KEY_F
	var lamp_before: bool=game.headlamp.visible;game._unhandled_input(key)
	check(game.headlamp.visible!=lamp_before,"normal use input toggles headlamp after inventory and building")
	game._unhandled_input(key)
	check(game.headlamp.visible==lamp_before,"second use restores light state")
	var block_center: Vector3=Vector3(expected.cell)+Vector3.ONE*0.5
	game.structures.set_model_focus(block_center)
	game.camera.global_position=block_center+Vector3(3,2,3);game.camera.look_at(block_center)
	for frame in 30:await RenderingServer.frame_post_draw
	var hit: Dictionary=game.structures.blocks.raycast_scene(block_center+Vector3.UP*3,block_center,2,[])
	check(not hit.is_empty() and absf(hit.position.y-(expected.cell.y+1.0))<0.02,"earned block provides reachable scene collision at its top surface")
	check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample and Engine.max_fps==60,"fullscreen1080p cap60")
	DirAccess.make_dir_recursive_absolute("res://reports/gather_build_loop")
	root.get_texture().get_image().save_png("res://reports/gather_build_loop/"+slot+("_reopen.png" if reopening else "_build.png"))
	var saved: Array=[];game.terrain.save_completed.connect(func(ok: bool):saved.append(ok))
	game.terrain.changed_since_save=true;game.terrain.save_world();deadline=Time.get_ticks_msec()+20000
	while saved.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(not saved.is_empty() and saved[0],"normal world save commits earned state")
	if not reopening and failures==0:
		var file:=FileAccess.open(expected_path,FileAccess.WRITE);file.store_var(expected);file.close()
	await finish()

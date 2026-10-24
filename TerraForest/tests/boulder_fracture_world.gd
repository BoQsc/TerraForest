# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var checks:=0
var failures:=0
var output:="res://reports/boulder_fracture_world"
var pose:Transform3D
var identity:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func stone_count()->int:
	var total:=0
	for row:Dictionary in game.player_hud.inventory.snapshot().slots:
		if row.item==201:total+=row.count
	return total
func aim()->void:
	var point:Vector3=pose*Vector3(0,.05,.26)
	game.camera.global_position=point+pose.basis.z.normalized()*2.0;game.camera.look_at(point)
	game.app_focused=true;game.fly=false;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func picture(name:String)->void:
	game.camera.global_position=pose.origin+Vector3(10,6,12);game.camera.look_at(pose.origin)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
	aim()
func strike()->bool:
	aim()
	var deadline:=Time.get_ticks_msec()+4000
	while (game.ground_cover._dirty.has(Vector2i(floori(pose.origin.x/32),floori(pose.origin.z/32))) or game.terrain.pending_edit) and Time.get_ticks_msec()<deadline:await process_frame
	if not game.world_attack.attack():print("STRIKE rejected before animation");return false
	while not game.world_attack.pending.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	return game.world_attack.pending.is_empty() and game.world_attack.last_hit
func run()->void:
	var slot:="";var reopening:=false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
		if arg=="--reopen-loop":reopening=true
		if arg.begins_with("--fracture-evidence="):output=arg.trim_prefix("--fracture-evidence=")
	if not slot.begins_with("fracture_check_") or not slot.is_valid_identifier():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	var expected_path:=OS.get_user_data_dir().path_join(slot+".expected")
	if not reopening and (FileAccess.file_exists(expected_path) or FileAccess.file_exists("user://worlds/"+slot+".trw")):quit(2);return
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=false;game.max_fps=60;game.background_fps=60;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active and game.terrain.world_ready,"playable world initializes the shared native fragment cache")
	if game.loading_active:quit(1);return
	game.set_physics_process(false);game._clear_motion();game.player_hud.equip_item(1);game._sync_player_tool()
	var inventory:RefCounted=game.player_hud.inventory
	if reopening:
		var expected:Dictionary=FileAccess.open(expected_path,FileAccess.READ).get_var();identity=expected.id;pose=expected.pose
		check(game.world_attack.durability.damage("cover:%d"%identity,240)==90,"fresh process restores exact partial mining damage")
		check(inventory.capture_storage_snapshot()==expected.inventory,"partial mining preserves the matching player inventory/tool wear")
	else:
		deadline=Time.get_ticks_msec()+18000
		while identity==0 and Time.get_ticks_msec()<deadline:
			for key:Vector2i in game.ground_cover.resident:
				var large:Dictionary=game.ground_cover.native.boulder_rows(game.ground_cover.resident[key][0])
				if large.ids.is_empty():continue
				var values:PackedFloat32Array=large.transforms
				pose=Transform3D(Basis(Vector3(values[0],values[4],values[8]),Vector3(values[1],values[5],values[9]),Vector3(values[2],values[6],values[10])),Vector3(values[3],values[7],values[11]));identity=large.ids[0];break
			if identity==0:await process_frame
		check(identity>0,"normal vegetation streaming supplies a mineable boulder")
	if identity>0:
		aim();deadline=Time.get_ticks_msec()+15000
		while game.ground_cover.fractures.stage(identity)<0 and Time.get_ticks_msec()<deadline:await process_frame
		check(game.ground_cover.fractures.stage(identity)==(1 if reopening else 0),"resident mesh matches its authoritative saved fracture stage")
		var before:=stone_count()
		if not reopening:
			check(await strike() and await strike() and await strike(),"three actual pickaxe contact animations damage the aimed boulder")
			check(game.world_attack.durability.damage("cover:%d"%identity,240)==90 and game.ground_cover.fractures.stage(identity)==1,"first damage threshold splits the boulder into halves")
			check(stone_count()==before,"partial fractures do not duplicate the stone reward")
			await picture("halves")
			var saved:Array=[];game.terrain.save_completed.connect(func(ok:bool):saved.append(ok))
			game.terrain.changed_since_save=true;game.terrain.save_world();deadline=Time.get_ticks_msec()+20000
			while saved.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
			check(not saved.is_empty() and saved[0],"normal compound save publishes partial fracture progress")
		else:
			await picture("restored_halves")
			check(await strike() and await strike() and await strike(),"continued mining damages the restored boulder")
			check(game.world_attack.durability.damage("cover:%d"%identity,240)==180 and game.ground_cover.fractures.stage(identity)==2,"second threshold splits the halves into four capped pieces")
			await picture("quarters")
			for i in 32:
				var slot_data:Dictionary=inventory.snapshot().slots[i]
				if slot_data.item==0:inventory.grant(201,999,inventory.snapshot().revision)
			var full:=stone_count()
			check(await strike() and not await strike(),"full inventory blocks the final harvest at the contact frame")
			check(game.ground_cover.fractures.stage(identity)==2 and stone_count()==full,"blocked final hit preserves the mineable quarters and all inventory")
			for i in 32:
				if inventory.snapshot().slots[i].item==201:inventory.consume(i,24,inventory.snapshot().revision);break
			var space:=stone_count()
			check(await strike(),"final hit succeeds after inventory space is available")
			check(game.ground_cover.fractures.stage(identity)==3 and stone_count()==space+24,"third fracture produces eight debris pieces and exactly 24 stone")
			await picture("eighths")
			check(game.ground_cover.removed.mask(PackedInt64Array([identity]))[0]!=0,"completed boulder remains marked harvested")
			var origin:Vector3=game.camera.global_position
			check(not game.ground_interaction.collect(origin,origin-game.camera.global_basis.z*3.5,inventory,true,null,identity).ok,"the same boulder cannot be collected twice")
			await create_timer(.85).timeout;await picture("landed_eighths")
			await create_timer(2.0).timeout
			check(game.ground_cover.fractures.stage(identity)==-1,"GPU debris expires without leaving a collision or render root")
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"normal shutdown drains the owned test world")
	if not reopening and failures==0:
		var file:=FileAccess.open(expected_path,FileAccess.WRITE);file.store_var({"id":identity,"pose":pose,"inventory":inventory.capture_storage_snapshot()});file.close()
	game.free();await process_frame;await process_frame
	print("BOULDER_FRACTURE_WORLD checks=",checks," failures=",failures," reopen=",reopening);quit(1 if failures else 0)

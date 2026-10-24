extends "res://addons/world_runtime/generate_world_task.gd"
func snapshot_signature(game:Node)->Dictionary:
	var result:=super.snapshot_signature(game)
	if not qualification:
		FileAccess.open(output_dir.path_join("terrain_lot_region_expected.bin"),FileAccess.WRITE).store_buffer(Marshalls.base64_to_raw(result.region))
	return result
func verify(ok:bool,label:String)->bool:
	print("PASS " if ok else "FAIL ",label);return ok
func capture(game:Node,label:String)->void:
	game.world_map.set_open(false)
	if generation_screen!=null:generation_screen.hide()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join(label+".png"))
func walk_ramp(game:Node,roads:Array)->bool:
	for road:Dictionary in roads:
		if absf(road.finish.y-road.start.y)<.1:continue
		var direction:Vector3=(road.finish-road.start).normalized()
		var across:Vector3=Vector3.UP.cross(direction).normalized()
		var start:Vector3=road.start.lerp(road.finish,.12)+across*3.75
		var finish:Vector3=road.start.lerp(road.finish,.88)+across*3.75
		start.y=lerpf(road.start.y,road.finish.y,smoothstep(0.0,1.0,.12))
		finish.y=lerpf(road.start.y,road.finish.y,smoothstep(0.0,1.0,.88))
		game.teleport(start)
		if not await ready_world(game):return false
		game.set_physics_process(false);game._clear_motion();game.fly=false;game.needs_floor_spawn=false
		game.player.position=start+Vector3.UP*.08;game.camera.position=Vector3(0,1.65,0);game.camera.look_at(finish+Vector3.UP*1.65)
		await capture(game,"road_smooth_ramp")
		var arrived:=false
		for tick in 360:
			var offset:Vector3=finish-game.player.position;offset.y=0
			if offset.length()<.25 and game.player.is_on_floor():arrived=true;break
			game.yaw=atan2(-offset.x,-offset.z);game.player.rotation.y=game.yaw
			game.controls.set_key(KEY_W,offset.length()>.15,Time.get_ticks_usec())
			await physics_frame;game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;game._physics_process(1.0/60)
		game.controls.clear(Time.get_ticks_usec())
		print("PAVING_RAMP_WALK ",{"arrived":arrived,"start":start,"finish":finish,"actual":game.player.position})
		return verify(arrived,"real walking controller traverses the smooth roadside ramp without jumping")
	return verify(false,"generated review site contains a slope to test")
func bake_photographs(game:Node,plan:Dictionary,market:Dictionary,connection:Dictionary)->bool:
	if generation_screen!=null:generation_screen.set_process(false)
	if not verify(game.structures.model("architecture/concrete_paving/v1").get_ids().is_empty(),"newly generated construction contains no legacy decorative paving instances"):return false
	var records:PackedInt32Array=plan.block_paving.records
	if not verify(records.size()>0,"production generation publishes native sidewalk plates"):return false
	var cell:=Vector3i(records[0],records[1],records[2])
	var point:=Vector3(cell)+Vector3(.5,1,.5)
	game.teleport(point+Vector3(0,.1,2))
	if not await ready_world(game):return false
	game.set_physics_process(false);game._clear_motion();game.needs_floor_spawn=false;game.app_focused=true
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);game.world_map.set_open(false)
	game.player.position=point+Vector3(0,.1,2);game.camera.global_position=point+Vector3(0,1.6,2);game.camera.look_at(point)
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;game.player_hud.equip_item(1)
	if not verify(await wait_until(func():return game.world_attack.target().get("cell")==cell,10),"real player target hits one generated plate, not the terrain below"):return false
	await capture(game,"road_plate_before")
	var adjacent:=Vector3i(records[4],records[5],records[6]);var neighbor:int=game.structures.blocks.get_cell(adjacent)
	var wear:int=game.player_hud.inventory.snapshot().slots[game.player_hud.active_slot].wear
	for strike in 4:
		game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;game.world_attack.next_attack=0
		var started:bool=game.world_attack.attack()
		var finished:bool=started and await wait_until(func():return game.world_attack.pending.is_empty(),4)
		if not verify(started and finished and game.world_attack.last_hit,"ordinary pickaxe contact damages the plate "+str(strike+1)):
			print("PAVING_ATTACK_DIAGNOSTIC ",{"started":started,"finished":finished,"pending":game.world_attack.pending,"can_edit":game._model_edit_available(),"focused":game.app_focused,"loading":game.loading_active,"tool":game.equipped_tool,"menu":game.session_menu.visible_ui(),"developer":game.session_menu.developer,"profile":game.tool_view.attack_profile()})
			return false
	if not verify(game.structures.blocks.get_cell(cell)==0 and game.structures.blocks.get_cell(adjacent)==neighbor and game.player_hud.inventory.snapshot().slots[game.player_hud.active_slot].wear==wear+4,"four normal hits remove only the selected plate and charge normal wear"):return false
	await capture(game,"road_plate_removed")
	var build_point:=Vector3(adjacent)+Vector3(.5,1,.5)
	game.player.position=build_point+Vector3(0,.1,2);game.camera.global_position=build_point+Vector3(0,1.6,2);game.camera.look_at(build_point)
	if not verify(game.player_hud.equip_item(101),"player owns a building block to place"):return false
	var stock:int=game.player_hud.inventory.snapshot().slots[game.player_hud.active_slot].count
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var target:Dictionary=game._structure_target(false)
	if not verify(target.get("target")==adjacent+Vector3i.UP and target.placement_ok,"building target is exactly the cell above the road plate"):return false
	game._edit_structure(false)
	if not verify(game.structures.blocks.get_cell(adjacent+Vector3i.UP)==1+(game.structure_rotation<<3),"actual placement puts a paid building block flush on the plate"):
		print("PAVING_PLACE_DIAGNOSTIC ",{"word":game.structures.blocks.get_cell(adjacent+Vector3i.UP),"shape":game.structure_shape,"material":game.structure_material,"rotation":game.structure_rotation,"reason":game.construction_inventory.reason})
		return false
	if not verify(game.player_hud.inventory.snapshot().slots[game.player_hud.active_slot].count==stock-1,"placing above the plate consumes exactly one brick"):return false
	if not verify(await wait_until(func():return game._placement_collision_ready(AABB(Vector3(adjacent),Vector3(1,2,1))),10),"placed block finishes native mesh and collision publication"):return false
	await capture(game,"road_plate_building")
	game.camera.global_position=point+Vector3(10,7,10);game.camera.look_at(point+Vector3(8,0,0))
	await capture(game,"road_plate_overview")
	var file:=FileAccess.open(output_dir.path_join("road_plate_interaction.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"removed":cell,"support":adjacent,"placed":adjacent+Vector3i.UP,"paving_tiles":records.size()/4,"terrain_ramps":plan.block_paving.terrain_ramps}));file.close()
	if not await walk_ramp(game,plan.roads):return false
	if generation_screen!=null:generation_screen.set_process(true)
	if not await super.bake_photographs(game,plan,market,connection):return false
	FileAccess.open(output_dir.path_join("world_signature.json"),FileAccess.WRITE).store_string(JSON.stringify({"seed":seed_value,"generator":game.terrain.backend.world_generator,"signature":snapshot_signature(game)}))
	return true

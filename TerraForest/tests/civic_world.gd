# SPDX-License-Identifier: 0BSD
extends "res://tests/approved_city_world.gd"
const Civic=preload("res://addons/structures/civic_catalog.gd")
const Trade=preload("res://addons/player_runtime/trader_inventory.gd")
var selected_slot:=""
var planned:Dictionary={}
var restoration:=false
var only_role:=""

func run()->void:
	folder="res://reports/civic_world";DirAccess.make_dir_recursive_absolute(folder)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--civic-role="):only_role=argument.trim_prefix("--civic-role=")
	if "--build-civic" in OS.get_cmdline_user_args():
		change_scene_to_file("res://demo/worlds.tscn");await scene_changed
		var browser=current_scene
		selected_slot="CivicReview_1703_"+Crypto.new().generate_random_bytes(4).hex_encode()
		var request:=Launch.command(selected_slot,true,Launch.INTEGRATED_PRESET,1703,true,"user://worlds",true,"connected",true,Recipe.DEFAULTS)
		if not check(request.ok,"fresh isolated civic review generation request"):await finish();return
		request.args.append("--civic-review")
		browser.start_preparation(request,selected_slot)
		var status_path:String=browser.preparation_status
		await wait_for(func():
			if game_ready():return true
			if browser_ready() and current_scene.preparation_pid<0 and FileAccess.file_exists(status_path):
				var state=JSON.parse_string(FileAccess.get_file_as_string(status_path))
				return state is Dictionary and state.get("state","") in ["failed","cancelled"]
			return false,520)
		if not check(game_ready(),"complete production generation and native publication"):
			print("CIVIC_GENERATION_STATUS ",FileAccess.get_file_as_string(status_path));await finish();return
		FileAccess.open(folder.path_join("slot.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":selected_slot,"status":status_path}))
		await finish();return
	var saved=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("slot.json")))
	if not check(saved is Dictionary and str(saved.get("slot","")).begins_with("CivicReview_1703_"),"existing isolated review slot is identified"):await finish();return
	selected_slot=saved.slot
	restoration="--restore-trade" in OS.get_cmdline_user_args()
	Options.set_arguments(PackedStringArray(["--world-slot="+selected_slot,"--gameplay-construction","--ground-cover","--actors","--vehicle-fleet","--no-zombies"]),true)
	change_scene_to_file("res://demo/world.tscn");await scene_changed
	if not check(await wait_for(game_ready,120),"fresh process restores complete review world"):await finish();return
	var game=current_scene;game.background_fps=60;game.app_focused=true
	var worker:=Thread.new()
	worker.start(Plan.build.bind(1703,29,true,true,"user://civic_review_plans",Recipe.DEFAULTS,null,true))
	while worker.is_alive():await process_frame
	planned=worker.wait_to_finish()
	if not check(planned.get("ok",false),"exact civic plan reconstructed"):await finish();return
	for lot:Dictionary in planned.sites[0].lots:
		var id:String=lot.asset.get_meta("civic_id")
		var world_asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
		world_asset.compose([lot.asset],PackedInt32Array([0,lot.origin.x,lot.origin.y,lot.origin.z,lot.rotation]))
		approved_records[id]=world_asset.get_records();approved_lots[id]=lot
	if "--details-only" in OS.get_cmdline_user_args():
		check(Civic.prepare_landscape(game,planned.sites[0]),"bounded civic roof and approach tree clearance")
		game.ecosystem._structures_changed();game.terrain.changed_since_save=true
		for lot:Dictionary in planned.sites[0].lots:await inspect_detail(game,lot)
		FileAccess.open(folder.path_join("details.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":metrics},"  "))
		await finish();return
	await verify_approved_records(game)
	if not restoration and "--trade-only" not in OS.get_cmdline_user_args():
		for lot:Dictionary in planned.sites[0].lots:
			if only_role.is_empty() or only_role==lot.asset.get_meta("civic_id"):await inspect_civic(game,lot)
	if only_role.is_empty() or only_role=="trader_t1":await trade_world(game,planned.sites[0].lots[0])
	FileAccess.open(folder.path_join("restore.json" if restoration else ("trade.json" if "--trade-only" in OS.get_cmdline_user_args() else "result.json")),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"checks":checks,"slot":selected_slot,"gpu":RenderingServer.get_video_adapter_name(),"metrics":metrics},"  "))
	await finish()

func verify_approved_records(game:Node)->void:
	# Reuse exact-cell verification, not the city-specific access pass.
	for id:String in approved_records:
		if not only_role.is_empty() and id!=only_role:continue
		if "--trade-only" in OS.get_cmdline_user_args() and id!="trader_t1":continue
		var lot:Dictionary=approved_lots[id]
		game.teleport(lot.entrance.segment.finish+Vector3.UP)
		var bounds:AABB=lot.asset.placement_bounds(lot.origin,lot.rotation)
		if not check(await wait_for(func():return not game.loading_active and game.structures.is_collision_region_ready(bounds),90),id+" collision residency"):continue
		var exact:=true;var records:PackedInt32Array=approved_records[id]
		for offset in range(0,records.size(),4):
			if game.structures.blocks.get_cell(Vector3i(records[offset],records[offset+1],records[offset+2]))!=records[offset+3]:exact=false;break
		check(exact,id+" every saved block matches reviewed geometry")

func inspect_civic(game:Node,lot:Dictionary)->void:
	# Reuse populated native walks, LOD metrics and real vehicle approaches.
	lot.asset.set_meta("city_id",lot.asset.get_meta("civic_id"))
	for route:Dictionary in lot.asset.get_meta("stair_routes",[]):
		if route.kind in ["arrival","loading bay"]:
			lot.asset.set_meta("site_access_goal",route.end);break
	await inspect_access(game,lot)

func trade_world(game:Node,lot:Dictionary)->void:
	game.trader.ui.close();game.teleport(lot.entrance.segment.finish+Vector3.UP)
	if not check(await wait_for(func():return not game.loading_active and is_instance_valid(game.trader.actor),90),"exactly one resident trader activates with ready collision"):return
	game.set_physics_process(false);game._clear_motion();game.fly=false;game.needs_floor_spawn=false
	game.player.position=lot.entrance.segment.finish+Vector3.UP*.04
	game.camera.position=Vector3(0,1.65,0);game.camera.rotation=Vector3.ZERO
	for door_id:int in game.doors.collection.get_ids():
		var pose:PackedFloat32Array=game.doors.collection.get_instance(door_id)
		if pose.size()==12 and lot.bounds.grow(1).has_point(Vector3(pose[3],pose[7],pose[11])) and not game.doors.state.is_open(door_id):game.doors.state.toggle(game.doors.collection,door_id,AABB())
	var targets:=[point(lot,lot.asset.get_meta("site_entrance")),point(lot,Vector3(6.5,1,10.9))]
	for target:Vector3 in targets:
		for tick in 600:
			await physics_frame;game.app_focused=true
			var offset:Vector3=target-game.player.position;offset.y=0
			if offset.length()<.14:break
			game.player.velocity=game.movement.walking_velocity(offset.normalized(),game.player.velocity,1.0/60,false,game.player.is_on_floor(),false)
			game.movement.move_grounded(game.player,1.0/60)
		check(Vector2(game.player.position.x-target.x,game.player.position.z-target.z).length()<.2,"actual player walks continuously from street toward shop counter "+str(game.player.position))
	game.player.velocity=Vector3.ZERO
	game.camera.look_at(game.trader.anchor+Vector3.UP*1.45)
	game.app_focused=true
	var target:Dictionary=game.world_interaction.hit(game)
	check(game.world_interaction.describe(game,target)=="E · Trade supplies","normal world picker and interaction hint identify merchant")
	if not check(game.trader.try_open(target),"normal trader interaction owns inventory focus"):return
	check(game.player_hud.inventory_open and not game.player_hud.enabled,"trade pauses player inventory and movement controls")
	var inventory:RefCounted=game.player_hud.inventory
	var stock:RefCounted=game.trader.trader.stock
	if restoration:
		check(inventory.capture_storage_snapshot()==FileAccess.get_file_as_bytes(folder.path_join("expected_player.bin")),"fresh process restores exact post-trade player inventory")
		check(stock.capture_storage_snapshot()==FileAccess.get_file_as_bytes(folder.path_join("expected_stock.bin")),"fresh process restores finite merchant goods and purse without refill")
	else:
		# Explicit fixture reward in this new disposable review world only. No
		# starter coins are granted by the merchant or by opening existing saves.
		check(inventory.grant(210,20,inventory.snapshot().revision).ok,"review fixture supplies gathered twigs for zero-coin start")
		var initial_money:=Trade.count(inventory,601);var initial_wood:=Trade.count(inventory,102)
		var merchant_money:=Trade.count(stock,601);var merchant_wood:=Trade.count(stock,102)
		game.trader.ui.refresh();game.trader.ui.rows.select(7);game.trader.ui.quantity.get_line_edit().text="20";game.trader.ui.exchange(false)
		check(Trade.count(inventory,601)==initial_money+20 and Trade.count(stock,601)==merchant_money-20,"sell resources creates spendable coins through native two-party exchange")
		game.trader.ui.rows.select(1);game.trader.ui.quantity.get_line_edit().text="3";game.trader.ui.exchange(true)
		check(Trade.count(inventory,601)==initial_money+8 and Trade.count(inventory,102)==initial_wood+3 and Trade.count(stock,102)==merchant_wood-3,"normal buy UI transfers goods and exact price")
		check(game.terrain.changed_since_save,"trade marks compound world save dirty")
		for pair in [["expected_player.bin",inventory],["expected_stock.bin",stock]]:FileAccess.open(folder.path_join(pair[0]),FileAccess.WRITE).store_buffer(pair[1].capture_storage_snapshot())
		await photograph("trader_world_trade")
	game.trader.ui.close()
	check(not game.player_hud.inventory_open and game.player_hud.enabled,"closing returns normal gameplay controls")
	await photograph("trader_world_counter")
	var balance_before:PackedByteArray=inventory.capture_storage_snapshot()
	game.player.position=point(lot,Vector3(6,1,5.4));game.camera.look_at(game.trader.anchor+Vector3.UP*1.45)
	check(not game.trader.reachable() and not game.trader.try_open(game.world_interaction.hit(game)) and inventory.capture_storage_snapshot()==balance_before,"stockroom wall blocks buying and selling inside reach radius")
	var retained:PackedByteArray=stock.capture_storage_snapshot()
	game.teleport(planned.sites[1].center)
	check(await wait_for(func():return not game.loading_active and not is_instance_valid(game.trader.actor),90),"distant merchant visual and body retire")
	game.teleport(lot.entrance.segment.finish+Vector3.UP)
	check(await wait_for(func():return not game.loading_active and is_instance_valid(game.trader.actor),90) and stock.capture_storage_snapshot()==retained,"return activates one merchant without refilling inventory")
	game.set_physics_process(true)


func finish()->void:
	if is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn":
		current_scene.trader.ui.close();current_scene.shutdown_requested=true
		check(await current_scene.terrain.shutdown_after_edits(),"durable review-world save succeeds")
	if is_instance_valid(current_scene):current_scene.free()
	await process_frame
	print("CIVIC_WORLD checks=",checks," failures=",failures," slot=",selected_slot)
	quit(1 if failures else 0)

func inspect_detail(game:Node,lot:Dictionary)->void:
	var id:String=lot.asset.get_meta("civic_id")
	game.teleport(lot.entrance.segment.finish+Vector3.UP)
	if not check(await wait_for(func():return not game.loading_active and game.ecosystem.coverage_status().ready,90),id+" landscape resident before final photographs"):return
	game.set_physics_process(false);game._clear_motion();game.fly=true
	var bounds:AABB=lot.asset.placement_bounds(lot.origin,lot.rotation)
	game.camera.cull_mask&=~((1<<18)|(1<<19))
	game.camera.global_position=lot.entrance.segment.finish+Vector3(8,1.7,2)
	game.camera.look_at(Vector3(bounds.get_center().x,lot.origin.y+minf(bounds.size.y*.45,8),bounds.get_center().z))
	for frame in 60:await process_frame
	await photograph(id+"_street_final")
	game.camera.global_position=bounds.get_center()+Vector3(38,24,48);game.camera.look_at(bounds.get_center())
	for frame in 30:await process_frame
	await photograph(id+"_overview_final")
	if not lot.asset.has_meta("cellar_clearance"):return
	var routes:Array=lot.asset.get_meta("stair_routes",[])
	var body:=CharacterBody3D.new();body.collision_layer=8;body.collision_mask=7;body.floor_snap_length=.35;body.safe_margin=.004
	var capsule:=CapsuleShape3D.new();capsule.radius=.34;capsule.height=1.8
	var collider:=CollisionShape3D.new();collider.shape=capsule;collider.position.y=.9;body.add_child(collider);game.add_child(body)
	var motor:RefCounted=ClassDB.instantiate("NativePlayerMovement")
	for route:Dictionary in routes:
		if route.kind=="stairs" and route.start.y<4:
			await descend(game,body,motor,point(lot,route.end),point(lot,route.start),id)
			check(absf(body.position.y-point(lot,route.start).y)<.15,id+" basement floor supports actual capsule")
	body.free()
	game.camera.global_position=point(lot,Vector3(7,2.7,10));game.camera.look_at(point(lot,Vector3(3,2,5)))
	for frame in 30:await process_frame
	await photograph(id+"_basement_final")
	game.set_physics_process(true)

func descend(_game:Node,body:CharacterBody3D,motor:RefCounted,start:Vector3,finish:Vector3,label:String)->void:
	body.position=start;body.velocity=Vector3.ZERO
	var arrived:=false
	for tick in 600:
		await physics_frame
		var offset:=finish-body.position;offset.y=0
		var direction:=offset.normalized() if offset.length()>.05 else Vector3.ZERO
		body.velocity=motor.walking_velocity(direction,body.velocity,1.0/60,false,body.is_on_floor(),false)
		motor.move_grounded(body,1.0/60)
		if offset.length()<.15 and absf(body.position.y-finish.y)<.15 and body.is_on_floor():arrived=true;break
	check(arrived,label+" descends stairs and settles on basement floor "+str(body.position))

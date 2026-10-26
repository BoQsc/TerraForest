# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
class NearbyVehicleProbe extends RefCounted:
	var driving:=false
	var attempts:=0
	func enter(_game: Node) -> bool:attempts+=1;return true
func check_grass_harvest()->void:
	var candidates:Array=[]
	var find_grass:=func()->bool:
		for rows:Array in game.ground_cover.resident.values():
			var grass:Dictionary=rows[2]
			for index in grass.ids.size():
				var values:PackedFloat32Array=grass.transforms
				candidates.append({"id":grass.ids[index],"point":Vector3(values[index*12+3],values[index*12+7],values[index*12+11])})
		return not candidates.is_empty()
	if not check(await wait_for(find_grass,20),"natural grass publishes for harvesting"):return
	candidates.sort_custom(func(first:Dictionary,second:Dictionary)->bool:return first.point.distance_squared_to(game.player.position)<second.point.distance_squared_to(game.player.position))
	game.player_hud.equip_item(2);game._sync_player_tool()
	var selected:Dictionary={}
	for candidate:Dictionary in candidates.slice(0,64):
		aim(candidate.point+Vector3(0.7,0,1),candidate.point+Vector3(0,0.2,0))
		var target:Dictionary=game.world_attack.target()
		if target.get("id",0)==candidate.id and target.get("species",-1)==2:selected=candidate;break
	if not check(not selected.is_empty(),"hatchet targets actual natural grass"):return
	var before:=amount(205)
	use()
	check(game.ground_cover.batches[2].get_ids().has(selected.id) and amount(205)==before,"E cannot pick up the aimed grass")
	var active_slot:int=game.player_hud.active_slot
	var wear:int=game.player_hud.inventory.snapshot().slots[active_slot].wear
	if not check(game.world_attack.attack(),"actual hatchet harvest animation starts"):return
	check(await wait_for(func():return game.world_attack.pending.is_empty(),5) and game.world_attack.last_hit,"animated contact harvests the grass")
	check(not game.ground_cover.batches[2].get_ids().has(selected.id) and amount(205)==before+1,"one actual harvest removes exact clump and grants one grass")
	check(game.player_hud.inventory.snapshot().slots[active_slot].wear==wear+1,"accepted grass harvest wears the hatchet once")
func check_boulder()->void:
	var candidates:Array=[]
	var find_boulder:=func()->bool:
		for rows:Array in game.ground_cover.resident.values():
			var large:Dictionary=game.ground_cover.native.boulder_rows(rows[0])
			if not large.ids.is_empty():candidates.append(large);return true
		return false
	if not check(await wait_for(find_boulder,25),"natural boulder publishes"):return
	var large:Dictionary=candidates[0]
	var values:PackedFloat32Array=large.transforms
	var pose:=Transform3D(Basis(Vector3(values[0],values[4],values[8]),Vector3(values[1],values[5],values[9]),Vector3(values[2],values[6],values[10])),Vector3(values[3],values[7],values[11]))
	var point:=pose*Vector3(0,.05,.26)
	var eye:=point+pose.basis.z.normalized()*2.0
	aim(eye-Vector3(0,1.62,0),point)
	game.player_hud.equip_item(3);game._sync_player_tool()
	for frame in 8:await process_frame
	var origin:Vector3=game.camera.global_position
	var endpoint:Vector3=origin-game.camera.global_basis.z*2.5
	var probe:Dictionary=game.ground_interaction.collection_probe(origin,endpoint,game.world_interaction.hit(game))
	if not check(probe.ok and probe.hit.get("large",false) and probe.hit.id==large.ids[0],"actual aimed target is the natural boulder"):return
	game.world_interaction.update(game,1.0)
	check(game.player_hud.interaction_hint.text.is_empty() and not game.player_hud.interaction_hint.visible,"boulder has no obvious mining instruction")
	await RenderingServer.frame_post_draw
	var folder:=ProjectSettings.globalize_path("res://reports/ground_interaction_hint")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join("boulder-unlabeled.png"))==OK,"boulder evidence saved")
	var before_inventory:PackedByteArray=game.player_hud.capture_snapshot()
	var before_cover:PackedByteArray=game.ground_cover.removed.capture_storage_snapshot()
	use()
	check(game.player_hud.capture_snapshot()==before_inventory and game.ground_cover.removed.capture_storage_snapshot()==before_cover,"hiding label does not make the boulder collectable with E")
func run() -> void:
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"main world loads"):await finish();return
	game.set_physics_process(false);game._clear_motion()
	if not check(game.ground_enabled and game.construction_inventory.gameplay,"ground cover and gameplay enabled"):await finish();return
	if "--boulder-hint-check" in OS.get_cmdline_user_args():
		await check_boulder();await finish();return
	if "--grass-harvest-check" in OS.get_cmdline_user_args():
		await check_grass_harvest();await finish();return
	if not check(await wait_for(func():return game.ground_interaction.available() and not game.ground_cover.resident.is_empty(),15),"ground cover publishes for interaction"):await finish();return
	print("GROUND_HINT_COVER resident=",game.ground_cover.resident.size()," wanted=",game.ground_cover._wanted.size())
	var nearest:=Vector3.ZERO;var distance:=INF
	for rows: Array in game.ground_cover.resident.values():
		for row: Dictionary in rows:
			if game.ground_cover.Catalog.HARVEST_ONLY[rows.find(row)]:continue
			for i in row.ids.size():
				var t: PackedFloat32Array=row.transforms
				var point:=Vector3(t[i*12+3],t[i*12+7],t[i*12+11])
				if point.distance_squared_to(game.player.position)<distance:nearest=point;distance=point.distance_squared_to(game.player.position)
	aim(nearest+Vector3(0.7,0,1),nearest+Vector3(0,0.2,0))
	var origin: Vector3=game.camera.global_position
	var endpoint: Vector3=origin-game.camera.global_basis.z*2.5
	var probe: Dictionary=game.ground_interaction.pickup_probe(origin,endpoint)
	if not check(probe.ok,"actual nearby vegetation is reachable"):await finish();return
	var id: int=probe.hit.id;var species: int=probe.hit.species
	var catalog=preload("res://addons/world_ecosystem/ground_catalog.gd")
	var expected: String="E · Collect "+catalog.NAMES[species] if catalog.WORLD_HINTS[species] else ""
	if probe.hit.get("large",false):expected=""
	var inventory_before: PackedByteArray=game.player_hud.capture_snapshot()
	var edits_before: PackedByteArray=game.ground_cover.removed.capture_storage_snapshot()
	game.world_interaction.update(game,1.0)
	check(game.player_hud.interaction_hint.text==expected and game.player_hud.interaction_hint.visible==not expected.is_empty(),"HUD labels only noteworthy ground targets")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var folder:=ProjectSettings.globalize_path("res://reports/ground_interaction_hint")
		DirAccess.make_dir_recursive_absolute(folder)
		check(root.get_texture().get_image().save_png(folder.path_join("quiet.png"))==OK,"interaction screenshot saved")
	check(game.player_hud.capture_snapshot()==inventory_before and game.ground_cover.removed.capture_storage_snapshot()==edits_before,"prompt has no inventory or durable world mutation")
	# A shared building ray extends farther than gathering. Never expand reach.
	check(not game.ground_interaction.pickup_probe(origin,origin+(endpoint-origin).normalized()*0.1,{"position":endpoint}).ok,"longer shared scene ray does not extend collection reach")
	var cell: Vector2i=probe.hit.cell
	game.ground_cover._dirty[cell]=true
	check(not game.ground_interaction.pickup_probe(origin,endpoint).ok,"dirty owner cannot be advertised as collectible")
	game.ground_cover._dirty.erase(cell)
	var full: RefCounted=ClassDB.instantiate("NativePlayerInventory");full.register_item(104,999)
	check(full.grant(104,32*999,0).ok and game.player_hud.restore_snapshot(full.capture_storage_snapshot()),"full inventory fixture")
	var vehicle=game.world_vehicle;var nearby:=NearbyVehicleProbe.new();game.world_vehicle=nearby
	use();game.world_vehicle=vehicle
	check(nearby.attempts==0 and game._lake_notice.contains("room"),"full inventory reports rejection without entering nearby vehicle")
	check(game.ground_cover.removed.capture_storage_snapshot()==edits_before and game.ground_cover.batches[species].get_ids().has(id),"failed collection preserves target")
	check(game.player_hud.restore_snapshot(inventory_before),"restore original loadout")
	var reward: int=catalog.REWARDS[species];var before:=amount(reward)
	game.world_vehicle=nearby;use();game.world_vehicle=vehicle
	check(nearby.attempts==0 and game.ground_cover.removed.contains(id),"E collects aimed cover before proximity vehicle entry")
	check(amount(reward)==before+1,"collection grants exact species reward")
	game.world_interaction.update(game,1.0)
	check(not game.ground_interaction.pickup_probe(origin,endpoint).ok or game.ground_interaction.pickup_probe(origin,endpoint).hit.id!=id,"removed identity is no longer targetable")
	await finish()

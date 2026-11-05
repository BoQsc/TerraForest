# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"
var selected_slot:=""
var restoration:=false
var cleared:=false
var admission:=false
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	node_added.connect(func(node:Node):
		if node.scene_file_path=="res://demo/world.tscn":ProjectSettings.set_setting("terraforest/offscreen_session",true))
	super._initialize()
func run()->void:
	DirAccess.make_dir_recursive_absolute(folder)
	cleared="--cleared-homes" in OS.get_cmdline_user_args()
	admission="--admission-homes" in OS.get_cmdline_user_args()
	restoration=cleared or admission or "--restore-homes" in OS.get_cmdline_user_args()
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed
	await wait_for(browser_catalog_ready)
	var browser=current_scene
	if restoration:
		var receipt:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("homes.json")))
		selected_slot=receipt.slot
		if not check(selected_slot.begins_with("SleeperHomes_"),"fresh-process check owns its test world"):await finish();return
		var index:=-1
		for candidate in browser.worlds.item_count:
			if browser.worlds.get_item_metadata(candidate)==selected_slot:index=candidate;break
		if not check(index>=0,"normal browser lists the generated sleeper world"):await finish();return
		browser.worlds.select(index);browser.launch_selected(false)
	else:
		selected_slot="SleeperHomes_1703_"+Crypto.new().generate_random_bytes(4).hex_encode()
		FileAccess.open(folder.path_join("created_slot.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":selected_slot}))
		browser.name_field.text=selected_slot;browser.seed_field.value=1703;browser.world_tabs.current_tab=1
		check(browser.selected_options()==preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS,"unchanged normal UI recipe creates house sleepers")
		browser.generate_button.pressed.emit()
	if not check(await wait_for(game_ready,520),"ordinary browser generation/load reaches playable world"):await finish();return
	var game=current_scene;game.background_fps=60;game.app_focused=true;game.set_physics_process(false)
	game.zombies.update(0,game.player.global_position,false)
	var store:RefCounted=game.zombies.population.store
	if not restoration:await verify_large_buildings(game,store)
	var anchors:Array=[]
	for identity in range(2501,int(store.statistics().slots)+1):
		var record:Dictionary=store.resident(identity)
		if record.anchor!=0:anchors.append(record)
	if not check(not anchors.is_empty(),"ordinary generation persists authored house residents before player arrival"):await finish();return
	var selected:Dictionary=anchors[0]
	if admission:selected=anchors.back()
	elif restoration:
		var receipt:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("homes.json")))
		selected=store.resident(int(receipt.identity))
		check(selected.anchor==int(receipt.anchor) and (selected.state==2 if cleared else selected.vitals==Marshalls.base64_to_raw(receipt.vitals)),"fresh process restores stable authored identity and damage/death")
	game.teleport(selected.position+Vector3(0,0,12))
	if not check(await wait_for(func():return not game.loading_active,90),"house approach streams terrain, furniture and resident collision"):await finish();return
	game.set_physics_process(false);game.zombies.update(0,game.player.global_position,false)
	var matches:Array=game.zombies.residents.filter(func(actor:Node3D):return actor.get_meta("world_zombie_id",0)==selected.id)
	if cleared:
		check(matches.is_empty() and selected.state==2 and selected.sleep.is_empty(),"cleared house stays cleared after normal fresh-process load")
		check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED and preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"cleared-house check never captures desktop pointer")
		await finish();return
	if not check(matches.size()==1,"normal residency admits exactly one authored inhabitant"):await finish();return
	var actor:CharacterBody3D=matches[0]
	check(game.zombies.awareness.status(actor.get_instance_id()).ambusher,"authored resident retains sleeper temperament across actual-world admission/reload")
	if admission:
		game.zombies._retire(game.zombies.residents.find(actor));await process_frame
		game.camera.look_at(selected.position+Vector3.UP*.5)
		game.zombies.population.reset_stream()
		var deadline:=Time.get_ticks_msec()+10000
		while Time.get_ticks_msec()<deadline:
			game.zombies.population.advance(game.player.global_position,false)
			await process_frame
			matches=game.zombies.residents.filter(func(resident:Node):return resident.get_meta("world_zombie_id",0)==selected.id)
			if not matches.is_empty():break
		check(matches.size()==1 and matches[0].sleeper_active(),"nonloading admission finds the sleeping house resident behind real walls")
		check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED and preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"admission check never captures desktop pointer")
		await finish();return
	check(actor.global_position.distance_to(selected.position)<.15,"house resident remains on the authored floor rather than the roof")
	check(not actor.sleeper_active() if restoration else actor.sleeper_active(),"resident restores its actual awake/asleep state without resetting")
	game.tool_view.hide();game.player_hud.set_open(false)
	var camera:=Camera3D.new();game.add_child(camera);camera.current=true
	camera.global_position=actor.global_position+Vector3(1.8,1.0,2.1);camera.look_at(actor.global_position+Vector3.UP*.5)
	await photograph("restored_house" if restoration else "sleeping_house")
	if not restoration:
		game.zombies.update(0,game.player.global_position,true)
		game.zombies.hear_noise(actor.global_position,5.)
		var deadline:=Time.get_ticks_msec()+8000
		while actor.sleeper_active() and Time.get_ticks_msec()<deadline:
			await physics_frame;game.zombies.update(1./60.,game.player.global_position,true)
		check(not actor.sleeper_active(),"house sleeper completes wake with real floor, walls and furnishings")
		var before:float=actor.anatomy.snapshot().health
		actor.receive_hit("torso",4.,actor.global_position+Vector3.UP,Vector3.ZERO)
		check(actor.anatomy.snapshot().health<before,"test strike really damages the resident before saving")
		game.zombies.update(0,game.player.global_position,false)
		await photograph("awakened_house")
		game.zombies.population.sync(actor)
		FileAccess.open(folder.path_join("homes.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":selected_slot,"identity":selected.id,"anchor":selected.anchor,"vitals":Marshalls.raw_to_base64(actor.anatomy.capture_vitals())}))
	else:
		actor.receive_hit("torso",1000.,actor.global_position+Vector3.UP,Vector3.ZERO)
		game.zombies.population.sync(actor)
		check(not actor.alive and store.resident(selected.id).state==2,"clearing the house records permanent resident death")
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED and preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"integrated house check never captures the desktop pointer")
	await finish()

func verify_large_buildings(game:Node,store:RefCounted)->void:
	var options:Dictionary=game.world_recipe.store.decode(game.world_recipe.store.capture_snapshot())
	var worker:=Thread.new()
	worker.start(preload("res://addons/world_runtime/world_generation_plan.gd").build.bind(1703,29,true,true,"user://generation_plans",options))
	while worker.is_alive():await process_frame
	var generated:Dictionary=worker.wait_to_finish()
	var lots:Array=[]
	for site:Dictionary in generated.get("sites",[]):lots.append_array(site.lots)
	var planned:Dictionary=preload("res://addons/characters/runtime/house_sleepers.gd").plan(lots,1703)
	if not check(generated.get("ok",false) and planned.ok and not planned.buildings.is_empty(),"normal UI recipe actually includes larger-building resident groups"):return
	var bytes:PackedByteArray=store.capture_snapshot();var sanctuary:=Vector3(bytes.decode_float(16),bytes.decode_float(20),bytes.decode_float(24))
	var positions:Dictionary={}
	for anchor:Dictionary in planned.anchors:positions[anchor.key]=anchor.position
	var receipt:Array=[]
	for building:Dictionary in planned.buildings:
		var identities:PackedInt64Array=store.authored_identities(building.keys)
		var actual:=0;var expected:=0;var correct:bool=identities.size()==building.keys.size()
		for index in identities.size():
			var offset:Vector3=positions[building.keys[index]]-sanctuary;offset.y=0
			if offset.length()>=40:expected+=1
			if identities[index]>0:
				actual+=1;correct=correct and store.resident(identities[index]).anchor==building.keys[index]
		check(correct and actual==expected and building.keys.size()>=3,"generated %s has its persistent small group (%d residents, %d sanctuary exemptions)"%[building.building,actual,building.keys.size()-expected])
		receipt.append({"building":building.building,"origin":building.origin,"expected":expected,"actual":actual,"ids":identities})
	FileAccess.open(folder.path_join("large_buildings.json"),FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
	for row:Dictionary in receipt:
		if row.building!="warehouse_w1" or row.actual<3:continue
		var first:Dictionary=store.resident(row.ids[0])
		game.teleport(first.position+Vector3(0,0,10),first.position.y)
		if not check(await wait_for(func():return not game.loading_active,90),"normal loading prepares the new warehouse group"):break
		var present:Array=game.zombies.residents.filter(func(actor:Node):return row.ids.has(int(actor.get_meta("world_zombie_id",0))))
		check(present.size()==row.actual and present.all(func(actor:Node):return actor.sleeper_active()),"all three warehouse residents enter normal scene residency together")
		check(game.zombies.residency_limit==16,"authored building group uses the existing bounded encounter pool")
		if not present.is_empty():
			var camera:=Camera3D.new();game.add_child(camera);camera.current=true
			camera.position=present[0].position+Vector3(3,1.6,3);camera.look_at(present[0].position+Vector3.UP*.6)
			await photograph("warehouse_resident");camera.free();game.camera.current=true
		break
func finish()->void:
	if game_ready():
		current_scene.shutdown_requested=true
		check(await current_scene.terrain.shutdown_after_edits(),"generated sleeper world saves durably")
	if is_instance_valid(current_scene):current_scene.free()
	await process_frame
	print("HOUSE_SLEEPERS_WORLD checks=",checks," failures=",failures)
	quit(1 if failures else 0)

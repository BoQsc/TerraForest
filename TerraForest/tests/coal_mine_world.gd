# SPDX-License-Identifier: 0BSD
extends "res://tests/exploration_world.gd"
const Rails=preload("res://addons/structures/mine_rail_catalog.gd")
var site:Dictionary
func item_count(item:int)->int:
	var total:=0
	for row:Dictionary in game.player_hud.inventory.snapshot().slots:
		if row.item==item:total+=row.count
	return total
func coal_count()->int:return item_count(220)
func verify_pose_adapter()->void:
	var held:int=game.player_hud.active_item;var position:Vector3=game.player.position;var previous:PackedByteArray=game._saved_pose
	for tool:int in [0]+game.player_hud.CATALOG.keys():
		game.player_hud.active_item=tool
		var encoded:PackedByteArray=game._capture_player_pose();var decoded:Dictionary=game.player_pose.decode(encoded)
		check(decoded.get("ok",false) and decoded.get("position")==position and decoded.get("tool")== (tool if tool in [1,2,3,4] else 0),"live pose adapter saves current position with catalog selection "+str(tool))
	var valid:PackedByteArray=game._saved_pose
	var pitch:float=game.pitch;game.pitch=2.0
	check(not game.player_pose.validate_snapshot(game._capture_player_pose()),"invalid current on-foot pose rejects the compound save instead of reusing an old pose")
	game.pitch=pitch;game.loading_active=true
	check(game._capture_player_pose()==valid,"loading retains the last valid player pose")
	game.loading_active=false;game.waiting_spawn=true
	check(game._capture_player_pose()==valid,"pending spawn retains the last valid player pose")
	game.waiting_spawn=false;game.player_hud.active_item=held;game._saved_pose=previous
func station_body_count(station:Array)->int:
	var bodies:Array=game.zombies.residents.filter(func(actor:Node):return actor.get_meta("world_zombie_id",0) in station)
	var records:Array=[]
	for identity:int in station:
		var record:Dictionary=game.zombies.population.store.resident(identity)
		var row:Dictionary={"id":identity,"state":record.state,"position":record.position,"loaded":bodies.any(func(actor:Node):return actor.get_meta("world_zombie_id",0)==identity)}
		if record.state==1 and not row.loaded:
			row.support=game.zombies.supported_resident_point(record.position,record.sleep.is_empty())
			var query:=PhysicsShapeQueryParameters3D.new();query.shape=game.zombies._resident_capsule
			query.transform=Transform3D(Basis.IDENTITY,Vector3(record.position)+Vector3.UP*(game.zombies._resident_capsule.height*.5));query.collision_mask=15|(1<<16)|(1<<18)
			row.clearance=[]
			for hit:Dictionary in game.get_world_3d().direct_space_state.intersect_shape(query,8):
				var collider:Node=hit.collider;var asset:=""
				for key:String in game.structures._models:
					if game.structures._models[key]==collider:asset=key;break
				row.clearance.append({"type":collider.get_class(),"asset":asset,"resident":collider.get_meta("world_zombie_id",0)})
		records.append(row)
	print("COAL_STATION_RESIDENCY ",JSON.stringify({"bodies":bodies.size(),"limit":game.zombies.residency_limit,"population":game.zombies.population.status(),"records":records}))
	return bodies.size()
func build_rail()->void:
	var before_wood:=item_count(102);var before_metal:=item_count(104)
	var pose:=Transform3D(Basis(Vector3.UP,-site.rotation*PI*.5),local(Vector3(-3,0,31)))
	var values:=PackedFloat32Array()
	for row in 3:
		for column in 3:values.append(pose.basis[column][row])
		values.append(pose.origin[row])
	var collection:Node=game.structures.model(Rails.key("short"))
	var identity:int=game._place_inventory_model(game.model_tool.history,collection,values,game.model_tool.protection(),Rails.recipe("short"))
	check(identity>0 and item_count(102)==before_wood-2 and item_count(104)==before_metal-2,"normal assembly payment places a reusable rail using chest materials")
func local(point:Vector3)->Vector3:return Vector3(site.origin)+Layouts.turn(point,site.rotation)
func path(points:Array)->bool:
	for point:Vector3 in points:
		if not check(await walk(local(point)),"physical mine route: "+str(point)):return false
	return true
func save_expected()->void:
	expected.rails={}
	for part:String in Rails.PARTS:
		var key:=Rails.key(part);var collection:Node=game.structures.model(key);var placements:Dictionary={}
		for identity:int in collection.get_ids():placements[identity]=collection.get_instance(identity)
		expected.rails[key]=placements
	expected.storage=game.storage.store.capture_storage_snapshot()
	FileAccess.open(folder.path_join("expected.bin"),FileAccess.WRITE).store_var(expected)
func run()->void:
	DirAccess.make_dir_recursive_absolute(folder)
	var restore:bool="--restore-exploration" in OS.get_cmdline_user_args()
	var inside_restore:bool="--coal-inside-restore" in OS.get_cmdline_user_args()
	var complete_return:bool="--coal-complete-return" in OS.get_cmdline_user_args()
	var reuse:=""
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--coal-reuse-slot="):reuse=argument.trim_prefix("--coal-reuse-slot=")
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed;await wait_for(browser_catalog_ready)
	var browser=current_scene
	if restore or not reuse.is_empty():
		expected=FileAccess.open(folder.path_join("expected.bin"),FileAccess.READ).get_var() if restore else {"slot":reuse}
		if not check(str(expected.slot).begins_with("CoalMine_"),"restore only owned coal-mine test world"):await finish();return
		var selected:=-1
		for index in browser.worlds.item_count:
			if browser.worlds.get_item_metadata(index)==expected.slot:selected=index;break
		if not check(selected>=0,"My worlds lists the generated coal-mine world"):await finish();return
		browser.worlds.select(selected);browser.launch_selected(false)
	else:
		expected.slot="CoalMine_1703_"+Crypto.new().generate_random_bytes(4).hex_encode()
		FileAccess.open(folder.path_join("created_slot.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":expected.slot}))
		browser.name_field.text=expected.slot;browser.seed_field.value=1703;browser.world_tabs.current_tab=1
		check(browser.selected_options()==preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS,"Generate & play uses unchanged default options, no content switches")
		browser.generate_button.pressed.emit()
	if not check(await wait_for(game_ready,520),"ordinary generation/load reaches gameplay"):await finish();return
	game=current_scene;game.background_fps=60;game.app_focused=true;game.set_physics_process(false);game._clear_motion()
	check(await wait_for(func():return not game.player_view.entry.active,45),"normal world-entry presentation finishes before walking")
	var locations:Array=game.quests.store.get_locations().filter(func(row:Dictionary):return row.layout=="coal_mine")
	if not check(locations.size()==1,"ordinary publication owns one coal mine and publishes it on the map"):await finish();return
	site=locations[0]
	check(game.generated_region.store.get_plan().places.any(func(row:Dictionary):return row.title=="Blackridge coal mine"),"normal world map exposes the mine approach")
	check(game.model_tool.catalog.filter(func(row:Dictionary):return row.title in Rails.PARTS.values()).size()==5,"assembly catalog exposes all five modular rails")
	var store:RefCounted=game.zombies.population.store
	var station:Array=[]
	for identity in range(2501,int(store.statistics().slots)+1):
		var row:Dictionary=store.resident(identity)
		if (int(row.anchor)&(1<<43))!=0:station.append(row.id)
	check(station.size()==10 and site.residents.size()==13,"ten deep-station residents plus three side-passage sleepers persist")
	# A separate process must resume the saved underground player pose naturally.
	# Normal teleport resolves the surface, so every other journey enters outside.
	if inside_restore:
		print("COAL_PLAYER_RESTORE ",JSON.stringify({"expected":expected.get("inside_pose"),"actual":game.player.global_position,"saved":game.player_pose.decode(game._saved_pose),"saved_selection":expected.get("inside_tool"),"active_selection":game.player_hud.active_item,"torches":item_count(6)}))
		if not check(expected.has("inside_pose") and game.player.global_position.distance_to(expected.inside_pose)<.45,"normal browser reopen restores the actual saved underground player pose"):await finish();return
		check(item_count(6)==expected.torches,"legacy pose mode preserves the torch in its separate inventory")
	else:
		game.teleport(local(Vector3(.5,0,2) if complete_return else Vector3(.5,0,-7)))
	if not check(await wait_for(func():return not game.loading_active,90),"mine collision and authored population stream before entry"):await finish();return
	game.set_physics_process(false);game.zombies.update(0,game.player.global_position,false)
	if complete_return:
		# Diagnostic continuation only: the retained journey already saved its
		# loot, placed rail and dead resident before an exterior-height assertion.
		var dead:Array=station.filter(func(identity:int):return store.resident(identity).state==2)
		if not check(dead.size()==1 and coal_count()>0,"retained journey restores its killed resident and harvested coal"):await finish();return
		expected.station=station;expected.killed=dead[0];expected.coal=coal_count()
		if not check(await walk(local(Vector3(.5,0,-7)),true),"physical exit follows the natural hillside grade"):await finish();return
		save_expected();await photograph("coal_exit_completed");await finish();return
	if restore:
		if not inside_restore:verify_pose_adapter()
		check(station==expected.station,"fresh process restores all ten stable station identities")
		check(store.resident(expected.killed).state==2,"killed station zombie remains dead")
		check(game.storage.store.capture_storage_snapshot()==expected.storage,"looted mine supplies remain depleted")
		check(coal_count()==expected.coal,"mined coal restores in the player inventory")
		for key:String in expected.rails:
			var collection:Node=game.structures.model(key)
			for identity:int in expected.rails[key]:check(collection.get_instance(identity)==expected.rails[key][identity],"rail placement survives fresh-process world restore")
		game.player_hud.equip_item(6)
		if inside_restore:
			if not await path([Vector3(.5,0,46),Vector3(.5,0,43)]):await finish();return
		else:
			if not await path([Vector3(.5,0,2),Vector3(.5,0,7),Vector3(.5,0,12.5),Vector3(.5,0,22.5),Vector3(.5,0,32.5),Vector3(.5,0,43)]):await finish();return
		check(station_body_count(station)==9,"all nine surviving station bodies restore during physical re-entry")
		game.camera.look_at(local(Vector3(.5,2,52)));await photograph("coal_station_inside_reopened" if inside_restore else "coal_station_restored")
		if not inside_restore:
			expected.inside_pose=game.player.global_position
			expected.inside_tool=game.player_hud.active_item;expected.torches=item_count(6)
			FileAccess.open(folder.path_join("expected.bin"),FileAccess.WRITE).store_var(expected)
		await finish();return
	expected.station=station
	game.camera.look_at(local(Vector3(.5,2,4)));await photograph("coal_mine_entrance")
	if not await path([Vector3(.5,0,2)]):await finish();return
	game.camera.look_at(local(Vector3(.5,1,4.5)))
	check(game.doors.try_interact(),"normal three-metre picking opens the mine entrance door")
	for tick in 60:await physics_frame
	game.player_hud.equip_item(6)
	if not await path([Vector3(.5,0,7),Vector3(.5,0,12.5),Vector3(6,0,12.5),Vector3(9.5,0,12.5)]):await finish();return
	game.camera.look_at(local(Vector3(11,.4,13.5)))
	if not await open_supply():await finish();return
	for transfer:Array in [[0,2],[1,2],[2,1]]:
		game.storage.storage_list.select(transfer[0]);game.storage.quantity.get_line_edit().text=str(transfer[1]);check(game.storage.move_selected(false),"dead-end chest supplies transfer through storage UI")
	game.storage.close();game.player_hud.equip_item(6)
	await photograph("coal_short_dead_end")
	if not await path([Vector3(6,0,12.5),Vector3(.5,0,12.5),Vector3(.5,0,22.5),Vector3(6,0,22.5),Vector3(9,0,22.5)]):await finish();return
	game.camera.look_at(local(Vector3(10,.4,23.5)))
	if not await open_supply():await finish();return
	game.storage.close()
	if not await path([Vector3(6,0,22.5),Vector3(.5,0,22.5),Vector3(.5,0,32.5)]):await finish();return
	build_rail()
	if not await path([Vector3(-3.5,0,36.5),Vector3(-15.5,0,36.5),Vector3(-19.5,0,32.5)]):await finish();return
	game.camera.look_at(local(Vector3(-19.5,1,24.5)));await photograph("coal_loop_gallery")
	if not await path([Vector3(-19.5,0,20.5),Vector3(-15.5,0,16.5),Vector3(-3.5,0,16.5),Vector3(.5,0,20.5),Vector3(.5,0,32.5),Vector3(.5,0,43)]):await finish();return
	game.camera.look_at(local(Vector3(.5,2,53)));await photograph("coal_deep_station")
	if not await path([Vector3(.5,0,48),Vector3(.5,0,54)]):await finish();return
	var actors:Array=game.zombies.residents.filter(func(actor:Node):return actor.get_meta("world_zombie_id",0) in station)
	check(actors.size()==10,"all ten station zombies are physically present together")
	game.camera.look_at(local(Vector3(3.5,1,51)));await photograph("coal_station_zombies")
	game.zombies.update(0,game.player.global_position,true);game.zombies.hear_noise(local(Vector3(.5,0,51)),18)
	for tick in 240:
		await physics_frame;game.zombies.update(1./60.,game.player.global_position,true)
	check(actors.all(func(actor:Node):return not actor.sleeper_active()),"all ten station residents can complete waking in actual building collision")
	if not actors.is_empty():
		var actor:Node=actors[0];expected.killed=actor.get_meta("world_zombie_id")
		actor.receive_hit("torso",1000.,actor.global_position+Vector3.UP,Vector3.ZERO);game.zombies.population.sync(actor)
	game.zombies.update(0,game.player.global_position,false)
	# The nearest coal heap is outside the station traffic aisle.
	if not await path([Vector3(.5,0,58),Vector3(2.5,0,59)]):await finish();return
	game.camera.look_at(local(Vector3(4,.3,59)));game.player_hud.equip_item(1)
	var target:Dictionary=game.world_attack.target();var before:=coal_count()
	check(target.get("asset","")=="resources/coal_heap/v1" and game.world_attack.apply_target(target),"normal pickaxe contact harvests original coal model")
	check(coal_count()>before,"coal is an inventory resource")
	expected.coal=coal_count()
	# Awake residents converge on the central aisle. Use the station's side
	# clearance instead of asking the walking controller to pass through bodies.
	if not await path([Vector3(-2,0,59),Vector3(-2,0,46),Vector3(.5,0,43),Vector3(.5,0,32.5),Vector3(.5,0,22.5),Vector3(.5,0,12.5),Vector3(.5,0,7),Vector3(.5,0,2)]):await finish();return
	if not check(await walk(local(Vector3(.5,0,-7)),true),"physical exit follows the natural hillside grade"):await finish();return
	check(true,"complete mine journey returns through its working door to outside")
	save_expected()
	frames.sort();FileAccess.open(folder.path_join("walk_timing.json"),FileAccess.WRITE).store_string(JSON.stringify({"samples":frames.size(),"p95_ms":frames[int(frames.size()*.95)],"worst_ms":frames.back(),"scope":"Offscreen collision walks; not foreground frame pacing"}))
	await finish()
func finish()->void:
	check(preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"test never captures desktop pointer")
	if game_ready():
		current_scene.shutdown_requested=true;check(await current_scene.terrain.shutdown_after_edits(),"mine world saves durably")
	if is_instance_valid(current_scene):current_scene.free()
	await process_frame;print("COAL_MINE_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"
const Layouts=preload("res://addons/exploration/cave_layouts.gd")
var game:Node
var expected:Dictionary={}
var frames:Array[float]=[]
var locks_opened:=0
func open_supply()->bool:
	var identity:int=game.storage.aimed_id()
	if not check(identity>0,"actual supply chest is selected by live scene ray"):return false
	if game.storage.store.is_locked(identity):
		check(game.storage.store.lock_state(identity).maximum==180,"generated lock has twice the normal chest durability")
		game.player_hud.equip_item(2)
		for strike in ceili(float(game.storage.store.lock_state(identity).remaining)/30.):
			var target:Dictionary=game.world_attack.target()
			if not check(target.get("kind")=="model" and target.get("id")==identity and game.world_attack.apply_target(target),"live hatchet contact adapter damages generated chest lock"):return false
			if strike==2:await photograph("generated_chest_partial_lock")
		check(not game.storage.store.is_locked(identity) and game.storage.collection.is_removal_protected(identity),"hatchet hits open lock without losing chest or contents")
		locks_opened+=1
	if not game.storage.opened:game.storage.try_open()
	return check(game.storage.opened,"actual supply storage opens and blocks player control")
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true)
	node_added.connect(func(node:Node):
		if node.scene_file_path=="res://demo/world.tscn":ProjectSettings.set_setting("terraforest/offscreen_session",true))
	super._initialize()
func walk(target:Vector3,follow_ground:bool=false)->bool:
	game.session_menu.developer_hud.mouse_access=true
	game.fly=false;game.needs_floor_spawn=false;game.controls.clear(Time.get_ticks_usec())
	game.camera.position=Vector3(0,1.65,0);game.camera.rotation=Vector3.ZERO
	var began:=Time.get_ticks_usec();var previous:=began;var reached:=false
	while Time.get_ticks_usec()-began<16000000:
		var offset:Vector3=target-game.player.position;offset.y=0
		if offset.length()<.25 and (game.player.is_on_floor() if follow_ground else absf(game.player.position.y-target.y)<.4):reached=true;break
		game.yaw=atan2(-offset.x,-offset.z);game.player.rotation.y=game.yaw
		game.controls.set_key(KEY_W,true,Time.get_ticks_usec())
		await physics_frame;game.app_focused=true;game._physics_process(1./60.)
		var now:=Time.get_ticks_usec();frames.append((now-previous)/1000.);previous=now
	if not reached:
		print("EXPLORATION_BLOCKED velocity=",game.player.velocity," floor=",game.player.is_on_floor()," normal=",game.player.get_floor_normal())
		for index in game.player.get_slide_collision_count():
			var hit:KinematicCollision3D=game.player.get_slide_collision(index)
			print("EXPLORATION_COLLISION ",hit.get_collider()," at=",hit.get_position()," normal=",hit.get_normal())
		await photograph("blocked_walk")
	game.controls.clear(Time.get_ticks_usec());game._clear_motion();game.session_menu.developer_hud.mouse_access=false
	print("EXPLORATION_WALK target=",target," actual=",game.player.position," reached=",reached)
	return reached
func run()->void:
	DirAccess.make_dir_recursive_absolute(folder)
	var restore:bool="--restore-exploration" in OS.get_cmdline_user_args()
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed
	await wait_for(browser_catalog_ready)
	var browser=current_scene
	if restore:
		expected=FileAccess.open(folder.path_join("expected.bin"),FileAccess.READ).get_var()
		if not check(str(expected.slot).begins_with("Exploration_"),"restore only this test's world"):await finish();return
		var selected:=-1
		for index in browser.worlds.item_count:
			if browser.worlds.get_item_metadata(index)==expected.slot:selected=index;break
		if not check(selected>=0,"ordinary browser lists the generated world"):await finish();return
		browser.worlds.select(selected);browser.launch_selected(false)
	else:
		expected.slot="Exploration_1703_"+Crypto.new().generate_random_bytes(4).hex_encode()
		FileAccess.open(folder.path_join("created_slot.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":expected.slot}))
		browser.name_field.text=expected.slot;browser.seed_field.value=1703;browser.world_tabs.current_tab=1
		check(browser.selected_options()==preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS,"unchanged ordinary browser recipe includes exploration")
		browser.generate_button.pressed.emit()
	if not check(await wait_for(game_ready,520),"normal generation/load reaches gameplay"):await finish();return
	game=current_scene;game.background_fps=60;game.app_focused=true;game.set_physics_process(false);game._clear_motion()
	if not check(preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"browser transition preserved offscreen no-capture mode"):await finish();return
	var store:RefCounted=game.zombies.population.store
	game.zombies.update(0,game.player.global_position,false)
	var anchors:Array=[];var locations:Dictionary={}
	for identity in range(2501,int(store.statistics().slots)+1):
		var row:Dictionary=store.resident(identity);var key:int=row.anchor
		if (key&(1<<40))==0:continue
		anchors.append(row)
		var origin:=Vector3i((key&2047)-1,(key>>29)&1023,((key>>11)&2047)-1)
		if not locations.has(origin):locations[origin]={"origin":origin,"rotation":(key>>22)&3,"anchors":[]}
		locations[origin].anchors.append(row.id)
	if not check(anchors.size()==18 and locations.size()==3,"ordinary generation saves three underground sites and eighteen keyed sleepers"):await finish();return
	var places:Array=game.generated_region.store.get_plan().places
	check(places.filter(func(place:Dictionary):return place.title in ["Abandoned survey mine","Split-rock cave","Blackridge coal mine"]).size()==3,"all actual underground locations are published on the map")
	if not await check_watchtowers(restore):await finish();return
	if restore:
		check(game.storage.store.capture_storage_snapshot()==expected.storage,"fresh process restores exact depleted supplies without refill")
		check(store.resident(expected.killed).state==2,"cleared underground resident stays dead")
		check(anchors.map(func(row:Dictionary):return row.anchor)==expected.anchors,"all underground resident identities persist")
		await finish();return
	expected.anchors=anchors.map(func(row:Dictionary):return row.anchor)
	expected.killed=0;expected.chests=[]
	for origin:Vector3i in locations:
		var site:Dictionary=locations[origin];var rotation:int=site.rotation
		# The complete coal loop/station/door/harvest journey has its own normal-
		# browser create/restore driver in coal_mine_world.gd.
		if site.anchors.size()==13:continue
		var layout:Dictionary=Layouts.load_catalog()[0 if site.anchors.size()==3 else 1]
		var mouth:=Vector3(origin)+Layouts.turn(Vector3(.5,0,-7),rotation)
		game.teleport(mouth)
		if not check(await wait_for(func():return not game.loading_active,90),"actual world streams entrance terrain, structures and encounters"):await finish();return
		game.set_physics_process(false);game.zombies.update(0,game.player.global_position,false)
		game.camera.look_at(Vector3(origin)+Layouts.turn(Vector3(.5,1.8,4),rotation))
		await photograph(layout.id+"_world_entrance")
		var path:Array=[Vector3(.5,0,.5),Vector3(.5,0,6.5)]
		path.append_array([Vector3(.5,0,11),Vector3(2.5,0,12)] if layout.id=="survey_mine" else [Vector3(-3.5,0,11.5),Vector3(-4.5,0,14.5)])
		for point:Vector3 in path:
			if not check(await walk(Vector3(origin)+Layouts.turn(point,rotation)),"real player walks entrance-to-chamber: "+str(point)):await finish();return
		game.zombies.update(0,game.player.global_position,false)
		var crate_position:=Vector3(origin)+Layouts.turn(Layouts.point(layout.crates[0]),rotation)
		game.camera.look_at(crate_position+Vector3.UP*.4)
		if not await open_supply():await finish();return
		if game.storage.opened:
			var identity:int=game.storage.identity;expected.chests.append(identity)
			check(game.storage.store.snapshot(identity).slots[0].count>=3,"underground chest contains generated supplies")
			game.storage.storage_list.select(0);game.storage.quantity.get_line_edit().text="1"
			check(game.storage.move_selected(false),"storage UI transfers one generated supply into backpack")
			game.storage.close()
		await photograph(layout.id+"_world_chamber")
		var residents:Array=game.zombies.residents.filter(func(actor:Node):return actor.get_meta("world_zombie_id",0) in site.anchors)
		check(not residents.is_empty(),"ordinary streaming admits actual underground residents")
		if not residents.is_empty():
			var actor:CharacterBody3D=residents[0]
			game.zombies.update(0,game.player.global_position,true);game.zombies.hear_noise(actor.global_position,5.)
			var deadline:=Time.get_ticks_msec()+8000
			while actor.sleeper_active() and Time.get_ticks_msec()<deadline:
				await physics_frame;game.zombies.update(1./60.,game.player.global_position,true)
			check(not actor.sleeper_active(),"resident hears and completes wake in populated cave collision")
			if expected.killed==0:
				expected.killed=actor.get_meta("world_zombie_id");actor.receive_hit("torso",1000.,actor.global_position+Vector3.UP,Vector3.ZERO)
				game.zombies.population.sync(actor);check(store.resident(expected.killed).state==2,"underground death is persisted as cleared")
		game.zombies.update(0,game.player.global_position,false)
	expected.storage=game.storage.store.capture_storage_snapshot()
	print("GENERATED_LOCKS_OPENED ",locks_opened)
	FileAccess.open(folder.path_join("expected.bin"),FileAccess.WRITE).store_var(expected)
	frames.sort();FileAccess.open(folder.path_join("walk_timing.json"),FileAccess.WRITE).store_string(JSON.stringify({"samples":frames.size(),"p95_ms":frames[int(frames.size()*.95)] if not frames.is_empty() else 0,"worst_ms":frames.back() if not frames.is_empty() else 0,"scope":"Offscreen physical player entrance walks; no foreground frame-pacing qualification"}))
	await finish()
func check_watchtowers(restore:bool)->bool:
	var store:RefCounted=game.zombies.population.store
	var towers:Array=[]
	for identity in range(2501,int(store.statistics().slots)+1):
		var resident:Dictionary=store.resident(identity)
		if (int(resident.anchor)&(1<<41))!=0:towers.append(resident)
	if not check(towers.size()==2,"ordinary generation includes two persistent off-road lookout residents"):return false
	var navigation:Dictionary=game.generated_region.store.get_plan()
	var markers:Array=navigation.places.filter(func(place:Dictionary):return place.title=="Wilderness lookout")
	check(markers.size()==2,"both lookouts publish their actual entrance on the world map")
	var keys:Array=towers.map(func(resident:Dictionary):return resident.anchor)
	if restore:
		check(keys==expected.tower_keys,"fresh process restores stable lookout population identities")
		check(store.resident(expected.tower_killed).state==2,"cleared lookout resident stays dead after reload")
		return true
	expected.tower_keys=keys;expected.tower_killed=0
	var asset:Resource=preload("res://addons/exploration/watchtower_sites.gd").asset()
	for resident:Dictionary in towers:
		var key:int=resident.anchor
		var origin:=Vector3i((key&2047)-1,(key>>29)&1023,((key>>11)&2047)-1);var rotation:int=(key>>22)&3
		var entrance:=Vector3(origin)+Layouts.turn(asset.get_meta("site_entrance"),rotation)
		var matching:Array=markers.filter(func(marker:Dictionary):return marker.position.distance_to(entrance)<1.)
		if not check(matching.size()==1,"lookout marker is at its actual terrain-fitted entrance"):return false
		var paths:Array=navigation.roads.filter(func(path:Dictionary):return path.a.is_equal_approx(matching[0].position))
		if not check(paths.size()==1,"lookout has a connected approach from the regional road"):return false
		game.teleport(paths[0].b+Vector3.UP*.05)
		if not check(await wait_for(func():return not game.loading_active,90),"ordinary streaming admits the roadside lookout"):return false
		game.set_physics_process(false);game.zombies.update(0,game.player.global_position,false)
		game.camera.look_at(Vector3(origin)+Layouts.turn(Vector3(3.5,6.,4.5),rotation))
		await photograph("watchtower_"+str(resident.id)+"_road")
		if not check(await walk(paths[0].a),"real player walks from regional road to lookout entrance"):return false
		var route:PackedVector3Array=asset.get_meta("walk_route").duplicate();route.resize(route.size()-1)
		for point:Vector3 in route:
			if not check(await walk(Vector3(origin)+Layouts.turn(point,rotation)),"real player climbs lookout staircase and reaches supplies"):return false
		var crate:=Vector3(origin)+Layouts.turn(Vector3(1.8,7,6.3),rotation)
		game.camera.look_at(crate+Vector3.UP*.4)
		if not await open_supply():return false
		if game.storage.opened:
			check(game.storage.store.snapshot(game.storage.identity).slots[0].count>=3,"lookout chest contains generated supplies")
			game.storage.storage_list.select(0);game.storage.quantity.get_line_edit().text="1"
			check(game.storage.move_selected(false),"lookout supplies transfer through normal inventory UI")
			game.storage.close()
		game.camera.look_at(Vector3(origin)+Layouts.turn(Vector3(3.5,7.5,6.5),rotation))
		await photograph("watchtower_"+str(resident.id)+"_deck")
		var actors:Array=game.zombies.residents.filter(func(actor:Node):return actor.get_meta("world_zombie_id",0)==resident.id)
		check(actors.size()==1,"authored lookout resident is physically streamed on the upper deck")
		if actors.size()==1:
			var actor:CharacterBody3D=actors[0]
			game.zombies.update(0,game.player.global_position,true);game.zombies.hear_noise(actor.global_position,5.)
			var deadline:=Time.get_ticks_msec()+8000
			while actor.sleeper_active() and Time.get_ticks_msec()<deadline:
				await physics_frame;game.zombies.update(1./60.,game.player.global_position,true)
			check(not actor.sleeper_active() and absf(actor.global_position.y-(origin.y+7))<.4,"upper-deck resident completes waking without falling through the floor")
			if expected.tower_killed==0:
				expected.tower_killed=resident.id;actor.receive_hit("torso",1000.,actor.global_position+Vector3.UP,Vector3.ZERO)
				game.zombies.population.sync(actor)
		game.zombies.update(0,game.player.global_position,false)
		route.reverse()
		check(asset.get_meta("walk_route").size()==7 and asset.get_meta("walk_route")[0].is_equal_approx(Vector3(1.5,1.02,.5)),"walking test never mutates the shared authored route")
		for point:Vector3 in route:
			if not check(await walk(Vector3(origin)+Layouts.turn(point,rotation)),"real player descends lookout staircase"):return false
		if not check(await walk(paths[0].b),"real player returns from lookout to regional road"):return false
	return true

func finish()->void:
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED and preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"test never captures the desktop pointer")
	if game_ready():
		current_scene.shutdown_requested=true
		check(await current_scene.terrain.shutdown_after_edits(),"test world saves durably")
	if is_instance_valid(current_scene):current_scene.free()
	await process_frame;print("EXPLORATION_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)

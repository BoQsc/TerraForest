# SPDX-License-Identifier: 0BSD
extends SceneTree
const Options=preload("res://addons/world_runtime/session_options.gd")
const Layouts=preload("res://addons/exploration/cave_layouts.gd")
var game:Node
var folder:="res://reports/zombie_mine_pursuit"
var rows:Array=[]
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func until(predicate:Callable,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await process_frame
		if is_instance_valid(game):game.app_focused=true
	return predicate.call()
func run()->void:
	var slot:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mine-output="):folder=arg.trim_prefix("--mine-output=")
		if arg.begins_with("--mine-slot="):slot=arg.trim_prefix("--mine-slot=")
	if not slot.begins_with("CoalMine_") or not slot.is_valid_identifier() or not "--fresh-station" in OS.get_cmdline_user_args():
		push_error("Mine regression requires --fresh-station and an owned --mine-slot=CoalMine_...");quit(2);return
	DirAccess.make_dir_recursive_absolute(folder)
	var before:=FileAccess.get_sha256("user://worlds/"+slot+".trw")
	Options.set_arguments(PackedStringArray(["--snapshot-readonly","--temporary","--world-slot="+slot,"--zombies","--gameplay-construction"]),true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not await until(func():return not game.loading_active,120):print("MINE_LOAD_FAILED");game.free();quit(1);return
	game._clear_motion();game.needs_floor_spawn=false;game.fly=false;game.app_focused=true
	game.session_menu.set_open(false)
	var locations:Array=game.quests.store.get_locations().filter(func(row:Dictionary):return row.layout=="coal_mine")
	if locations.is_empty():game.free();quit(1);return
	var site:Dictionary=locations[0]
	var point:Vector3=Vector3(site.origin)+Layouts.turn(Vector3(.5,0,51),site.rotation)
	game.teleport(point,point.y+.08)
	if not await until(func():return not game.loading_active,100):print("MINE_TELEPORT_FAILED");game.free();quit(1);return
	await until(func():return not game.player_view.entry.active,40)
	var target=preload("res://addons/characters/runtime/zombie_target.gd").new();game.player.add_child(target);game.zombies.target=target
	if "--fresh-station" in OS.get_cmdline_user_args():
		game.set_physics_process(false);game.zombies.clear();game.zombies.population_enabled=false;game.zombies.residency_limit=16
		await physics_frame;await physics_frame
		var layout:Dictionary=Layouts.load_catalog().filter(func(row:Dictionary):return row.id=="coal_mine")[0]
		for anchor:Dictionary in Layouts.sleepers(layout,site.origin,site.rotation).slice(3):
			var zombie:CharacterBody3D=game.zombies.spawn_at(anchor.position,true,true)
			if zombie==null:print("MINE_FRESH_ADMISSION_FAILED ",anchor.position);continue
			zombie.rotation.y=anchor.yaw;game.zombies.configure_encounter(zombie,{"profile":"shambler","ambusher":true});game.zombies.put_to_sleep(zombie,anchor.pose)
		game.zombies.hear_noise(point,14.);game.set_physics_process(true)
	check(game.zombies.residents.size()==10,"actual mine fixture admits all ten authored station sleepers")
	var starts:Array[Vector3]=[]
	for actor:CharacterBody3D in game.zombies.residents:starts.append(actor.position)
	var player_travel:=0.;var previous_player:Vector3=game.player.position
	var moving_player:bool="--moving-player" in OS.get_cmdline_user_args()
	if moving_player:game.session_menu.developer_hud.mouse_access=true
	for frame in 60*12:
		if moving_player and frame>=180 and frame<540:
			var destination:Vector3=point+Layouts.turn(Vector3(0,0,3 if frame<360 else -3),site.rotation)
			var offset:Vector3=destination-game.player.position;offset.y=0
			game.yaw=atan2(-offset.x,-offset.z);game.player.rotation.y=game.yaw
			game.controls.set_key(KEY_W,offset.length()>.3,Time.get_ticks_usec())
		elif moving_player:game.controls.clear(Time.get_ticks_usec())
		await physics_frame;game.app_focused=true
		player_travel+=game.player.position.distance_to(previous_player);previous_player=game.player.position
		if frame%60==0:
			var actors:Array=[]
			for zombie:CharacterBody3D in game.zombies.residents:
				if not zombie.alive:continue
				actors.append({"id":zombie.get_meta("world_zombie_id",0),"position":zombie.position,"velocity":zombie.velocity,"state":zombie.state,"behavior":zombie.behavior_enabled,"mode":zombie.process_mode,"intent":game.zombies.awareness.status(zombie.get_instance_id()),"route":game.zombies.navigator.status(zombie.get_instance_id())})
			var row:Dictionary={"tick":frame,"fly":game.fly,"focused":game.app_focused,"loading":game.loading_active,"pending_edit":game.terrain.pending_edit,"ready":game.terrain.world_ready,"menu":game.session_menu.pauses_world(),"player":game.player.position,"damage":target.damage_received,"actors":actors}
			rows.append(row);print("MINE_PURSUIT ",JSON.stringify(row))
	var moved:=0;var attackers:=0
	for index in game.zombies.residents.size():
		var actor:CharacterBody3D=game.zombies.residents[index]
		if actor.position.distance_to(starts[index])>.5:moved+=1
		if actor.get_behavior_snapshot().contact_count>0:attackers+=1
	check(moved==10,"all ten awake station residents make actual pursuit progress")
	check(attackers>=3 and target.damage_received>0,"multiple mine residents land authored attacks on the solid player")
	game.controls.clear(Time.get_ticks_usec());game.session_menu.developer_hud.mouse_access=false
	if moving_player:check(player_travel>1,"mine acceptance uses actual on-foot player movement through the crowd")
	game.fly=true
	for frame in 3:await physics_frame;game.app_focused=true
	var flight_damage:float=target.damage_received
	for frame in 60:await physics_frame;game.app_focused=true
	check(game.zombies.residents.all(func(actor:CharacterBody3D):return actor.behavior_enabled) and target.damage_received>flight_damage,"Fly no longer globally switches off nearby zombie behavior")
	game.fly=false;var damage_before:float=target.damage_received
	for frame in 120:await physics_frame;game.app_focused=true
	check(target.damage_received>damage_before,"attacks continue after leaving Fly through the normal world update")
	var unchanged:=before==FileAccess.get_sha256("user://worlds/"+slot+".trw")
	check(unchanged,"prepared mine save remains unchanged during read-only diagnostics")
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"moved":moved,"attackers":attackers,"damage":target.damage_received,"player_travel":player_travel,"rows":rows,"source_unchanged":unchanged},"  "))
	game.shutdown_requested=true;game.free();await process_frame
	print("ZOMBIE_MINE_PURSUIT done checks=",checks," failures=",failures);quit(1 if failures else 0)

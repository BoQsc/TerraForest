# SPDX-License-Identifier: 0BSD
extends SceneTree
const Options=preload("res://addons/world_runtime/session_options.gd")
var game:Node
var rows:Array=[]
var invalidations:=0
var folder:="res://reports/zombie_saved_response"
var close_id:=0
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func until(predicate:Callable,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await process_frame
		if is_instance_valid(game):game.app_focused=true
	return predicate.call()
func sample(phase:String,frame:int)->void:
	var actors:Array=[]
	for zombie:CharacterBody3D in game.zombies.residents:
		var clearance:Array=[]
		for radius:float in [.24,.35]:
			var shape:=CapsuleShape3D.new();shape.radius=radius;shape.height=1.8
			var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=7;query.transform=Transform3D(Basis(),zombie.global_position+Vector3.UP*.93);query.exclude=[game.player.get_rid(),zombie.get_rid()]
			var hits:Array=[]
			for hit:Dictionary in game.get_world_3d().direct_space_state.intersect_shape(query,4):hits.append(str(hit.collider.get_path())+" shape="+str(hit.shape))
			clearance.append({"radius":radius,"hits":hits})
		actors.append({"id":zombie.get_meta("world_zombie_id",0),"position":zombie.global_position,"velocity":zombie.velocity,"state":zombie.state,"behavior":zombie.behavior_enabled,"process":zombie.process_mode,"sleep":zombie.sleeper.phase if zombie.sleeper_active() else "","hit":zombie._hit_timer,"clearance":clearance,"intent":game.zombies.awareness.status(zombie.get_instance_id()),"route":game.zombies.navigator.status(zombie.get_instance_id()),"steering":zombie.navigation_target})
	var row:Dictionary={"phase":phase,"frame":frame,"player":game.player.position,"fly":game.fly,"dead":game.player_life.dead,"menu":game.session_menu.pauses_world(),"entry":game.player_view.entry.active,"pending_edit":game.terrain.pending_edit,"world_ready":game.terrain.world_ready,"invalidations":invalidations,"damage":game.zombie_target.damage_received,"navigation":game.zombies.navigation_status,"actors":actors}
	rows.append(row);print("SAVED_RESPONSE ",JSON.stringify(row))
func run()->void:
	var slot:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--replay-slot="):slot=arg.trim_prefix("--replay-slot=")
		if arg.begins_with("--response-output="):folder=arg.trim_prefix("--response-output=")
		if arg.begins_with("--close-resident="):close_id=int(arg.trim_prefix("--close-resident="))
	if not slot.is_valid_identifier() or not FileAccess.file_exists("user://worlds/"+slot+".trw"):
		push_error("Saved response requires an existing --replay-slot");quit(2);return
	DirAccess.make_dir_recursive_absolute(folder)
	Options.set_arguments(PackedStringArray(["--snapshot-readonly","--temporary","--world-slot="+slot,"--zombies","--gameplay-construction"]),true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not await until(func():return not game.loading_active,120):game.free();quit(1);return
	game.zombie_target.attacked.disconnect(game.player_life.damage)
	game._clear_motion();game.needs_floor_spawn=false;game.app_focused=true;game.session_menu.set_open(false)
	await until(func():return not game.player_view.entry.active,40)
	game.terrain.region_changed.connect(func(_bounds:AABB,_revision:int):invalidations+=1)
	game.structures.changed.connect(func():invalidations+=1)
	if close_id!=0:
		var selected:CharacterBody3D
		for actor:CharacterBody3D in game.zombies.residents:
			if int(actor.get_meta("world_zombie_id",0))==close_id:selected=actor
		if selected==null:game.free();quit(3);return
		var point:=Vector3.INF
		for index in 32:
			var angle:=TAU*index/16.;var radius:=2. if index<16 else 3.5
			var candidate:Vector3=game.zombies.supported_roam_point(selected.position+Vector3(cos(angle)*radius,0,sin(angle)*radius))
			if not candidate.is_finite() or absf(candidate.y-selected.position.y)>.3:continue
			var ray:=PhysicsRayQueryParameters3D.create(selected.position+Vector3.UP*1.35,candidate+Vector3.UP*1.1,7,[game.player.get_rid()])
			if game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():point=candidate;break
		if not point.is_finite():print("NO_CLOSE_CANDIDATE");sample("no_candidate",0);game.free();quit(4);return
		game.teleport(point,point.y+.04)
		await until(func():return not game.loading_active and not game.player_view.entry.active,100)
		game.fly=false
	for phase:String in ["saved","provoked"]:
		if phase=="provoked":
			for actor:CharacterBody3D in game.zombies.residents:
				if actor.alive:actor.receive_hit("torso",1.,actor.global_position+Vector3.UP)
		for frame in 60*10:
			await physics_frame;game.app_focused=true
			if frame%60==0:sample(phase,frame)
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":slot,"rows":rows},"  "))
	game.shutdown_requested=true;game.free();await process_frame
	print("ZOMBIE_SAVED_RESPONSE done");quit()

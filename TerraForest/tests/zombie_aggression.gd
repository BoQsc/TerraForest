# SPDX-License-Identifier: 0BSD
extends SceneTree
## Original Codex-authored regression for close threats and guarded sleeper ambushes.
var checks:=0
var failures:=0
var stage:Node3D
var host:Node3D
var player:CharacterBody3D
var target:Node3D
var camera:Camera3D
var driving:=false
var available:=true
var ready:=true
var folder:="res://reports/zombie_aggression"
var traces:Array=[]

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--aggression-output="):folder=arg.trim_prefix("--aggression-output=")
	run.call_deferred()

func box(at:Vector3,size:Vector3)->StaticBody3D:
	var body:=StaticBody3D.new();body.position=at
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape;body.add_child(collision)
	var view:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;view.mesh=mesh;body.add_child(view)
	stage.add_child(body);return body

func tick()->void:
	if driving:host.update(1./60.,player.global_position,available)

func ticks(count:int)->void:
	for frame in count:await physics_frame

func reset()->void:
	driving=false;host.clear();await ticks(3)
	player.position=Vector3(60,0,0);available=true;ready=true

func spawn(ambusher:bool=false)->CharacterBody3D:
	var zombie:CharacterBody3D=host.spawn_at(Vector3.ZERO)
	check(zombie!=null,"supported aggression fixture admits")
	if zombie!=null:check(host.configure_encounter(zombie,{"profile":"shambler","ambusher":ambusher}),"shipped quiet profile configures")
	return zombie

func sample(zombie:CharacterBody3D,label:String)->void:
	traces.append({"label":label,"body":zombie.get_behavior_snapshot(),"intent":host.awareness.status(zombie.get_instance_id()),"posture":zombie.sleeper.snapshot() if zombie.sleeper_active() else {}})
	if DisplayServer.get_name()=="headless":return
	camera.position=zombie.position+Vector3(3,2,-3);camera.look_at(zombie.position+Vector3.UP*.7)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))

func native_contract()->void:
	var brain=ClassDB.instantiate("NativeZombieAwareness");brain.configure(1,1703);brain.add_agent(1,Vector3.ZERO)
	brain.set_profile(1,host.encounter_profiles.shambler)
	brain.observe(1,Vector3(0,0,-1.5),true,1.5)
	for frame in 16:brain.advance(1,Vector3.ZERO,1./60.,true,"following")
	check(brain.status(1).combat,"close confirmed sight shortens quiet zombie recognition to 0.2 seconds")
	for frame in 60*25:
		brain.observe(1,Vector3(0,0,-1.5),true,1.5);brain.advance(1,Vector3.ZERO,1./60.,true,"following")
	check(brain.status(1).combat and brain.status(1).interest_seconds>20,"obvious close threat cannot exhaust interest while still seen")
	brain.observe(1,Vector3(0,0,-1.5),false,1.5)
	for frame in 60*21:brain.advance(1,Vector3.ZERO,1./60.,true,"following")
	check(brain.status(1).state in ["idle","wander"],"close engagement remains escapable after sight is broken")
	brain.provoke(1,Vector3(0,0,-8))
	check(brain.wants_sight(1,Vector3.ZERO,Vector3.BACK,Vector3(0,0,-8)),"retaliation checks behind the zombie without waiting for a blind turn")
	brain.observe(1,Vector3(0,0,-8),true,8)
	check(brain.status(1).combat and brain.status(1).chase_speed_multiplier>=1.8,"confirmed attacker gets immediate committed retaliation")
	for frame in 60*7:
		brain.observe(1,Vector3(0,0,-8),true,8);brain.advance(1,Vector3.ZERO,1./60.,true,"blocked")
	check(brain.status(1).urgent and brain.status(1).ignore_seconds==0,"physical blockage cannot erase retaliation while the player remains visible")
	check(brain.wants_sight(1,Vector3.ZERO,Vector3.BACK,Vector3(0,0,1)),"close threat is eligible to break blocked pursuit cooldown")
	var retained_goal:Vector3=brain.status(1).goal
	brain.observe(1,Vector3(0,0,1),false,1)
	check(not brain.status(1).visible and brain.status(1).goal==retained_goal,"occluded proximity cannot reveal a hidden player's new position")
	brain.observe(1,Vector3(0,0,1),true,1)
	for frame in 16:brain.advance(1,Vector3.ZERO,1./60.,true,"following")
	check(brain.status(1).combat and brain.status(1).ignore_seconds==0,"actually visible close threat restores engagement")
	brain.remove_agent(1);brain.add_agent(1,Vector3.ZERO);brain.set_profile(1,host.encounter_profiles.shambler);brain.set_sleeping(1,1)
	brain.observe(1,Vector3(0,0,2),true,2)
	for frame in 12:brain.advance(1,Vector3.ZERO,1./60.,true,"none")
	brain.observe(1,Vector3(0,0,2),false,2)
	for frame in 60:brain.advance(1,Vector3.ZERO,1./60.,true,"none")
	check(brain.status(1).state=="sleeping" and brain.status(1).notice_seconds==0,"brief interrupted sleeper glimpse clears caution instead of accumulating a radial alarm")
	brain.hear(1,Vector3.ZERO,Vector3(0,0,3),7)
	for frame in 70:brain.advance(1,Vector3.ZERO,1./60.,true,"none")
	brain.observe(1,Vector3(0,0,4),true,4)
	check(brain.finish_waking(1) and brain.status(1).combat and brain.status(1).goal==Vector3(0,0,4),"wake handshake directly targets a currently seen player")
	brain.observe(1,Vector3(8,0,8),false,11)
	for frame in 60*13:brain.advance(1,Vector3.ZERO,1./60.,true,"following")
	if brain.status(1).state=="reposition":brain.advance(1,brain.status(1).goal,1./60.,true,"arrived")
	check(brain.status(1).urgent and brain.status(1).goal==Vector3(0,0,4),"completed recovery returns to the last sighting without tracking hidden coordinates")
	for frame in 60*16:brain.advance(1,Vector3.ZERO,1./60.,true,"following")
	check(brain.status(1).state in ["idle","wander"],"sleeper memory still expires within a bounded chase")

func run()->void:
	DirAccess.make_dir_recursive_absolute(folder)
	stage=Node3D.new();root.add_child(stage);box(Vector3(0,-.5,0),Vector3(160,1,160))
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);stage.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.7;stage.add_child(environment)
	player=CharacterBody3D.new();player.collision_layer=2;stage.add_child(player);player.position=Vector3(60,0,0)
	var collision:=CollisionShape3D.new();var shape:=CapsuleShape3D.new();shape.radius=.34;shape.height=1.8;collision.shape=shape;collision.position.y=.9;player.add_child(collision)
	target=preload("res://addons/characters/runtime/zombie_target.gd").new();player.add_child(target)
	host=preload("res://addons/characters/runtime/zombie_world.gd").new();host.target=target;host.enabled=true;host.population_enabled=false
	host.readiness=func(_bounds:AABB):return ready
	stage.add_child(host)
	camera=Camera3D.new();stage.add_child(camera);camera.current=true
	physics_frame.connect(tick);await ticks(3)
	native_contract()
	for pose in [1,2]:
		await reset();var zombie:CharacterBody3D=spawn()
		if zombie==null:quit(1);return
		check(host.put_to_sleep(zombie,pose),"physical sleeper pose admits: "+str(pose));driving=true
		await ticks(60)
		check(zombie.awareness_state=="sleeping","quiet distant player leaves sleeper asleep")
		player.position=Vector3(0,0,2.2)
		var wall:=box(Vector3(0,1.5,1.1),Vector3(8,3,.25));await ticks(70)
		check(zombie.awareness_state=="sleeping","stationary close player behind solid wall cannot wake sleeper")
		wall.queue_free();await ticks(3)
		ready=false;await ticks(35)
		check(zombie.awareness_state=="sleeping","unready close sight cannot wake sleeper")
		ready=true;await ticks(12)
		check(zombie.awareness_state=="sleeping","close stationary player gets a brief cautious interval")
		var elapsed:=12
		while zombie.sleeper_active() and elapsed<220:
			await ticks(1);elapsed+=1
		check(not zombie.sleeper_active() and elapsed<=200,"pose %d safely finishes its accelerated rise within 3.34 seconds (%0.3f)"%[pose,elapsed/60.])
		check(zombie.target==target and zombie.awareness_state=="chase" and zombie.chase_speed_multiplier>=2.2,"awake sleeper immediately acquires the visible player at ambush pace")
		await sample(zombie,"awake_pose_"+str(pose))
		var damage_before:float=target.damage_received
		await ticks(60*7)
		check(target.damage_received>damage_before,"awakened sleeper physically closes and lands an authored attack")
		await sample(zombie,"attacking_pose_"+str(pose))
	await reset();var roamer:CharacterBody3D=spawn();driving=true
	player.position=Vector3(0,0,-8)
	check(host.apply_hit({"zombie":roamer,"part":"torso","position":roamer.position+Vector3.UP},4.,Vector3.BACK),"normal hit adapter accepts an attack from behind")
	await ticks(25)
	check(roamer.target==target and roamer.awareness_state=="chase" and roamer.chase_speed_multiplier>=1.8,"ordinary damaged zombie locates its visible attacker behind it")
	var before:float=roamer.position.distance_to(player.position);await ticks(60*3)
	check(roamer.position.distance_to(player.position)<before-1.,"provoked ordinary zombie makes physical pursuit progress")
	await sample(roamer,"retaliation")
	await reset();roamer=spawn(true);driving=true;player.position=Vector3(0,0,7);await ticks(90)
	check(host.awareness.status(roamer.get_instance_id()).ambusher and roamer.chase_speed_multiplier>=2.2,"restored authored sleeper identity keeps ambush temperament after waking bytes are gone")
	check(host.navigation_status.perception_probes<=2,"perception retains the existing two-probe frame budget")
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED,"aggression regression leaves pointer uncaptured")
	driving=false;host.clear();await ticks(3);stage.free();await process_frame
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"traces":traces},"  "))
	print("ZOMBIE_AGGRESSION checks=",checks," failures=",failures);quit(1 if failures else 0)

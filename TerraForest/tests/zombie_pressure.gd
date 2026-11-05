# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var stage:Node3D
var host:Node3D
var player:CharacterBody3D
var target:Node3D
var active:=false
var clock:=0.
var moving:=false
var trace:Array=[]
var folder:="res://reports/zombie_pressure"
var budget_ok:=true
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pressure-output="):folder=arg.trim_prefix("--pressure-output=")
	run.call_deferred()
func tick()->void:
	if not active:return
	var delta:=1./Engine.physics_ticks_per_second;clock+=delta
	if moving:player.position=Vector3(sin(clock*.8)*1.5,0,5+cos(clock*.8)*.75)
	host.update(delta,player.position,true)
	budget_ok=budget_ok and host.navigation_status.perception_probes<=2 and host.navigation_status.route_work<=host.navigation_status.route_work_limit and host.navigation_status.route_work_limit<=48
func frames(count:int)->void:
	for frame in count:await physics_frame
func box(point:Vector3,size:Vector3)->void:
	var body:=StaticBody3D.new();stage.add_child(body);body.position=point
	var shape:=BoxShape3D.new();shape.size=size;var collision:=CollisionShape3D.new();collision.shape=shape;body.add_child(collision)
	var view:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;view.mesh=mesh
	var material:=StandardMaterial3D.new();material.albedo_color=Color("4d6151") if size.y<2 else Color("8c7160");view.material_override=material;body.add_child(view)
func run()->void:
	stage=Node3D.new();root.add_child(stage);box(Vector3(0,-.5,0),Vector3(50,1,50))
	DirAccess.make_dir_recursive_absolute(folder)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);stage.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65;stage.add_child(environment)
	var camera:=Camera3D.new();stage.add_child(camera);camera.position=Vector3(10,9,-11);camera.look_at(Vector3(0,.5,0));camera.current=true
	player=CharacterBody3D.new();player.collision_layer=2;stage.add_child(player);player.position=Vector3(0,0,5)
	var capsule:=CapsuleShape3D.new();capsule.radius=.34;capsule.height=1.8;var collision:=CollisionShape3D.new();collision.shape=capsule;collision.position.y=.9;player.add_child(collision)
	var player_view:=MeshInstance3D.new();var mesh:=CapsuleMesh.new();mesh.radius=.34;mesh.height=1.8;player_view.mesh=mesh;player_view.position.y=.9;player.add_child(player_view)
	target=preload("res://addons/characters/runtime/zombie_target.gd").new();player.add_child(target)
	host=preload("res://addons/characters/runtime/zombie_world.gd").new();stage.add_child(host);host.enabled=true;host.population_enabled=false;host.target=target;host.residency_limit=16
	host.readiness=func(_bounds:AABB):return true
	physics_frame.connect(tick);await frames(3)
	var brain=ClassDB.instantiate("NativeZombieAwareness");brain.configure(1,5);brain.add_agent(1,Vector3.ZERO);brain.set_profile(1,host.encounter_profiles.shambler)
	brain.observe(1,Vector3(0,0,10),true,10)
	for frame in 30:brain.advance(1,Vector3.ZERO,1./60.,true,"following")
	check(brain.status(1).combat,"ordinary sustained sight commits within half a second")
	for frame in 60*45:brain.observe(1,Vector3(0,0,10),true,10);brain.advance(1,Vector3.ZERO,1./60.,true,"following")
	check(brain.status(1).urgent and brain.status(1).interest_seconds>30,"visible player cannot exhaust engagement during recovery or pursuit")
	brain.remove_agent(1);brain.add_agent(1,Vector3.ZERO);brain.set_profile(1,host.encounter_profiles.shambler)
	brain.observe(1,Vector3(0,0,10),true,10)
	for frame in 30:brain.advance(1,Vector3.ZERO,1./60.,true,"following")
	brain.observe(1,Vector3(9,0,9),false,12)
	for frame in 12:brain.advance(1,Vector3.ZERO,1./60.,true,"following")
	check(brain.status(1).state=="chase" and not brain.status(1).visible and brain.status(1).goal==Vector3(0,0,10),"brief lost sight keeps pressure on last seen point without hidden homing")
	for frame in 48:brain.advance(1,Vector3.ZERO,1./60.,true,"following")
	check(brain.status(1).state=="investigate" and brain.status(1).urgent,"longer lost sight becomes urgent clue pursuit")
	check(brain.hear(1,Vector3.ZERO,Vector3(0,0,7),8) and brain.status(1).goal==Vector3(0,0,7),"fresh audible footsteps update an active investigation")
	check(not brain.hear(1,Vector3.ZERO,Vector3(1,0,7),8),"sound clue updates retain a bounded cooldown")
	brain.remove_agent(1);brain.add_agent(1,Vector3.ZERO);brain.set_profile(1,host.encounter_profiles.shambler);brain.set_sleeping(1,1)
	check(brain.wants_sight(1,Vector3.ZERO,Vector3.BACK,Vector3(0,0,4)) and not brain.wants_sight(1,Vector3.ZERO,Vector3.BACK,Vector3(0,0,-4)),"sleeper caution reaches forward but is not a spherical four-metre alarm")
	check(brain.wants_sight(1,Vector3.ZERO,Vector3.BACK,Vector3(0,0,-1)),"intimate behind approach is still eligible for an occlusion check")
	# Explicit already-acquired target isolates moving-goal route progress. Normal
	# perception/memory are tested above and in actual furnished/mine journeys.
	host.force_pursuit=true;box(Vector3(0,1.5,0),Vector3(6,3,.4))
	var starts:Array[Vector3]=[]
	for index in 10:
		var point:=Vector3((index%5-2)*.9,0,-4.5-float(index/5)*1.2)
		var zombie:CharacterBody3D=host.spawn_at(point)
		check(zombie!=null,"moving-goal crowd fixture admits "+str(index))
		if zombie!=null:host.configure_encounter(zombie,{"profile":"roamer","ambusher":true});starts.append(zombie.position)
	active=true;moving=true
	var moved:=0
	for frame in 60*12:
		await frames(1)
		if frame%60==0:
			var actors:Array=[]
			for zombie:CharacterBody3D in host.residents:actors.append({"position":zombie.position,"route":host.navigator.status(zombie.get_instance_id())})
			trace.append({"frame":frame,"player":player.position,"actors":actors})
		if DisplayServer.get_name()!="headless" and frame in [180,600]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join("moving_pursuit_%d.png"%frame))
	for index in host.residents.size():
		if host.residents[index].position.distance_to(starts[index])>1:moved+=1
	print("MOVING_TARGET_PROGRESS ",moved,"/",host.residents.size()," damage=",target.damage_received)
	check(moved>=8,"moving player does not repeatedly erase crowd route progress")
	active=false;moving=false;host.clear();await frames(3)
	player.position=Vector3(0,0,8);host.force_pursuit=false
	for index in 16:
		var angle:=TAU*index/16.;var zombie:CharacterBody3D=host.spawn_at(player.position+Vector3(cos(angle)*3,0,sin(angle)*3))
		if zombie!=null:host.configure_encounter(zombie,{"profile":"shambler"})
	check(host.residents.size()==16,"fairness fixture fills bounded station capacity")
	Engine.physics_ticks_per_second=20;active=true;await frames(40)
	var engaged:int=host.residents.filter(func(zombie:CharacterBody3D):return zombie.awareness_state=="chase").size()
	check(engaged==16,"all sixteen residents receive perception service at a low update rate")
	check(budget_ok,"pressure, crowd and perception retain their existing frame work limits")
	Engine.physics_ticks_per_second=60
	active=false;host.clear();await frames(3);stage.free();await process_frame
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"moved":moved,"engaged_at_20hz":engaged,"trace":trace},"  "))
	print("ZOMBIE_PRESSURE checks=",checks," failures=",failures);quit(1 if failures else 0)

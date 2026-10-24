# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
var stage:Node3D
var encounters:Node3D
var target:Node3D
var player:CharacterBody3D
var active:=false
var missing_route:=false
var wet_band:=false
var peak_work:=0
var trace:Array=[]
var camera:Camera3D
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func box(at:Vector3,size:Vector3,color:Color,layer:int=1)->StaticBody3D:
	var body:=StaticBody3D.new();body.position=at;body.collision_layer=layer
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collider.shape=shape;body.add_child(collider)
	var view:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;var material:=StandardMaterial3D.new();material.albedo_color=color;mesh.material=material;view.mesh=mesh;body.add_child(view);stage.add_child(body);return body
func _initialize()->void:run.call_deferred()
func tick_manager()->void:
	if not active:return
	encounters.update(1.0/Engine.physics_ticks_per_second,player.global_position,true)
	peak_work=maxi(peak_work,int(encounters.navigation_status.get("route_work",0)))
func ticks(count:int)->void:
	for tick in count:await physics_frame
func run()->void:
	stage=Node3D.new();root.add_child(stage)
	box(Vector3(0,-0.5,4),Vector3(36,1,30),Color("53614d"))
	var wall:=box(Vector3(0,1.5,0),Vector3(0.4,3,3),Color("927953"),2)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);light.light_energy=1.8;light.shadow_enabled=true;stage.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("354453");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.5;stage.add_child(environment)
	camera=Camera3D.new();stage.add_child(camera);camera.position=Vector3(8,8,10);camera.look_at(Vector3(0,0.7,0));camera.current=true
	player=CharacterBody3D.new();player.collision_layer=2;stage.add_child(player);player.position=Vector3(2.5,0,0)
	var collision:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=0.34;capsule.height=1.8;collision.shape=capsule;collision.position.y=0.9;player.add_child(collision)
	target=preload("res://addons/characters/runtime/zombie_target.gd").new();player.add_child(target)
	encounters=preload("res://addons/characters/runtime/zombie_world.gd").new();stage.add_child(encounters);encounters.enabled=true;encounters.target=target
	encounters.force_pursuit=true # Isolate route/motor acceptance from sight and memory.
	# A small resident island contains the real body, while every exit corridor
	# is unknown. Readiness must describe the entire box, including larger probes.
	encounters.readiness=func(bounds:AABB):return not missing_route or bounds.position.x>=-4.2 and bounds.end.x<=-.8 and bounds.position.z>=-1.7 and bounds.end.z<=1.7
	encounters.water_depth=func(point:Vector3):return 1.0 if wet_band and absf(point.x)<0.7 and absf(point.z)<1.3 else 0.0
	encounters._spawn_clock=100000.0
	physics_frame.connect(tick_manager)
	await ticks(3)
	var zombie=encounters.spawn_at(Vector3(-2.5,0,0));check(zombie!=null,"routed zombie admits")
	active=true
	var clipped:=false
	for tick in Engine.physics_ticks_per_second*23:
		await physics_frame
		if tick%6==0:
			var p:Vector3=zombie.position;trace.append([p.x,p.y,p.z])
			clipped=clipped or (absf(p.x)<0.4 and absf(p.z)<1.65)
		if target.damage_received>0:break
	check(target.damage_received>0,"zombie routes around a wall and reaches actual attack contact")
	check(not clipped,"route and body never cross the solid wall")
	check(peak_work<=12,"zombie pool shares twelve native route work units")
	check(encounters.navigator.status(zombie.get_instance_id()).node_limit==2048,"same bounded ActorRoute core supplies node limit")
	var before:float=target.damage_received
	player.position=Vector3(2.5,0,3)
	for tick in Engine.physics_ticks_per_second*9:
		await physics_frame
		if target.damage_received>before:break
	check(target.damage_received>before,"changed pursuit goal replans and reaches the moved player")
	DirAccess.make_dir_recursive_absolute("res://reports/zombie_navigation")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/zombie_navigation/wall.png")
	active=false;encounters.clear();await ticks(2);wall.free();await ticks(2)
	player.position=Vector3(2.5,0,0);target.damage_received=0;wet_band=true;encounters._spawn_clock=100000.0
	zombie=encounters.spawn_at(Vector3(-2.5,0,0));active=true
	var crossed_water:=false
	var water_trace:Array=[]
	for tick in Engine.physics_ticks_per_second*23:
		await physics_frame
		var p:Vector3=zombie.global_position
		if tick%15==0:water_trace.append({"position":p,"route":encounters.navigator.status(zombie.get_instance_id()),"state":zombie.state})
		crossed_water=crossed_water or (absf(p.x)<0.7 and absf(p.z)<1.3)
		if target.damage_received>0:break
	check(target.damage_received>0 and not crossed_water,"route admission goes around deep water instead of walking across it")
	print("WATER_RESULT ",JSON.stringify({"damage":target.damage_received,"crossed":crossed_water,"body":zombie.get_behavior_snapshot(),"route":encounters.navigator.status(zombie.get_instance_id())}))
	active=false;encounters.clear();wet_band=false;await ticks(2)
	player.position=Vector3(3,0,0);target.damage_received=0
	var gates:Array=[]
	gates.append(box(Vector3(-1.8,1.5,0),Vector3(.2,3,2.6),Color("927953")))
	gates.append(box(Vector3(-4.2,1.5,0),Vector3(.2,3,2.6),Color("927953")))
	gates.append(box(Vector3(-3,1.5,-1.2),Vector3(2.6,3,.2),Color("927953")))
	gates.append(box(Vector3(-3,1.5,1.2),Vector3(2.6,3,.2),Color("927953")))
	await ticks(2);encounters._spawn_clock=100000.0;zombie=encounters.spawn_at(Vector3(-3,0,0));active=true
	await ticks(Engine.physics_ticks_per_second*5)
	var state:Dictionary=encounters.navigator.status(zombie.get_instance_id())
	check(state.state in ["blocked","search_limit"],"sealed room reports blocked/search limit instead of direct pursuit")
	check(zombie.position.distance_to(Vector3(-3,0,0))<0.15,"failed route holds the real body")
	gates[0].free();encounters.invalidate_navigation()
	for tick in Engine.physics_ticks_per_second*15:
		await physics_frame
		if target.damage_received>0:break
	check(target.damage_received>0,"removing a blocking wall invalidates and restores traversal")
	active=false;encounters.clear();await ticks(2)
	for index in range(1,4):gates[index].free()
	await ticks(2);encounters._spawn_clock=100000.0
	zombie=encounters.spawn_at(Vector3(-2.5,0,0));missing_route=true;active=true
	var unavailable_seen:=false
	for tick in Engine.physics_ticks_per_second*2:
		await physics_frame
		if encounters.navigator.status(zombie.get_instance_id()).state=="unavailable":unavailable_seen=true;break
	check(unavailable_seen,"unknown route coverage differs from blocked geometry")
	check(zombie.position.distance_to(Vector3(-2.5,0,0))<0.15,"unknown route never falls back to direct chasing")
	missing_route=false;encounters.invalidate_navigation();await ticks(Engine.physics_ticks_per_second)
	check(encounters.navigator.status(zombie.get_instance_id()).state in ["following","planning"],"ready coverage resumes bounded planning")
	active=false;encounters.clear();await ticks(2)
	for index in 4:box(Vector3(-1.75+index*.5,(index+1)*.125,8),Vector3(.5,(index+1)*.25,3),Color("8e7e62"))
	box(Vector3(1.5,.5,8),Vector3(3.5,1,3),Color("8e7e62"))
	player.position=Vector3(2.5,1.04,8);target.damage_received=0
	await ticks(2);encounters._spawn_clock=100000.0;zombie=encounters.spawn_at(Vector3(-3,0,8));active=true
	for tick in Engine.physics_ticks_per_second*20:
		await physics_frame
		if target.damage_received>0:break
	check(zombie.position.y>.9 and target.damage_received>0,"shared walking route and native motor climb four stairs to attack")
	if DisplayServer.get_name()!="headless":
		camera.position=Vector3(7,5,13);camera.look_at(Vector3(0,0.8,8));await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/zombie_navigation/stairs.png")
	var report:=FileAccess.open("res://reports/zombie_navigation/result.json",FileAccess.WRITE);report.store_string(JSON.stringify({"checks":checks,"failures":failures,"peak_route_work":peak_work,"wall_trace":trace,"water_trace":water_trace,"water_crossed":crossed_water,"final":zombie.get_behavior_snapshot(),"route":encounters.navigator.status(zombie.get_instance_id())},"  "));report.close()
	active=false;encounters.clear();await process_frame;stage.free();await process_frame
	print("ZOMBIE_NAVIGATION checks=",checks," failures=",failures);quit(0 if failures==0 else 1)

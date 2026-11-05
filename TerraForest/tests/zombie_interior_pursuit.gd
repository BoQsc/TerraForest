# SPDX-License-Identifier: 0BSD
extends SceneTree
const Homes=preload("res://addons/characters/runtime/house_sleepers.gd")
var stage:Node3D
var host:Node3D
var driving:=false
var cases:Array=[]
var checks:=0
var failures:=0
var folder:="res://reports/zombie_interior_pursuit"
var moving_body:CharacterBody3D
var endpoint_a:Vector3
var endpoint_b:Vector3
var motion_clock:=0.
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:run.call_deferred()
func tick()->void:
	if driving:
		if is_instance_valid(moving_body):
			motion_clock+=1./60.
			var goal:=endpoint_a.lerp(endpoint_b,(sin(motion_clock*.9)+1.)*.5)
			var offset:=goal-moving_body.position;offset.y=0
			moving_body.velocity=offset.normalized()*minf(1.2,offset.length()*60.)+Vector3.DOWN*.1
			moving_body.move_and_slide()
		host.update(1./60.,host.target.global_position,true)
func frames(count:int)->void:
	for frame in count:await physics_frame
func run()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--interior-output="):folder=arg.trim_prefix("--interior-output=")
	DirAccess.make_dir_recursive_absolute(folder)
	physics_frame.connect(tick)
	for house:String in Homes.HOMES:
		stage=Node3D.new();root.add_child(stage)
		var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);stage.add_child(light)
		var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.7;stage.add_child(environment)
		var structures=preload("res://addons/structures/structures_world.gd").new();stage.add_child(structures);structures.prepare()
		for catalog:String in ["furniture","ladder","storage","window","door","guardrail","fence"]:load("res://addons/structures/"+catalog+"_catalog.gd").register(structures)
		var origin:=Vector3i(100,20,100);var asset:Resource=Homes.Catalog.asset(house)
		var anchor:Dictionary=Homes.plan([{"asset":asset,"origin":origin,"rotation":0}],1703).anchors[0]
		var placement=ClassDB.instantiate("NativePrefabPlacement")
		print("INTERIOR_PLACE ",house," ",placement.place(structures.blocks,asset,origin,0,structures.model_collections(),[]))
		structures.blocks.set_focus(anchor.position);structures.blocks.set_collision_radius(48);structures.blocks.flush_bakes();structures.set_model_focus(anchor.position)
		var bounds:=AABB(anchor.position-Vector3(2.5,.5,2.5),Vector3(5,5,5));var deadline:=Time.get_ticks_msec()+10000
		while not structures.is_collision_region_ready(bounds) and Time.get_ticks_msec()<deadline:await process_frame
		host=preload("res://addons/characters/runtime/zombie_world.gd").new();host.population_enabled=false;host.enabled=true
		host.target=preload("res://addons/characters/runtime/zombie_target.gd").new();stage.add_child(host.target)
		host.target.position=anchor.position+Vector3(0,0,30);host.readiness=structures.is_collision_region_ready;stage.add_child(host)
		await frames(3)
		var zombie:CharacterBody3D=host.spawn_at(anchor.position,true,true)
		if zombie==null:check(false,"furnished house admits resident: "+house);stage.free();await frames(3);continue
		host.configure_encounter(zombie,{"profile":"shambler","ambusher":true});host.put_to_sleep(zombie,1);zombie.rotation.y=anchor.yaw
		var candidates:Array=[]
		for radius:float in [2.0,1.5,3.0,4.0]:
			for offset:Vector3 in [Vector3(0,0,1),Vector3(1,0,0),Vector3(0,0,-1),Vector3(-1,0,0)]:
				var point:Vector3=host.supported_resident_point(anchor.position+offset*radius,true)
				if not point.is_finite():continue
				var ray:=PhysicsRayQueryParameters3D.create(anchor.position+Vector3.UP*1.35,point+Vector3.UP*1.1,7)
				if stage.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():candidates.append(point)
		print("INTERIOR_CANDIDATES ",house," ",candidates)
		var accepted:=0
		for candidate:Vector3 in candidates:
			var space:=stage.get_world_3d().direct_space_state
			var high:=space.intersect_ray(PhysicsRayQueryParameters3D.create(candidate+Vector3.UP*4,candidate-Vector3.UP*4,1))
			var low:=space.intersect_ray(PhysicsRayQueryParameters3D.create(candidate+Vector3.UP*.3,candidate-Vector3.UP*4,1))
			var projected:Vector3=host.supported_roam_point(candidate)
			if projected.is_finite():
				accepted+=1
				check(absf(projected.y-candidate.y)<.1,house+": roam projection retains the occupied storey")
			print("INTERIOR_ROAM_PROJECTION ",house," ",JSON.stringify({"requested":candidate,"projected":projected,"legacy_projection":host.supported_point(candidate),"ready":host.readiness.call(AABB(candidate-Vector3(.6,4,.6),Vector3(1.2,9,1.2))),"high_hit":high.get("position"),"high_normal":high.get("normal"),"low_hit":low.get("position"),"low_normal":low.get("normal")}))
		check(accepted>=2,house+": shared room-floor selector accepts multiple valid room destinations")
		if "--projection-only" in OS.get_cmdline_user_args():
			host.clear();stage.free();await frames(3);continue
		if candidates.is_empty():host.clear();stage.free();await frames(3);continue
		host.target.position=candidates[0]
		var player_travel:=0.;var previous_player:Vector3=host.target.global_position
		if "--moving-target" in OS.get_cmdline_user_args():
			endpoint_a=candidates[0];endpoint_b=endpoint_a
			var direction:Vector3=endpoint_a-anchor.position;direction=direction.normalized()
			for candidate:Vector3 in candidates:
				var offset:Vector3=candidate-anchor.position
				if offset.normalized().dot(direction)>.999 and candidate.distance_to(endpoint_a)>endpoint_b.distance_to(endpoint_a):endpoint_b=candidate
			moving_body=CharacterBody3D.new();moving_body.collision_layer=2;moving_body.collision_mask=7|(1<<16);stage.add_child(moving_body);moving_body.position=endpoint_a
			var collider:=CollisionShape3D.new();var shape:=CapsuleShape3D.new();shape.radius=.34;shape.height=1.8;collider.shape=shape;collider.position.y=.9;moving_body.add_child(collider)
			host.target.reparent(moving_body);host.target.position=Vector3.ZERO;motion_clock=0
		host.hear_noise(host.target.global_position,7.);driving=true
		var rows:Array=[];var start:Vector3=zombie.position
		for frame in 60*20:
			await frames(1)
			player_travel+=host.target.global_position.distance_to(previous_player);previous_player=host.target.global_position
			if frame%30==0:
				var row:Dictionary={"tick":frame,"position":zombie.position,"velocity":zombie.velocity,"state":zombie.state,"intent":host.awareness.status(zombie.get_instance_id()),"route":host.navigator.status(zombie.get_instance_id()),"target":host.target.global_position,"behavior":zombie.behavior_enabled,"process_mode":zombie.process_mode}
				rows.append(row)
				if frame%120==0:print("INTERIOR_TRACE ",house," ",JSON.stringify(row))
		var summary:Dictionary={"house":house,"start":start,"target":host.target.global_position,"player_travel":player_travel,"displacement":zombie.position.distance_to(start),"damage":host.target.damage_received,"rows":rows}
		cases.append(summary);print("INTERIOR_SUMMARY ",house," displacement=",summary.displacement," damage=",summary.damage)
		check(summary.displacement>.4 and summary.damage>0,house+": normal awakened resident pursues and attacks through furnished collision")
		if "--moving-target" in OS.get_cmdline_user_args():check(player_travel>.25,house+": target body physically moves through furnished collision")
		if DisplayServer.get_name()!="headless":
			var camera:=Camera3D.new();stage.add_child(camera);camera.current=true;camera.position=zombie.position+Vector3(1.2,1.2,1.4);camera.look_at(zombie.position+Vector3.UP*.8)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join(house+"_awake.png"))
		driving=false;host.clear();stage.free();await frames(3)
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases},"  "))
	print("ZOMBIE_INTERIOR_PURSUIT done checks=",checks," failures=",failures);quit(1 if failures else 0)

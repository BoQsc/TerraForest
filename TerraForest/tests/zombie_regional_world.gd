# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var checks:=0
var failures:=0
var kind:=""
var trace:Array=[]
var peak_work:=0
var peak_us:=0
var phases:Array=[]
var details:Dictionary={}
var door_identity:=0
var door_centre:=Vector3.ZERO
var door_normal:=Vector3.ZERO
var minimum_intact_clearance:=INF
var camera:Camera3D
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label);return ok
func until(predicate:Callable,seconds:float)->bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<end:
		await physics_frame;game.app_focused=true
	return predicate.call()
func chase(zombie:CharacterBody3D,seconds:float,label:String)->bool:
	var before:float=game.zombie_target.damage_received
	var frames:=PackedInt64Array();var started:=Time.get_ticks_usec();var previous:=started;var first_path:=-1.0;var reached:=false
	for tick in int(seconds*Engine.physics_ticks_per_second):
		await physics_frame;game.app_focused=true
		if not is_instance_valid(zombie):return false
		if door_identity>0 and not game.doors.collection.get_instance(door_identity).is_empty():
			minimum_intact_clearance=minf(minimum_intact_clearance,(zombie.global_position-door_centre).dot(door_normal))
			if DisplayServer.get_name()!="headless" and not details.get("door_attack_captured",false) and zombie._active_action in zombie.R4_ATTACKS and zombie._action_time>.4:
				camera.position=door_centre+door_normal*4+door_normal.cross(Vector3.UP)*2+Vector3.UP*2
				camera.look_at(door_centre+Vector3.UP)
				await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute("res://reports/zombie_regional_world/"+kind)
				root.get_texture().get_image().save_png("res://reports/zombie_regional_world/"+kind+"/door_attack.png")
				details.door_attack_captured=true
		var now:=Time.get_ticks_usec();frames.append(now-previous);previous=now
		var stats:Dictionary=game.zombies.navigation_status
		peak_work=maxi(peak_work,stats.get("route_work",0));peak_us=maxi(peak_us,stats.get("planning_us",0))
		var route_state:Dictionary=game.zombies.navigator.status(zombie.get_instance_id())
		if first_path<0 and route_state.get("complete_path",false) and route_state.goal.distance_to(game.player.global_position)<.2:first_path=(now-started)/1000000.0
		if tick%60==0:
			var row:Dictionary={"phase":label,"tick":tick,"position":zombie.global_position,"navigation":game.zombies.navigator.status(zombie.get_instance_id())}
			row.velocity=zombie.velocity;row.grounded=zombie.is_on_floor();row.behavior=zombie.state
			row.planning_readiness_hits=stats.get("readiness_cache_hits",0);row.planning_readiness_probes=stats.get("readiness_probes",0)
			var direction:Vector3=zombie.navigation_target-zombie.global_position;direction.y=0;direction=direction.normalized()
			row.guards=[game.zombies.navigator.guard_motion(zombie.get_instance_id(),direction,.02),game.zombies.navigator.guard_motion(zombie.get_instance_id(),direction,.1),game.zombies.navigator.guard_motion(zombie.get_instance_id(),direction,.5)]
			row.wall=zombie.test_move(zombie.global_transform,direction*.04)
			row.head=zombie.test_move(zombie.global_transform,Vector3.UP*.3)
			var raised:Transform3D=zombie.global_transform;raised.origin.y+=.3
			row.raised_wall=zombie.test_move(raised,direction*.04)
			if tick%60==0 and row.navigation.get("complete_path",false) and row.navigation.state=="following":
				var collision:=KinematicCollision3D.new();raised.origin+=direction*.012
				row.landing=zombie.test_move(raised,Vector3.DOWN*.35,collision)
				if row.landing:row.landing_normal=collision.get_normal();row.landing_travel=collision.get_travel()
				print("WORLD_MOTOR ",JSON.stringify(row))
			trace.append(row)
			if tick%600==0:print("WORLD_NAV_PROGRESS ",JSON.stringify(row))
		if game.zombie_target.damage_received>before:reached=true;break
		if route_state.planner=="regional" and route_state.state in ["blocked","search_limit"]:break
	frames.sort()
	phases.append({"phase":label,"contact":reached,"elapsed_seconds":(Time.get_ticks_usec()-started)/1000000.0,"first_complete_path_seconds":first_path,"physics_frames":frames.size(),"frame_interval_p50_us":frames[int(frames.size()*.5)],"frame_interval_p95_us":frames[int(frames.size()*.95)],"frame_interval_max_us":frames[-1],"route":game.zombies.navigator.route_points(zombie.get_instance_id())})
	return reached
func _initialize()->void:run.call_deferred()
func run()->void:
	if not "--snapshot-readonly" in OS.get_cmdline_user_args():quit(2);return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--navigation-case="):kind=arg.trim_prefix("--navigation-case=")
	if kind not in ["cave","tower"]:quit(2);return
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	game.zombies.force_pursuit=true # Explicit pre-acquired target for saved route journeys.
	if not check(await until(func():return not game.loading_active,90),"saved actual world loads read-only"):await finish();return
	game._clear_motion();game.needs_floor_spawn=false;game.fly=false;game.app_focused=true
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	game.zombies.clear();game.zombies.population_enabled=false
	var start:Vector3
	var goal:Vector3
	var pose:=Transform3D.IDENTITY
	if kind=="cave":
		var descriptor:Dictionary=preload("res://demo/cave_checkpoint.gd").route(game.terrain.backend.world_generator,game.terrain.backend.world_seed)
		if not check(not descriptor.is_empty(),"native cave entrance and interior descriptors match the saved generator"):await finish();return
		start=descriptor.points[0];goal=descriptor.points[1]
	else:
		var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
		if not check(not layout.is_empty(),"saved regional layout identifies the actual northern district"):await finish();return
		var center:Vector3=layout.sites[3].position;game.teleport(center)
		if not check(await until(func():return not game.loading_active,60),"district residency arrives before selecting its entrance"):await finish();return
		var nearest:=INF;var identity:=0
		for id:int in game.doors.collection.get_ids():
			var data:PackedFloat32Array=game.doors.collection.get_instance(id)
			var point:=Vector3(data[3],data[7],data[11])
			if point.distance_to(center)<nearest:nearest=point.distance_to(center);identity=id
		if not check(identity>0 and nearest<120,"a real saved tower door is resident"):await finish();return
		var data:PackedFloat32Array=game.doors.collection.get_instance(identity)
		pose=Transform3D(Basis(Vector3(data[0],data[4],data[8]),Vector3(data[1],data[5],data[9]),Vector3(data[2],data[6],data[10])).orthonormalized(),Vector3(data[3],data[7],data[11]))
		start=pose*Vector3(.5,-1,6);goal=pose*Vector3(4,8,-3.5)
		door_identity=identity;door_centre=pose*Vector3(.5,0,0);door_normal=pose.basis.z.normalized()
		if (start-door_centre).dot(door_normal)<0:door_normal=-door_normal
	game.teleport(goal+Vector3.UP*.05,goal.y+.05)
	if not check(await until(func():return not game.loading_active,60),"recipient's destination collision loads through normal travel"):await finish();return
	game.needs_floor_spawn=false;game.fly=false;game.zombies.clear();game.zombies.population_enabled=false
	game.navigation_residency.update(PackedVector3Array([start,goal]))
	if not check(await until(func():return game._actor_collision_ready(AABB(start-Vector3(1,1,1),Vector3(2,4,2))),30),"separate pursuit start has ready terrain, model and vegetation collision"):await finish();return
	var zombie:CharacterBody3D
	print("WORLD_ROUTE_ENDPOINTS ",start," -> ",goal)
	for fraction in ([0.0,.125,.25,.3] if kind=="cave" else [0.0]):
		for offset in [Vector3.ZERO,Vector3(1,0,0),Vector3(-1,0,0),Vector3(0,0,1),Vector3(0,0,-1),Vector3(2,0,0),Vector3(-2,0,0),Vector3(0,0,2),Vector3(0,0,-2)]:
			zombie=game.zombies.spawn_at(start.lerp(goal,fraction)+offset)
			if zombie!=null:break
		if zombie!=null:break
	if zombie==null:
		var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start+Vector3.UP*4,start-Vector3.UP*4,1))
		print("WORLD_SPAWN_REJECT ",JSON.stringify({"start":start,"floor":hit,"ready":game._actor_collision_ready(AABB(start-Vector3(.6,4,.6),Vector3(1.2,9,1.2))),"wet":game.lakes.depth_at(start+Vector3.UP*.5),"enabled":game.zombies.enabled}))
	if not check(zombie!=null,"zombie admits at the actual street/cave approach"):await finish();return
	start=zombie.global_position
	details.start=start;details.destination=goal
	# This is a reachability/contact check. Scale its bounded travel allowance
	# from the original 0.72-m/s fixture when an authored gait is deliberately
	# slower, without changing planning budgets or the actual movement driver.
	var journey_seconds:=150.0*clampf(.72/zombie.walk_speed,1.0,2.0)
	details.walk_speed=zombie.walk_speed;details.journey_allowance_seconds=journey_seconds
	camera=Camera3D.new();game.add_child(camera);camera.position=start+Vector3(4,3,4);camera.look_at(start+Vector3.UP);camera.current=true;game.tool_view.human.hide()
	var light:=OmniLight3D.new();light.position=goal+Vector3.UP*2;light.omni_range=18;light.light_energy=3;game.add_child(light)
	check(await chase(zombie,journey_seconds,"outbound"),"zombie finds its own complete world route and reaches actual player attack contact")
	if kind=="tower":
		check(zombie.global_position.y>pose.origin.y+7.5,"pursuer physically reaches second upper floor through authored stairs")
		check(game.doors.collection.get_instance(door_identity).is_empty(),"actual generated entrance door is destroyed before upper-floor arrival")
		check(minimum_intact_clearance>.20,"pursuer stays outside the intact generated door")
		details.door_identity=door_identity;details.minimum_intact_door_clearance=minimum_intact_clearance
	else:
		var roof:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(zombie.global_position+Vector3.UP*1.8,zombie.global_position+Vector3.UP*32,1))
		check(not roof.is_empty(),"arrival is inside the actual terrain cave beneath its solid roof")
		if not roof.is_empty():details.roof_position=roof.position;details.roof_normal=roof.normal
	DirAccess.make_dir_recursive_absolute("res://reports/zombie_regional_world/"+kind)
	if DisplayServer.get_name()!="headless":
		camera.position=zombie.global_position+(Vector3(3,2,0) if kind=="cave" else pose.basis*Vector3(2,2,0));camera.look_at(zombie.global_position+Vector3.UP)
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/zombie_regional_world/"+kind+"/arrival.png")
	# The player changes destination; the pursuer receives no waypoint hints,
	# position correction, manual jump or movement calls from this fixture.
	game.player.global_position=start+Vector3.UP*.05;game.terrain.focus=game.player.global_position
	check(await chase(zombie,journey_seconds,"return"),"pursuer replans and returns from upper floor/cave to the connected approach")
	if DisplayServer.get_name()!="headless":
		camera.position=zombie.global_position+Vector3(3,2,0);camera.look_at(zombie.global_position+Vector3.UP)
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/zombie_regional_world/"+kind+"/return.png")
	check(peak_work<=48 and game.zombies.residents.size()<=6,"live host retains planning and encounter limits")
	await finish()
func finish()->void:
	DirAccess.make_dir_recursive_absolute("res://reports/zombie_regional_world/"+kind)
	var file:=FileAccess.open("res://reports/zombie_regional_world/"+kind+"/result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"case":kind,"details":details,"trace":trace,"phases":phases,"peak_work":peak_work,"peak_planning_us":peak_us,"slot":game.terrain.save_slot,"generator":game.terrain.backend.world_generator,"readonly":game.terrain.backend.readonly_snapshot},"  "));file.close()
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("ZOMBIE_REGIONAL_WORLD case=",kind," checks=",checks," failures=",failures);quit(1 if failures else 0)

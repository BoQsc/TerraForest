# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var scene:Node3D
var folder:="res://reports/zombie_route_response"
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func box(at:Vector3,size:Vector3)->void:
	var body:=StaticBody3D.new();scene.add_child(body);body.position=at
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape;body.add_child(collision)
func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pressure-output=" ):folder=arg.trim_prefix("--pressure-output=")
	run.call_deferred()
func run()->void:
	scene=Node3D.new();root.add_child(scene)
	box(Vector3(0,-.5,0),Vector3(30,1,30))
	# Actual standing body is 0.48 m wide. A 0.60 m aisle must not require
	# a 0.70 m planning capsule or an unrelated detour through the building.
	for x:float in [-.4,.4]:box(Vector3(x,1.5,0),Vector3(.2,3,6))
	var player:=CharacterBody3D.new();scene.add_child(player);player.position=Vector3(0,0,4.5)
	var collision:=CollisionShape3D.new();var shape:=CapsuleShape3D.new();shape.radius=.34;shape.height=1.8;collision.shape=shape;collision.position.y=.9;player.add_child(collision)
	var target=preload("res://addons/characters/runtime/zombie_target.gd").new();player.add_child(target)
	var host=preload("res://addons/characters/runtime/zombie_world.gd").new();scene.add_child(host);host.enabled=true;host.population_enabled=false;host.target=target;host.readiness=func(_bounds:AABB):return true
	host.trace_responses=true;host.response_trace_path=folder.path_join("response_trace.json")
	await physics_frame;await physics_frame
	var actor:CharacterBody3D=host.spawn_at(Vector3(0,0,-4.5));check(actor!=null,"narrow aisle admits the actual body")
	if actor==null:scene.free();quit(1);return
	host.configure_encounter(actor,{"profile":"roamer"});actor.receive_hit("torso",1.,actor.position+Vector3.UP)
	var touched_wall:=false
	for frame in 60*7:
		host.update(1./60.,player.position,true);await physics_frame
		if absf(actor.position.z)<3 and absf(actor.position.x)>.061:touched_wall=true
	check(actor.position.z>3,"provoked standing body crosses a physically fitting aisle")
	check(target.damage_received>0,"retaliation reaches authored attack contact after the narrow aisle")
	check(not touched_wall,"body uses the fitting aisle instead of detouring around its walls")
	var receipt:Variant=JSON.parse_string(FileAccess.get_file_as_string(host.response_trace_path))
	check(receipt is Dictionary and receipt.rows.size()>1 and receipt.rows.size()<=7 and receipt.rows.back().actors[0].has("route"),"real-hit receipt retains bounded movement and navigation diagnostics")
	var aisle:Dictionary={"position":actor.position,"damage":target.damage_received}
	host.clear();scene.free();await physics_frame
	scene=Node3D.new();root.add_child(scene)
	var ramp:=StaticBody3D.new();scene.add_child(ramp)
	var angle:=atan(.125);ramp.rotation.z=angle;ramp.position=Vector3(12,2.-.5/cos(angle),0)
	var slope:=BoxShape3D.new();slope.size=Vector3(34,1,8)
	var ramp_collision:=CollisionShape3D.new();ramp_collision.shape=slope;ramp.add_child(ramp_collision)
	var nav:Node3D=ClassDB.instantiate("NativeActorNavigator");scene.add_child(nav);nav.configure(1)
	await physics_frame;await physics_frame
	nav.set_agent(1,Vector3(-2,.25,0),Vector3(24,3.5,0),0,true)
	var state:Dictionary;var ticks:=0;var budget_ok:=true;var unpublished:=true
	for frame in 120:
		var work:Dictionary=nav.advance(1./60.,func(_bounds:AABB):return true,Callable())
		budget_ok=budget_ok and work.route_work<=work.route_work_limit and work.route_work_limit<=48
		state=nav.status(1);ticks=frame+1
		if state.state=="planning":unpublished=unpublished and nav.steering_target(1).distance_to(Vector3(-2,.25,0))<.001
		if state.state!="planning":break
		await physics_frame
	check(state.state=="following" and state.complete_path,"complete supported route reaches a distant elevated target")
	check(state.expansions==0,"open slope validates a corridor before expanding the regional graph")
	check(budget_ok,"corridor validation retains the existing scheduler budget")
	check(unpublished,"partial corridor samples never supply movement before completion")
	var corridor:Dictionary=state.duplicate()
	nav.clear();nav.set_agent(1,Vector3(-2,.25,0),Vector3(24,3.5,0),0,true)
	for frame in 120:
		nav.advance(1./60.,func(bounds:AABB):return bounds.end.x<5,Callable());state=nav.status(1)
		if state.state!="planning":break
		await physics_frame
	check(state.state=="unavailable" and nav.steering_target(1).distance_to(Vector3(-2,.25,0))<.001,"missing corridor collision suspends movement with unpublished samples")
	for frame in 120:
		nav.advance(1./60.,func(_bounds:AABB):return true,Callable());state=nav.status(1)
		if state.state=="following":break
		await physics_frame
	check(state.state=="following" and state.expansions==0,"same corridor resumes and completes when collision becomes ready")
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"aisle":aisle,"corridor":corridor,"corridor_ticks":ticks},"  "))
	scene.free();await process_frame;print("ZOMBIE_ROUTE_RESPONSE checks=",checks," failures=",failures);quit(1 if failures else 0)

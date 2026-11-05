# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var folder:="res://reports/zombie_replan_latency"
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--pressure-output="):folder=arg.trim_prefix("--pressure-output=")
	run.call_deferred()
func run()->void:
	var scene:=Node3D.new();root.add_child(scene)
	var ground:=StaticBody3D.new();scene.add_child(ground);ground.position=Vector3(0,-.5,0)
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(200,1,200);collision.shape=shape;ground.add_child(collision)
	var nav:Node3D=ClassDB.instantiate("NativeActorNavigator");scene.add_child(nav);nav.configure(1)
	await physics_frame;await physics_frame
	var position:=Vector3.ZERO;var goal:=Vector3(0,0,10)
	nav.set_agent(1,position,goal,0,true)
	check(nav.steering_target(1).distance_to(position)<.001,"cold query has no unvalidated movement")
	for frame in 180:
		nav.set_agent(1,position,goal,0,true);nav.advance(1./60.,func(_bounds:AABB):return true,Callable())
		if nav.state(1)=="following":break
		await physics_frame
	check(nav.state(1)=="following","initial complete route is available")
	for frame in 100:
		nav.set_agent(1,position,goal,0,true);nav.advance(1./60.,func(_bounds:AABB):return true,Callable())
		var waypoint:Vector3=nav.steering_target(1);var move:Vector3=waypoint-position
		if move.length()>.001 and nav.guard_motion(1,move,minf(.04,move.length())):position+=move.normalized()*minf(.04,move.length())
		await physics_frame
	var before:Dictionary=nav.status(1)
	goal=Vector3(20,0,80);nav.set_agent(1,position,goal,0,true)
	var work:Dictionary=nav.advance(1./60.,func(_bounds:AABB):return true,Callable())
	var pending:Dictionary=nav.status(1);var waypoint:Vector3=nav.steering_target(1)
	check(pending.state=="planning","changed moving goal starts a real replacement query")
	check(waypoint.distance_to(position)>.025,"replacement planning retains the next validated waypoint")
	check(work.route_work<=work.route_work_limit and work.route_work_limit<=48,"replacement retains existing scheduler limits")
	var waiting:=0;var moved_while_planning:=0.;var started:=position;var joined:=position
	for frame in 240:
		nav.set_agent(1,position,goal,0,true);nav.advance(1./60.,func(_bounds:AABB):return true,Callable())
		var state:String=nav.state(1);waypoint=nav.steering_target(1);var move:Vector3=waypoint-position
		if state=="planning" and move.length()>.025:moved_while_planning+=minf(.04,move.length())
		if state=="planning" and move.length()<.025:waiting+=1
		if move.length()>.001 and nav.guard_motion(1,move,minf(.04,move.length())):position+=move.normalized()*minf(.04,move.length())
		if state=="following" and not nav.status(1).get("continuing_previous_path",false):joined=position;break
		await physics_frame
	check(moved_while_planning>.02,"body makes guarded progress while replacement is calculated")
	waypoint=nav.steering_target(1)
	check(nav.state(1)=="following" and waypoint.z>=position.z-.05,"replacement joins ahead without returning to its former start")
	nav.set_agent(1,position,goal,0,true);nav.invalidate();check(nav.steering_target(1).distance_to(position)<.001,"geometry invalidation discards the retained waypoint")
	nav.set_agent(1,position,goal,0,true);nav.advance(1./60.,func(_bounds:AABB):return false,Callable())
	check(nav.state(1)=="unavailable" and not nav.guard_motion(1,Vector3.BACK,.04),"missing collision still stops navigation and motion")
	for scenario:String in ["edit","unavailable","stalled"]:
		nav.clear();position=Vector3.ZERO;goal=Vector3(0,0,10)
		for frame in 35:
			nav.set_agent(1,position,goal,0,true);nav.advance(1./60.,func(_bounds:AABB):return true,Callable())
			var move:Vector3=nav.steering_target(1)-position
			if move.length()>.001 and nav.guard_motion(1,move,minf(.04,move.length())):position+=move.normalized()*minf(.04,move.length())
			await physics_frame
		goal=Vector3(20,0,80);nav.set_agent(1,position,goal,0,true);nav.advance(1./60.,func(_bounds:AABB):return true,Callable())
		if scenario=="edit":
			nav.invalidate();check(nav.steering_target(1).distance_to(position)<.001,"edit interrupts an in-flight retained waypoint immediately")
		elif scenario=="unavailable":
			nav.advance(1./60.,func(_bounds:AABB):return false,Callable())
			check(nav.state(1)=="unavailable" and nav.steering_target(1).distance_to(position)<.001,"new missing coverage suspends even an in-flight retained waypoint")
		else:
			for frame in 90:nav.set_agent(1,position,goal,0,true);nav.advance(1./60.,func(_bounds:AABB):return true,Callable());nav.steering_target(1);await physics_frame
			check(not nav.status(1).get("continuing_previous_path",false),"physical blockage cannot pin a retained waypoint indefinitely")
	# A real damaged body must keep its planner while the animation owns movement.
	var player:=Node3D.new();scene.add_child(player);player.position=Vector3(5,0,10)
	var target=preload("res://addons/characters/runtime/zombie_target.gd").new();player.add_child(target)
	var host=preload("res://addons/characters/runtime/zombie_world.gd").new();scene.add_child(host);host.enabled=true;host.population_enabled=false;host.force_pursuit=true;host.target=target;host.readiness=func(_bounds:AABB):return true
	var zombie:CharacterBody3D=host.spawn_at(Vector3(5,0,0))
	check(zombie!=null,"retaliation fixture admits a physical zombie")
	if zombie!=null:
		for frame in 90:host.update(1./60.,player.position,true);await physics_frame
		zombie.receive_hit("torso",1.,zombie.position+Vector3.UP)
		host.update(1./60.,player.position,true)
		check(zombie._hit_timer>0 and host.navigator.state(zombie.get_instance_id()) in ["planning","following"],"hit reaction preserves active navigation for immediate retaliation")
	host.clear();scene.free();await process_frame
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"prior":before,"pending":pending,"guarded_progress_while_planning":moved_while_planning,"waiting_frames":waiting,"start":started,"join":joined},"  "))
	print("ZOMBIE_REPLAN_LATENCY checks=",checks," failures=",failures);quit(1 if failures else 0)

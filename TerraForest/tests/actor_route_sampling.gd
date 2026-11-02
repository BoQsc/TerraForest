# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func _initialize()->void:run.call_deferred()

func run()->void:
	var scene:=Node3D.new();root.add_child(scene)
	var body:=StaticBody3D.new();scene.add_child(body)
	var collider:=CollisionShape3D.new();var shape:=ConcavePolygonShape3D.new()
	var profile:=[Vector2(-2,0),Vector2(.1,0),Vector2(.2,-.18),Vector2(.24,0),Vector2(2,0)]
	var faces:=PackedVector3Array()
	for index in profile.size()-1:
		var left:Vector2=profile[index];var right:Vector2=profile[index+1]
		var near_left:=Vector3(left.x,left.y,-2);var far_left:=Vector3(left.x,left.y,2)
		var near_right:=Vector3(right.x,right.y,-2);var far_right:=Vector3(right.x,right.y,2)
		faces.append_array(PackedVector3Array([near_left,far_right,far_left,near_left,near_right,far_right]))
	shape.set_faces(faces);collider.shape=shape;body.add_child(collider)
	var nav:Node3D=ClassDB.instantiate("NativeActorNavigator");scene.add_child(nav);nav.configure(1)
	await physics_frame;await physics_frame
	nav.set_agent(1,Vector3.ZERO,Vector3(.5,0,0),0,true)
	nav.advance(1.0/60,func(_bounds:AABB):return true,Callable())
	check(nav.guard_motion(1,Vector3.RIGHT,.05),"flat motion before the narrow facet remains permitted")
	check(not nav.guard_motion(1,Vector3.RIGHT,.5) and nav.status(1).motion_rejection=="steep_support","half-metre edge rejects steep support hidden between midpoint and endpoint")
	nav.set_agent(1,Vector3(.14,0,0),Vector3(.5,0,0),0,true)
	check(not nav.guard_motion(1,Vector3.RIGHT,.03) and nav.status(1).motion_rejection=="steep_support","physical short motion agrees with the planning rejection")
	nav.set_agent(1,Vector3(-1,0,0),Vector3(-.5,0,0),0,true)
	check(nav.guard_motion(1,Vector3.RIGHT,.5),"ordinary supported flat edge remains permitted")
	for index in 6:
		var step_body:=StaticBody3D.new();var step_collider:=CollisionShape3D.new();var step_shape:=BoxShape3D.new()
		if index==0:step_body.position=Vector3(10,-.5,0);step_shape.size=Vector3(12,1,4)
		elif index==5:step_body.position=Vector3(12,.5,0);step_shape.size=Vector3(4,1,4)
		else:step_body.position=Vector3(8.25+(index-1)*.5,index*.125,0);step_shape.size=Vector3(.5,index*.25,4)
		step_collider.shape=step_shape;step_body.add_child(step_collider);scene.add_child(step_body)
	var walker:=CharacterBody3D.new();walker.position=Vector3(7,0,0);walker.collision_mask=7;walker.collision_layer=8;scene.add_child(walker)
	var capsule:=CapsuleShape3D.new();capsule.radius=.34;capsule.height=1.8
	var walker_shape:=CollisionShape3D.new();walker_shape.shape=capsule;walker_shape.position.y=.9;walker.add_child(walker_shape)
	var motor:RefCounted=ClassDB.instantiate("NativePlayerMovement");motor.set_step_radius(.34)
	nav.clear();nav.set_exclusions([walker.get_rid()])
	await physics_frame;await physics_frame
	var goal:=Vector3(12,1,0);var peak_work:=0
	for tick in 900:
		await physics_frame
		nav.set_agent(1,walker.position,goal,0,true)
		var measured:Dictionary=nav.advance(1.0/60,func(_bounds:AABB):return true,Callable());peak_work=maxi(peak_work,measured.route_work)
		var motion:Vector3=nav.steering_target(1)-walker.position;motion.y=0
		motion=motion.normalized()*2.1 if nav.state(1)=="following" else Vector3.ZERO
		if not nav.guard_motion(1,motion,motion.length()/60):motion=Vector3.ZERO
		walker.velocity=Vector3(motion.x,0 if walker.is_on_floor() else walker.velocity.y-20.0/60,motion.z);motor.move_grounded(walker,1.0/60)
		if walker.position.distance_to(goal)<.2:break
	check(walker.position.distance_to(goal)<.2,"real grounded controller still climbs four supported quarter-metre steps")
	check(peak_work<=48,"denser support validation retains the scheduler work cap")
	print("STAIR_RESULT ",walker.position," ",nav.status(1))
	var ground:=StaticBody3D.new();ground.position=Vector3(40,-.5,0);scene.add_child(ground)
	var ground_shape:=BoxShape3D.new();ground_shape.size=Vector3(24,1,6)
	var ground_collider:=CollisionShape3D.new();ground_collider.shape=ground_shape;ground.add_child(ground_collider)
	var strip:=StaticBody3D.new();scene.add_child(strip)
	var strip_shape:=ConcavePolygonShape3D.new();var strip_collider:=CollisionShape3D.new();faces.clear()
	profile=[Vector2(28,.02),Vector2(30.458,.02),Vector2(30.4595,.016),Vector2(30.461,.02),Vector2(52,.02)]
	for index in profile.size()-1:
		var left:Vector2=profile[index];var right:Vector2=profile[index+1]
		var near_left:=Vector3(left.x,left.y,-.1);var far_left:=Vector3(left.x,left.y,.1)
		var near_right:=Vector3(right.x,right.y,-.1);var far_right:=Vector3(right.x,right.y,.1)
		faces.append_array(PackedVector3Array([near_left,far_right,far_left,near_left,near_right,far_right]))
	strip_shape.set_faces(faces);strip_collider.shape=strip_shape;strip.add_child(strip_collider)
	nav.clear();await physics_frame;await physics_frame
	var start:=Vector3(30.442,.02,0);goal=Vector3(46,.02,0)
	for tick in 600:
		await physics_frame;nav.set_agent(1,start,goal,0,true);nav.advance(1.0/60,func(_bounds:AABB):return true,Callable())
		if nav.state(1)=="following":break
	check(nav.state(1)=="following","sub-sample facet fixture initially produces a whole route")
	var first_target:Vector3=nav.steering_target(1)
	check(not nav.guard_motion(1,first_target-start,.035) and nav.status(1).rejected_waypoints==1,"live motion rejects and remembers the missed facet without moving the body")
	for tick in 600:
		await physics_frame;nav.set_agent(1,start,goal,0,true);nav.advance(1.0/60,func(_bounds:AABB):return true,Callable())
		if nav.state(1) in ["following","blocked"]:break
	check(nav.state(1)=="following" and nav.steering_target(1).distance_to(first_target)>.1,"root rejection explores other neighbours instead of repeating the failed connector")
	nav.invalidate();check(nav.status(1).rejected_waypoints==0,"world invalidation clears disposable support failures")
	scene.free();await process_frame
	print("ACTOR_ROUTE_SAMPLING checks=",checks," failures=",failures);quit(1 if failures else 0)

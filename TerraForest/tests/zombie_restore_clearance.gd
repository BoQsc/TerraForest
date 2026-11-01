# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:run.call_deferred()
func block(stage:Node3D,bounds:AABB,layer:int=1)->StaticBody3D:
	var body:=StaticBody3D.new();body.collision_layer=layer;stage.add_child(body)
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=bounds.size;shape.shape=box;shape.position=bounds.get_center();body.add_child(shape)
	return body
func run()->void:
	var stage:=Node3D.new();root.add_child(stage)
	block(stage,AABB(Vector3(-40,-1,-40),Vector3(80,1,80)))
	# The exact baked straight-rail proxy that rejected saved resident 2519.
	var mesh:Mesh=preload("res://addons/structures/mine_rail_catalog.gd").mesh("straight")
	var rail:=block(stage,mesh.get_meta("collision_parts")[0])
	var host:=preload("res://addons/characters/runtime/zombie_world.gd").new();stage.add_child(host)
	host.readiness=func(_bounds:AABB):return true
	await physics_frame;await physics_frame
	var feet:=Vector3(.589,.1732,2)
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=host._capsule;query.transform=Transform3D(Basis.IDENTITY,feet+Vector3.UP*.9);query.collision_mask=15
	check(stage.get_world_3d().direct_space_state.intersect_shape(query,8).any(func(hit:Dictionary):return hit.collider==rail),"saved feet reproduce the real low rail contact")
	var admitted:Vector3=host.supported_resident_point(feet,true)
	check(admitted==feet,"matching standing geometry restores the exact saved rail-side position")
	if admitted.is_finite():
		check(host.supported_resident_point(admitted,true)==admitted,"repeated admission preserves the exact saved position")
	check(host.supported_resident_point(Vector3(.7666,.0004,2),true)==Vector3(.7666,.0004,2),"second saved ground-level rail edge restores exactly")
	check(not host.supported_resident_point(Vector3(.2,.15,2),true).is_finite(),"actual standing overlap with the rail still rejects")
	var body:=host.Zombie.new();stage.add_child(body)
	check(body.capsule.shape.radius==host._resident_capsule.radius and body.capsule.shape.height==host._resident_capsule.height,"restoration shape matches the actual initialized zombie movement body")
	body.free();await physics_frame
	check(host.supported_resident_point(Vector3(2,.02,2),true)==Vector3(2,.02,2),"already-clear standing pose remains exact")
	var sleeper:=Vector3(.9,.002,2)
	check(host.supported_resident_point(sleeper,false)==sleeper,"sleeping anchor retains its exact authored floor pose")
	var wall:=block(stage,AABB(feet+Vector3(-.2,0,-.2),Vector3(.4,2,.4)))
	await physics_frame;await physics_frame
	check(not host.supported_resident_point(feet,true).is_finite(),"actual standing wall overlap still rejects")
	wall.free();await physics_frame
	var ceiling:=block(stage,AABB(Vector3(-1,1.85,1),Vector3(2,.2,2)))
	await physics_frame;await physics_frame
	check(not host.supported_resident_point(feet,true).is_finite(),"actual standing overlap with a low ceiling still rejects")
	ceiling.free();await physics_frame
	var occupied:=block(stage,AABB(feet+Vector3(-.2,0,-.2),Vector3(.4,1.8,.4)),1<<16)
	await physics_frame;await physics_frame
	check(not host.supported_resident_point(feet,true).is_finite(),"occupied character space still rejects")
	occupied.free();await physics_frame
	host.readiness=func(_bounds:AABB):return false
	check(not host.supported_resident_point(feet,true).is_finite(),"missing collision residency still rejects")
	host.readiness=func(_bounds:AABB):return true
	host.water_depth=func(_point:Vector3):return 1.0
	check(not host.supported_resident_point(feet,true).is_finite(),"submerged standing point still rejects")
	host.water_depth=Callable()
	check(not host.supported_resident_point(Vector3(2,.2,2),true).is_finite(),"original support reach remains bounded without extending it")
	check(not host.supported_resident_point(Vector3(60,.17,2),true).is_finite(),"unsupported air still rejects")
	stage.free();await process_frame
	print("ZOMBIE_RESTORE_CLEARANCE checks=",checks," failures=",failures);quit(1 if failures else 0)

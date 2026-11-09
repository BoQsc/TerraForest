# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var scene:Node3D
var nav:Node3D
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func box(at:Vector3,size:Vector3)->void:
	var body:=StaticBody3D.new();body.position=at;scene.add_child(body)
	var shape:=BoxShape3D.new();shape.size=size
	var collider:=CollisionShape3D.new();collider.shape=shape;body.add_child(collider)
func permitted(feet:Vector3,direction:Vector3,travel:float=.5)->bool:
	nav.set_agent(1,feet,feet+direction,0,true)
	nav.advance(1.0/60,func(_bounds:AABB):return true,Callable())
	return nav.guard_motion(1,direction,travel)
func _initialize()->void:run.call_deferred()
func run()->void:
	scene=Node3D.new();root.add_child(scene)
	box(Vector3(24,-.5,0),Vector3(100,1,80))
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld");scene.add_child(blocks);blocks.set_collision_radius(64)
	check(blocks.set_cells(preload("res://addons/structures/furniture_catalog.gd").furnished_tower(3).get_records()),"actual tower entrance collision installs")
	blocks.flush_bakes()
	nav=ClassDB.instantiate("NativeActorNavigator");scene.add_child(nav);nav.configure(1)
	# Separate tall step remains physically impossible for the standing profile.
	box(Vector3(12.5,.25,9),Vector3(1,.5,1))
	for tick in 20:await physics_frame
	var ray:=PhysicsRayQueryParameters3D.new();ray.collision_mask=7
	for x in [.25,.5,.75]:
		for z in [9.6,9.5,9.4]:
			ray.from=Vector3(x,2,z);ray.to=Vector3(x,-1,z)
			var hit:Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(ray)
			check(not hit.is_empty() and permitted(hit.position,Vector3.FORWARD),"quarter-metre risers remain traversable at x=%s z=%s"%[x,z])
	check(not permitted(Vector3(12.5,0,9.75),Vector3.FORWARD),"a single half-metre riser remains rejected")
	check(nav.status(1).motion_rejection=="step_height","tall step fails support validation rather than a route timeout")
	scene.free();await process_frame
	print("NAVIGATION_TREADS checks=",checks," failures=",failures);quit(1 if failures else 0)

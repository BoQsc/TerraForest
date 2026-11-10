# SPDX-License-Identifier: 0BSD
extends SceneTree
## Compare incremental compound construction in/out of the physics space.
## No terrain generation, saved world, imported asset or persistent cache.
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var scene:=Node3D.new();root.add_child(scene)
	var shape:=BoxShape3D.new();shape.size=Vector3(0.8,0.2,0.8)
	var results:Dictionary={}
	for detached:bool in [false,true]:
		var totals:Array[int]=[];var activation:Array[int]=[];var pieces:Array[int]=[];var retirement:Array[int]=[]
		for repetition in 12:
			var body:=StaticBody3D.new();body.collision_layer=0;body.collision_mask=0
			if detached:body.process_mode=Node.PROCESS_MODE_DISABLED
			scene.add_child(body)
			check(PhysicsServer3D.body_get_space(body.get_rid()).is_valid()!=detached,"preparation space state")
			var began:=Time.get_ticks_usec()
			for index in 64:
				var piece_begin:=Time.get_ticks_usec()
				var collision:=CollisionShape3D.new();collision.shape=shape
				collision.position=Vector3(index%16,0,index/16);body.add_child(collision)
				pieces.append(Time.get_ticks_usec()-piece_begin)
			totals.append(Time.get_ticks_usec()-began)
			var query:=PhysicsRayQueryParameters3D.create(Vector3(1,2,1),Vector3(1,-2,1),1)
			check(scene.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"prepared shapes cannot collide before publication")
			began=Time.get_ticks_usec();body.collision_layer=1
			body.process_mode=Node.PROCESS_MODE_INHERIT
			activation.append(Time.get_ticks_usec()-began)
			await physics_frame;await physics_frame
			check(not scene.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"complete compound collides after publication")
			body.collision_layer=0
			if detached:body.process_mode=Node.PROCESS_MODE_DISABLED
			check(PhysicsServer3D.body_get_space(body.get_rid()).is_valid()!=detached,"retirement space state")
			began=Time.get_ticks_usec()
			for child in body.get_children():child.free()
			retirement.append(Time.get_ticks_usec()-began)
			body.free()
		totals.sort();activation.sort();pieces.sort();retirement.sort()
		results["detached" if detached else "in_space"]={"build_median_us":totals[6],"build_max_us":totals[11],"publish_median_us":activation[6],"publish_max_us":activation[11],"piece_p99_us":pieces[760],"retire_median_us":retirement[6],"retire_max_us":retirement[11]}
	scene.free();await process_frame
	print("TERRAIN_COLLISION_PREPARATION ",JSON.stringify(results))
	print("TERRAIN_COLLISION_PREPARATION failures=",failures);quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func box(scene:Node3D,at:Vector3,size:Vector3)->void:
	var body:=StaticBody3D.new();body.position=at
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape;body.add_child(collision);scene.add_child(body)
func run()->void:
	var failures:=0
	for kind in ["narrow","tower"]:
		var scene:=Node3D.new();root.add_child(scene)
		box(scene,Vector3(0,-.5,4),Vector3(30,1,30))
		if kind=="narrow":
			for index in 4:box(scene,Vector3(0,(index+1)*.125,index*.25),Vector3(3,(index+1)*.25,.25))
			box(scene,Vector3(0,.5,3.375),Vector3(3,1,5))
		else:
			var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld");scene.add_child(blocks);blocks.set_collision_radius(48)
			blocks.set_cells(preload("res://addons/structures/furniture_catalog.gd").furnished_tower(3).get_records());blocks.flush_bakes()
			for tick in 90:await physics_frame
		var start:=Vector3(0,.06,-1) if kind=="narrow" else Vector3(.5,.06,12)
		var direction:=Vector3.BACK if kind=="narrow" else Vector3.FORWARD
		var goal:=Vector3(0,1,4) if kind=="narrow" else Vector3(.5,1,6)
		var body:=CharacterBody3D.new();body.collision_layer=1<<16;body.collision_mask=15|(1<<16);scene.add_child(body);body.position=start
		var collider:=CollisionShape3D.new();var shape:=CapsuleShape3D.new();shape.radius=.24;shape.height=1.74;collider.shape=shape;collider.position.y=.87;body.add_child(collider)
		var nav:Node3D=ClassDB.instantiate("NativeActorNavigator");scene.add_child(nav);nav.configure(1)
		var motor:RefCounted=ClassDB.instantiate("NativePlayerMovement");motor.set_step_radius(.24)
		var peak_rise:=0.0;var steps:=0;var arrived:=false
		for tick in 1200:
			await physics_frame
			nav.set_agent(1,body.position,goal,0,true);nav.advance(1.0/60,func(_b:AABB):return true,Callable())
			var guard:bool=nav.guard_motion(1,direction,.012)
			var vertical:float=-.1 if body.is_on_floor() else body.velocity.y-9.8/60
			body.velocity=direction*(.72 if guard else 0);body.velocity.y=vertical
			var previous_y:=body.position.y
			var stepped:bool=motor.move_grounded(body,1.0/60)
			if stepped:steps+=1;peak_rise=maxf(peak_rise,body.position.y-previous_y)
			if tick%120==0:print("STEP ",kind," ",tick," ",body.position," guard=",guard," floor=",body.is_on_floor())
			arrived=body.position.z>2 if kind=="narrow" else body.position.z<6.2
			if arrived:break
		var passed:=arrived and body.position.y>.9 and steps>0 and peak_rise<=.301 and body.is_on_floor()
		print(("PASS " if passed else "FAIL "),kind," slow capsule steps: peak_rise=",peak_rise," verified_steps=",steps)
		if not passed:failures+=1
		scene.free();await process_frame
	print("ZOMBIE_STEP_GUARD ","PASS" if failures==0 else "FAIL");quit(0 if failures==0 else 1)

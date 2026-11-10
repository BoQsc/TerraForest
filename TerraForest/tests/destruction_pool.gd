# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld")
	var effects=load("res://addons/player_runtime/destruction_effects.gd").new()
	effects.blocks=blocks;effects.pooled=true;root.add_child(effects)
	check(effects.pool.size()==96 and effects.available.size()==96,"exactly 96 slots preallocated")
	var ids:Array=[]
	for body:RigidBody3D in effects.pool:
		ids.append(body.get_instance_id())
		check(not PhysicsServer3D.body_get_space(body.get_rid()).is_valid(),"inactive slot is absent from physics")
	var word:int=blocks.encode_block(1,0,0)
	for i in 96:effects.block(Vector3i(i,10,0),word,Vector3.ZERO,9)
	var first:RigidBody3D=effects.fragments[0].body
	first.global_basis=Basis.from_euler(Vector3(.5,.7,.9));first.constant_force=Vector3.ONE*100;first.constant_torque=Vector3.ONE*50
	effects.block(Vector3i(3,20,4),blocks.encode_block(1,0,3),Vector3(3.5,20.5,4.5),7)
	var reused:RigidBody3D=effects.fragments.back().body
	check(reused==first and effects.fragments.size()==96 and effects.available.is_empty(),"oldest body replaced in place at unchanged limit")
	check(reused.global_basis==Basis.IDENTITY and reused.global_position==Vector3(3.5,20.5,4.5),"reused transform resets rotation and position")
	check(reused.constant_force==Vector3.ZERO and reused.constant_torque==Vector3.ZERO and reused.linear_velocity==Vector3.UP*7,"forces and zero-distance launch reset")
	check(reused.mass==20 and reused.continuous_cd and reused.collision_layer==1<<20 and reused.collision_mask==7,"mass CCD and collision rules preserved")
	effects.step(2,false)
	check(reused.freeze and effects.fragments.back().remaining==8,"pause freezes physics and lifetime")
	effects.step(7.9,true)
	check(not reused.freeze and effects.fragments.size()==96,"resume retains eight second lifetime")
	effects.step(.11,true)
	check(effects.fragments.is_empty() and effects.available.size()==96,"expiration returns every slot")
	for round_index in 3:
		for i in 110:effects.block(Vector3i(i,10,0),word,Vector3.ZERO,9)
		effects.clear()
	check(effects.get_child_count()==96 and effects.available.size()==96,"repeated destruction and clear keep node count bounded")
	for body:RigidBody3D in effects.pool:
		check(ids.has(body.get_instance_id()) and not PhysicsServer3D.body_get_space(body.get_rid()).is_valid(),"original slots retained without inactive colliders")
	var floor_body:=StaticBody3D.new();var floor_shape:=CollisionShape3D.new();var box:=BoxShape3D.new()
	box.size=Vector3(20,1,20);floor_shape.shape=box;floor_body.add_child(floor_shape);root.add_child(floor_body)
	effects.block(Vector3i(0,3,0),word,Vector3.ZERO,0)
	var falling:RigidBody3D=effects.fragments[0].body
	for tick in 100:await physics_frame
	check(falling.global_position.y>.8 and falling.global_position.y<1.3,"reused physical shape lands on the unchanged floor")
	var landed:=falling.global_transform
	effects.step(0,false)
	for tick in 5:await physics_frame
	check(falling.global_transform.is_equal_approx(landed),"paused reused body stays fixed through real physics ticks")
	effects.clear();floor_body.free()
	var measurements:Array=[]
	# Same warmed geometry/materials and exact 96-body workload. These are enqueue
	# timings only; renderer/physics-step and frame-tail acceptance remain separate.
	for use_pool:bool in [false,true,true,false]:
		var target=effects
		if not use_pool:
			target=load("res://addons/player_runtime/destruction_effects.gd").new()
			target.pooled=false;target.blocks=blocks;root.add_child(target)
		target.block(Vector3i.ZERO,word,Vector3.ZERO,1);target.clear();await process_frame
		var begin:=Time.get_ticks_usec()
		for i in 96:target.block(Vector3i(i,20,0),word,Vector3.ZERO,9)
		var enqueued:=Time.get_ticks_usec()
		target.clear()
		measurements.append({"pooled":use_pool,"enqueue_us":enqueued-begin,"clear_us":Time.get_ticks_usec()-enqueued})
		await process_frame
		if not use_pool:target.free()
	print("DESTRUCTION_POOL_WORK ",JSON.stringify(measurements))
	effects.free();blocks.free();await process_frame
	print("DESTRUCTION_POOL failures=",failures);quit(1 if failures else 0)

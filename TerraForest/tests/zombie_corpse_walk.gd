extends "res://tests/zombie_ragdoll_reactivation.gd"

func run()->void:
	print("CORPSE_PHYSICS_ENGINE ",ProjectSettings.get_setting("physics/3d/physics_engine","unknown"))
	stage=Node3D.new();root.add_child(stage)
	var floor:=StaticBody3D.new();floor.collision_layer=1;floor.position.y=-.5;stage.add_child(floor)
	var ground:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(30,1,30);ground.shape=box;floor.add_child(ground)
	zombie=Zombie.new();zombie.position=Vector3(0,.04,0);stage.add_child(zombie);zombie.set_behavior(false)
	check(zombie.initialized,"production corpse walk fixture initializes")
	await ticks(3)
	zombie.die(Vector3(1,0,0));await ticks(2)
	for body:PhysicalBone3D in zombie.physical_bones.values():
		if body.joint_type==PhysicalBone3D.JOINT_TYPE_NONE:continue
		var ancestor:int=zombie.skeleton.get_bone_parent(body.get_bone_id())
		while ancestor>=0:
			var name:String=zombie.skeleton.get_bone_name(ancestor)
			if zombie.physical_bones.has(name):
				var parent:PhysicalBone3D=zombie.physical_bones[name]
				var child_pose:Transform3D=zombie.skeleton.global_transform*zombie._death_pose[body.get_bone_id()]*body.body_offset
				var parent_pose:Transform3D=zombie.skeleton.global_transform*zombie._death_pose[parent.get_bone_id()]*parent.body_offset
				anchors.append({"child":body,"parent":parent,"child_point":body.joint_offset.origin,"parent_point":parent_pose.affine_inverse()*(child_pose*body.joint_offset.origin)})
				break
			ancestor=zombie.skeleton.get_bone_parent(ancestor)
	await ticks(600)
	check(zombie.anatomy.ragdoll_stats().sleeping==15,"corpse settles before walking")
	pusher=CharacterBody3D.new();pusher.collision_layer=2;pusher.collision_mask=1|Zombie.RAGDOLL_LAYER;pusher.platform_floor_layers=1
	pusher.safe_margin=.004;pusher.max_slides=8;pusher.floor_snap_length=.35;pusher.floor_max_angle=deg_to_rad(48);pusher.floor_constant_speed=true;stage.add_child(pusher)
	var collider:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.34;capsule.height=1.8;collider.shape=capsule;collider.position.y=.9;pusher.add_child(collider)
	movement=ClassDB.instantiate("NativePlayerMovement")
	var rows:Array=[]
	for direction:Vector3 in [Vector3.RIGHT,Vector3.BACK,Vector3.LEFT,Vector3.FORWARD]:
		var center:Vector3=zombie.physical_bones.Spine2.global_position;center.y=.05
		await relocate_player(center-direction*2)
		await ticks(12)
		var target:Vector3=center+direction*2
		var peak_speed:=0.0;var contacts:=0;var highest:=0.0
		var torso_speed:=0.0;var peak_anchor:=0.0;var peak_radius:=0.0;var peak_angular:=0.0;var finite:=true
		for frame in 240:
			await physics_frame
			var delta:Vector3=target-pusher.position;delta.y=0
			if delta.length()<.15:break
			pusher.velocity=movement.walking_velocity(delta.normalized(),pusher.velocity,1.0/60,false,pusher.is_on_floor(),false)
			movement.move_grounded(pusher,1.0/60)
			for collision in pusher.get_slide_collision_count():
				if PhysicsServer3D.body_get_collision_layer(pusher.get_slide_collision(collision).get_collider_rid())&Zombie.RAGDOLL_LAYER:contacts+=1
			highest=maxf(highest,pusher.position.y)
			peak_speed=maxf(peak_speed,float(zombie.anatomy.ragdoll_stats().maximum_linear_speed))
			var current:Dictionary=measure()
			finite=finite and current.finite
			peak_anchor=maxf(peak_anchor,current.anchor_error);peak_radius=maxf(peak_radius,current.radius);peak_angular=maxf(peak_angular,current.angular)
			var torso_velocity:Vector3=PhysicsServer3D.body_get_state(zombie.physical_bones.Spine2.get_rid(),PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			torso_speed=maxf(torso_speed,torso_velocity.length())
		check(Vector2(pusher.position.x,pusher.position.z).distance_to(Vector2(target.x,target.z))<.2,"walk across corpse without jumping / "+str(direction))
		check(highest>.1 and contacts>0,"route actually walks on corpse collision / "+str(direction))
		check(finite and torso_speed<3 and peak_speed<12 and peak_angular<120 and peak_anchor<.08 and peak_radius<2.5,"walking keeps torso motion and every anatomical joint bounded / "+str(direction))
		rows.append({"direction":str(direction),"end":str(pusher.position),"target":str(target),"highest":highest,"contacts":contacts,"corpse_peak_speed":peak_speed,"torso_speed":torso_speed,"anchor_error":peak_anchor,"radius":peak_radius})
		await relocate_player(Vector3(10,.05,10));await ticks(180)
		check(zombie.anatomy.ragdoll_stats().sleeping==15 and zombie.anatomy.ragdoll_stats().maximum_linear_speed<.01,"corpse returns to quiet rest after walking / "+str(direction))
	DirAccess.make_dir_recursive_absolute("res://reports/zombie_corpse_walk")
	FileAccess.open("res://reports/zombie_corpse_walk/result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"routes":rows},"  "))
	stage.free();await process_frame
	print("ZOMBIE_CORPSE_WALK failures=",failures);quit(1 if failures else 0)

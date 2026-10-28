extends SceneTree
const Zombie=preload("res://addons/characters/runtime/zombie.gd")
var failures:=0
var rows:Array=[]
var stage:Node3D
var zombie:Node3D
var anchors:Array=[]
var camera:Camera3D
var pusher:CharacterBody3D
var pushing:=false
var push_direction:=Vector3.ZERO
var push_contacts:=0
var movement:RefCounted
var expected_joints:=0
var forest:=false
var game:Node
var home:=Vector3(950,35.05,1130)
var pose:=""
var folder:="res://reports/zombie_ragdoll_reactivation"
func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->void:
	print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
func ticks(count:int)->void:
	for frame in count:await physics_frame
func relocate_player(point:Vector3)->void:
	var layer:=pusher.collision_layer;var mask:=pusher.collision_mask
	pusher.collision_layer=0;pusher.collision_mask=0;pusher.velocity=Vector3.ZERO;pusher.global_position=point
	await ticks(2)
	pusher.collision_layer=layer;pusher.collision_mask=mask
func place_player(point:Vector3)->void:
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*3,point-Vector3.UP*8,7)
	query.exclude=[pusher.get_rid()]
	var hit:Dictionary=stage.get_world_3d().direct_space_state.intersect_ray(query)
	await relocate_player(hit.position+Vector3.UP*.02 if not hit.is_empty() else point)
func measure()->Dictionary:
	var stats:Dictionary=zombie.anatomy.ragdoll_stats()
	var error:=0.0;var span:=0.0;var finite:=true;var joints:=0
	var center:Vector3=zombie.physical_bones.Hips.global_position
	for body:PhysicalBone3D in zombie.physical_bones.values():
		if body.joint_type!=PhysicalBone3D.JOINT_TYPE_NONE:joints+=1
		finite=finite and body.global_transform.is_finite() and body.linear_velocity.is_finite() and body.angular_velocity.is_finite()
		span=maxf(span,body.global_position.distance_to(center))
	for anchor:Dictionary in anchors:
		if not is_instance_valid(anchor.child) or not is_instance_valid(anchor.parent):continue
		error=maxf(error,(anchor.child.global_transform*anchor.child_point).distance_to(anchor.parent.global_transform*anchor.parent_point))
	return {"linear":stats.maximum_linear_speed,"angular":stats.maximum_angular_speed,"anchor_error":error,"radius":span,"finite":finite,"sleeping":stats.sleeping,"resting":stats.resting,"joints":joints}
func observe(label:String,count:int)->void:
	var peak:={"phase":label,"linear":0.0,"angular":0.0,"anchor_error":0.0,"radius":0.0,"finite":true,"joints_intact":true,"displacement":0.0,"player_speed":0.0,"fastest_bone":"","corpse_contacts":0}
	var immediate:=measure()
	for key:String in ["linear","angular","anchor_error","radius"]:peak[key]=immediate[key]
	peak.finite=immediate.finite;peak.joints_intact=immediate.joints==expected_joints;peak["immediate"]=immediate
	var initial:Dictionary={}
	for bone:String in zombie.physical_bones:initial[bone]=zombie.physical_bones[bone].global_position
	for frame in count:
		await physics_frame
		if pushing:
			pusher.velocity=movement.walking_velocity(push_direction,pusher.velocity,1.0/60.0,false,pusher.is_on_floor(),false)
			movement.move_grounded(pusher,1.0/60.0)
			push_contacts+=pusher.get_slide_collision_count()
			for contact in pusher.get_slide_collision_count():
				if PhysicsServer3D.body_get_collision_layer(pusher.get_slide_collision(contact).get_collider_rid())&Zombie.RAGDOLL_LAYER:peak.corpse_contacts+=1
			peak.player_speed=maxf(peak.player_speed,pusher.get_real_velocity().length())
		var current:=measure()
		if current.linear>peak.linear:
			var speed:=0.0
			for bone:String in zombie.physical_bones:
				var velocity:Vector3=zombie.physical_bones[bone].linear_velocity
				if velocity.length()>speed:speed=velocity.length();peak.fastest_bone=bone
		for key:String in ["linear","angular","anchor_error","radius"]:peak[key]=maxf(peak[key],current[key])
		peak.finite=peak.finite and current.finite
		peak.joints_intact=peak.joints_intact and current.joints==expected_joints
		for bone:String in initial:peak.displacement=maxf(peak.displacement,zombie.physical_bones[bone].global_position.distance_to(initial[bone]))
	peak["final"]=measure();rows.append(peak);print("REACTIVATION ",JSON.stringify(peak))
	check(peak.finite and peak.linear<12 and peak.angular<120 and peak.anchor_error<.08 and peak.radius<2.5,"modest corpse interaction stays connected and bounded: "+label)
	check(peak.joints_intact,"sleep and contact preserve every anatomical joint: "+label)
	if label.begins_with("physical_push_"):check(peak.displacement>.001 and peak.linear>.1,"external physical impulse wakes and moves corpse: "+label)
func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--reactivation-evidence="):folder=argument.trim_prefix("--reactivation-evidence=")
		if argument=="--forest":forest=true
		if argument.begins_with("--pose="):pose=argument.trim_prefix("--pose=")
	DirAccess.make_dir_recursive_absolute(folder)
	if forest:
		game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
		var deadline:=Time.get_ticks_msec()+60000
		while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
		check(not game.loading_active,"temporary streamed world is ready")
		if game.loading_active:quit(1);return
		game.set_physics_process(false);game._clear_motion();game.needs_floor_spawn=false
		game.zombies.population_enabled=false;game.zombies.clear();game.zombies.enabled=true;stage=game;pusher=game.player;camera=game.camera
		check((pusher.collision_mask&Zombie.RAGDOLL_LAYER)!=0 and (pusher.platform_floor_layers&Zombie.RAGDOLL_LAYER)==0,"real player blocks corpses without treating limbs as moving platforms")
		home=game.player.global_position+Vector3(0,0,2)
		zombie=game.zombies.spawn_at(home)
		if zombie==null:check(false,"corpse fixture admits on real terrain");quit(1);return
		home=zombie.global_position;zombie.set_behavior(false)
	else:
		stage=Node3D.new();root.add_child(stage)
		var floor:=StaticBody3D.new();floor.position=Vector3(950,34.5,1130);floor.collision_layer=1;stage.add_child(floor)
		var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(40,1,40);collision.shape=shape;floor.add_child(collision)
		var visual:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=shape.size;visual.mesh=mesh;floor.add_child(visual)
		var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);stage.add_child(light)
		camera=Camera3D.new();stage.add_child(camera);camera.current=true
		zombie=Zombie.new();zombie.position=home;stage.add_child(zombie);zombie.set_behavior(false)
	check(zombie.initialized,"production zombie initializes")
	await ticks(3)
	if not pose.is_empty():
		zombie.play_clip(pose);zombie.animation_player.pause();zombie.animation_player.seek(.7,true);zombie.skeleton.force_update_all_bone_transforms()
	zombie.die(Vector3(1,0,0));await ticks(2)
	for body:PhysicalBone3D in zombie.physical_bones.values():
		if body.joint_type!=PhysicalBone3D.JOINT_TYPE_NONE:expected_joints+=1
		var ancestor:int=zombie.skeleton.get_bone_parent(body.get_bone_id())
		while ancestor>=0:
			var name:String=zombie.skeleton.get_bone_name(ancestor)
			if zombie.physical_bones.has(name):
				var parent:PhysicalBone3D=zombie.physical_bones[name]
				var point:Vector3=body.global_transform*body.joint_offset.origin
				anchors.append({"child":body,"parent":parent,"child_point":body.joint_offset.origin,"parent_point":parent.global_transform.affine_inverse()*point});break
			ancestor=zombie.skeleton.get_bone_parent(ancestor)
	await ticks(600)
	check(zombie.anatomy.ragdoll_stats().sleeping==15,"corpse settles before interaction")
	check(expected_joints==14 and measure().joints==expected_joints,"settling retains all fourteen joints")
	if pusher==null:
		pusher=CharacterBody3D.new();pusher.collision_layer=2;pusher.collision_mask=1|Zombie.RAGDOLL_LAYER;pusher.platform_floor_layers=1|4;stage.add_child(pusher)
		pusher.safe_margin=.01;pusher.floor_snap_length=.35;pusher.floor_max_angle=deg_to_rad(48);pusher.floor_constant_speed=true
		var player_shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.34;capsule.height=1.8;player_shape.shape=capsule;player_shape.position.y=.9;pusher.add_child(player_shape)
	if "--one-way-contact" in OS.get_cmdline_user_args():pusher.collision_mask=1
	movement=ClassDB.instantiate("NativePlayerMovement")
	for direction:Vector3 in [Vector3.RIGHT,Vector3.BACK,Vector3.LEFT]:
		await place_player(zombie.physical_bones.Spine2.global_position-direction*2.5)
		push_direction=direction;push_contacts=0;pushing=true
		await observe("walk_push_"+str(direction),240)
		print("PUSH_CONTACTS ",push_contacts)
		pushing=false;await relocate_player(home+Vector3(12,0,12))
		await observe("after_walk_"+str(direction),180)
	await relocate_player(zombie.physical_bones.Spine2.global_position+Vector3(0,1.5,0));push_direction=Vector3.ZERO;pushing=true
	await observe("land_on_corpse",240)
	if game!=null:
		pushing=false
		var velocities:Dictionary={};var spaces:Dictionary={}
		for bone:String in zombie.physical_bones:
			var body:PhysicalBone3D=zombie.physical_bones[bone]
			velocities[bone]=[PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY),PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)]
			spaces[bone]=PhysicsServer3D.body_get_space(body.get_rid())
		zombie.process_mode=Node.PROCESS_MODE_DISABLED;game.corpse_loot.set_frozen(zombie,true)
		var frozen:Dictionary=zombie.get_meta("corpse_body_modes")
		var authoritative:=true
		for bone:String in velocities:authoritative=authoritative and frozen[bone][1]==velocities[bone][0] and frozen[bone][2]==velocities[bone][1]
		check(authoritative,"loot pause records authoritative physics velocities")
		await ticks(12)
		var registered:=true
		for bone:String in spaces:registered=registered and spaces[bone].is_valid() and PhysicsServer3D.body_get_space(zombie.physical_bones[bone].get_rid())==spaces[bone]
		check(registered,"loot pause preserves the connected bodies in their physics space")
		game.corpse_loot.set_frozen(zombie,false);zombie.process_mode=Node.PROCESS_MODE_INHERIT
		await observe("loot_resume_under_player",180)
	pushing=false;await relocate_player(home+Vector3(12,0,12));await observe("after_landing",180)
	var push_only:bool="--push-only" in OS.get_cmdline_user_args()
	for cycle in (0 if push_only else 3):
		zombie.anatomy.wake_ragdolls()
		zombie.physical_bones.Spine2.apply_central_impulse(Vector3(8,2,0))
		await observe("explicit_wake_"+str(cycle),180)
		await ticks(180)
	for bone:String in ([] if push_only else ["Spine2","Head","LeftLeg"]):
		if not zombie.physical_bones.has(bone):check(false,"test bone exists: "+bone);continue
		zombie.physical_bones[bone].apply_central_impulse(Vector3(6,1,0))
		await observe("physical_push_"+bone,180)
		await ticks(180)
	if game!=null:game.tool_view.hide()
	camera.global_position=zombie.physical_bones.Hips.global_position+Vector3(2,1.5,2);camera.look_at(zombie.physical_bones.Hips.global_position)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join("after.png"))
	check(zombie.anatomy.ragdoll_stats().sleeping==15,"corpse returns to rest after interactions")
	var contacts:=0
	for row:Dictionary in rows:contacts+=row.corpse_contacts
	check(contacts>0,"player actually contacts the corpse")
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rows":rows,"final":zombie.anatomy.ragdoll_stats()},"  "))
	if game!=null:game.shutdown_requested=true;await game.terrain.shutdown_after_edits()
	stage.free();await process_frame;print("ZOMBIE_RAGDOLL_REACTIVATION failures=",failures);quit(1 if failures else 0)

extends "res://tests/zombie_ragdoll_reactivation.gd"

const STRESS_CASES=["flat","slope","stairs","rubble","corner","ledge","pile","severed","far_origin","ground_pile"]
var subjects:Array[Node3D]=[]
var supports:Array[StaticBody3D]=[]
var shared_geometry:RefCounted
var base:=Vector3.ZERO
var summary:Array=[]
var physics_hz:=60
var cases:Array[String]=[]

func solid(size:Vector3,point:Vector3,angles:Vector3=Vector3.ZERO)->StaticBody3D:
	var support:=StaticBody3D.new();support.collision_layer=1;support.position=base+point;support.rotation_degrees=angles;stage.add_child(support)
	var material:=PhysicsMaterial.new();material.friction=1.0;material.rough=true;support.physics_material_override=material
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;support.add_child(shape)
	if DisplayServer.get_name()!="headless":
		var visual:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;visual.mesh=mesh;support.add_child(visual)
		var surface:=StandardMaterial3D.new();surface.albedo_color=Color(.18,.22,.25);surface.roughness=.9;visual.material_override=surface
	supports.append(support);return support

func remember_constraints(subject:Node3D)->void:
	var connections:Array=[]
	var detached_joints:Array=[]
	for body:PhysicalBone3D in subject.physical_bones.values():
		var ancestor:int=subject.skeleton.get_bone_parent(body.get_bone_id())
		while ancestor>=0:
			var name:String=subject.skeleton.get_bone_name(ancestor)
			if subject.physical_bones.has(name) and body.joint_type!=PhysicalBone3D.JOINT_TYPE_NONE:
				var parent:PhysicalBone3D=subject.physical_bones[name]
				var initial_child:Transform3D=subject.skeleton.global_transform*subject._death_pose[body.get_bone_id()]*body.body_offset
				var initial_parent:Transform3D=subject.skeleton.global_transform*subject._death_pose[parent.get_bone_id()]*parent.body_offset
				var point:Vector3=initial_child*body.joint_offset.origin
				connections.append({"child":body,"parent":parent,"child_point":body.joint_offset.origin,"parent_point":initial_parent.affine_inverse()*point});break
			ancestor=subject.skeleton.get_bone_parent(ancestor)
	for part:RigidBody3D in subject.detached_parts:
		for node in part.get_children():
			if node is Joint3D and node.has_meta("anchor_a"):
				connections.append({"child":node.get_meta("body_a"),"parent":node.get_meta("body_b"),"child_point":node.get_meta("anchor_a"),"parent_point":node.get_meta("anchor_b")})
				detached_joints.append(node)
	subject.set_meta("stress_anchors",connections)
	subject.set_meta("stress_joints",subject.physical_bones.size()-1)
	subject.set_meta("stress_detached_joints",detached_joints)

func phase(label:String,seconds:float,linear_limit:float=12.0)->Dictionary:
	var peak:={"phase":label,"linear":0.0,"angular":0.0,"anchor_error":0.0,"anchor_bone":"","anchor_pose":"","anchor_frame":0,"radius":0.0,"finite":true,"joints":true,"ccd":true,"physics_ms":0.0}
	for frame in ceili(seconds*physics_hz):
		await physics_frame
		peak.physics_ms=maxf(peak.physics_ms,float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))*1000)
		for subject:Node3D in subjects:
			var stats:Dictionary=subject.anatomy.ragdoll_stats()
			peak.linear=maxf(peak.linear,stats.maximum_linear_speed);peak.angular=maxf(peak.angular,stats.maximum_angular_speed)
			if frame%6==0:
				zombie=subject;anchors=subject.get_meta("stress_anchors")
				var current:=measure()
				peak.finite=peak.finite and current.finite
				peak.joints=peak.joints and current.joints==subject.get_meta("stress_joints")
				for joint:Joint3D in subject.get_meta("stress_detached_joints"):
					peak.joints=peak.joints and is_instance_valid(joint) and joint.get_node_or_null(joint.node_a)==joint.get_meta("body_a") and joint.get_node_or_null(joint.node_b)==joint.get_meta("body_b")
				for body:PhysicalBone3D in subject.physical_bones.values():
					peak.ccd=peak.ccd and (body.is_resting() or PhysicsServer3D.body_is_continuous_collision_detection_enabled(body.get_rid()))
				for part:RigidBody3D in subject.detached_parts:
					for body:RigidBody3D in part.get_meta("segment_bodies"):
						peak.finite=peak.finite and body.global_transform.is_finite() and body.linear_velocity.is_finite() and body.angular_velocity.is_finite()
						peak.ccd=peak.ccd and (body.is_resting() or body.continuous_cd)
						peak.radius=maxf(peak.radius,body.global_position.distance_to(part.global_position))
				if current.anchor_error>peak.anchor_error:
					peak.anchor_pose=subject.get_meta("stress_pose");peak.anchor_frame=frame
					var worst:=0.0
					for link:Dictionary in anchors:
						var separation:float=(link.child.global_transform*link.child_point).distance_to(link.parent.global_transform*link.parent_point)
						if separation>worst:worst=separation;peak.anchor_bone=String(link.child.name)
				peak.anchor_error=maxf(peak.anchor_error,current.anchor_error);peak.radius=maxf(peak.radius,current.radius)
	var sleeping:=0;var bodies:=0;var details:Array=[]
	for subject:Node3D in subjects:
		var stats:Dictionary=subject.anatomy.ragdoll_stats();sleeping+=stats.sleeping;bodies+=stats.bodies
		details.append({"pose":subject.get_meta("stress_pose"),"stats":stats,"hips":str(subject.physical_bones.Hips.global_position)})
	peak["sleeping"]=sleeping;peak["bodies"]=bodies
	peak["details"]=details
	check(peak.finite and peak.linear<linear_limit and peak.angular<120 and peak.anchor_error<.08 and peak.radius<2.5,"finite bounded articulated motion: "+label)
	check(peak.joints,"anatomical joints retained: "+label)
	check(peak.ccd,"active bodies retain swept collision: "+label)
	print("RAGDOLL_STRESS ",JSON.stringify(peak));return peak

func picture(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	var center:Vector3=subjects[subjects.size()/2].physical_bones.Hips.global_position
	camera.global_position=center+Vector3(3.5,3,4.5);camera.look_at(center)
	var overlay:=CanvasLayer.new();stage.add_child(overlay)
	var sleeping:=0;var bodies:=0
	for subject:Node3D in subjects:
		var stats:Dictionary=subject.anatomy.ragdoll_stats();sleeping+=stats.sleeping;bodies+=stats.bodies
	var caption:=Label.new();caption.text="RAGDOLL PHYSICS TEST | "+label+" | "+str(physics_hz)+" Hz\nProduction rig, real collisions, no animation motors | "+str(subjects.size())+" corpses | Asleep: "+str(sleeping)+" / "+str(bodies);caption.position=Vector2(24,24);caption.add_theme_font_size_override("font_size",22);caption.add_theme_color_override("font_outline_color",Color.BLACK);caption.add_theme_constant_override("outline_size",6);overlay.add_child(caption)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label+".png"))==OK,"stress capture: "+label)
	overlay.free()

func run_case(name:String)->void:
	stage=Node3D.new();root.add_child(stage);subjects.clear();supports.clear()
	base=Vector3(1550,45,1550) if name=="far_origin" else Vector3.ZERO
	if name=="slope":solid(Vector3(100,1,100),Vector3(0,-.5*cos(deg_to_rad(20)),0),Vector3(0,0,20))
	else:solid(Vector3(100,1,100),Vector3(0,-.5,0))
	if name=="stairs":
		for step in 18:solid(Vector3(8,.2*(step+1),1),Vector3(0,.1*(step+1),step-9))
	elif name=="rubble":
		for index in 20:solid(Vector3(.7,.15+.08*(index%3),.6),Vector3((index%2-.5)*.9,.06,index*.8-8),Vector3(0,index*17,0))
	elif name=="corner":solid(Vector3(.2,4,40),Vector3(.9,2,0))
	elif name=="ledge":solid(Vector3(8,1,40),Vector3(0,1.5,0))
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);light.light_energy=1.4;light.shadow_enabled=true;stage.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65;stage.add_child(environment)
	camera=Camera3D.new();camera.fov=50;stage.add_child(camera);camera.current=true;camera.global_position=base+Vector3(20,14,24);camera.look_at(base+Vector3(0,1,0))
	await ticks(3)
	var count:=8 if name in ["pile","ground_pile"] else 4
	var poses:Array[String]=["Zombie_Idle","Zombie_Walk_Drag_Right","Zombie_Attack_Both","Zombie_Crawl"]
	for index in count:
		var point:=base+Vector3(3.65 if name=="ledge" else 0,0,(index-(count-1)*.5)*5.0)
		if name=="ground_pile":point=base+Vector3(cos(TAU*index/count)*1.2,0,sin(TAU*index/count)*1.2)
		var ray:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*30,point-Vector3.UP*30,7)
		var ground:Dictionary=stage.get_world_3d().direct_space_state.intersect_ray(ray)
		if name=="pile":point=base+Vector3((index%2-.5)*.55,index*1.8,(index%3-1)*.35)
		else:point=ground.position+Vector3.UP*.04
		var subject:=Zombie.new();subject.geometry_template=shared_geometry;subject.position=point;subject.rotation.y=index*.4;stage.add_child(subject);subject.set_behavior(false)
		check(subject.initialized,"stress zombie initialized: "+name)
		if not subject.initialized:continue
		if shared_geometry==null:shared_geometry=subject.anatomy
		subject.set_meta("stress_pose",poses[index%poses.size()]);subject.play_clip(poses[index%poses.size()]);subject.animation_player.pause();subject.animation_player.seek(.55,true);subject.skeleton.force_update_all_bone_transforms()
		if name=="severed":subject.sever_limb(["upper_arm_l","thigh_r","head","forearm_r"][index],Vector3(.3,.1,0))
		subject.die(Vector3(12,0,0) if name=="ledge" else Vector3(1,0,.5));subjects.append(subject)
	await ticks(2)
	for subject:Node3D in subjects:remember_constraints(subject)
	var linear_limit:=maxf(12.0,sqrt(2*float(ProjectSettings.get_setting("physics/3d/default_gravity"))*count*1.8)+4) if name=="pile" else 12.0
	var settled:=await phase(name+"_settle",12.0 if name in ["pile","ground_pile"] else 8.0,linear_limit)
	check(settled.sleeping==settled.bodies,"all supported pieces settle: "+name)
	var dead:=true
	for subject:Node3D in subjects:dead=dead and not subject.alive and subject.health==0 and not subject.animation_player.active and not subject.behavior_enabled and subject.capsule.disabled and subject.collision_layer==0
	check(dead,"dead zombies retain zero health and no animation/behavior motor: "+name)
	await picture(name+"-settled")
	for subject:Node3D in subjects:
		subject.anatomy.wake_ragdolls();subject.physical_bones.Spine2.apply_central_impulse(Vector3(10,2,-3))
	var pushed:=await phase(name+"_wake",4.0)
	var initial:Array[float]=[]
	for subject:Node3D in subjects:initial.append(subject.physical_bones.Hips.global_position.y)
	for support:StaticBody3D in supports:support.position.y-=.12
	var lowered:=await phase(name+"_lowered_support",2.0)
	var moved:=0
	for index in subjects.size():
		if initial[index]-subjects[index].physical_bones.Hips.global_position.y>.06:moved+=1
	check(moved==subjects.size(),"small support edits do not leave corpses floating: "+name)
	await picture(name+"-support-lowered")
	summary.append({"case":name,"hz":physics_hz,"settled":settled,"pushed":pushed,"lowered":lowered,"support_drop_moved":moved})
	stage.free();subjects.clear();await ticks(3)

func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ragdoll-evidence="):folder=argument.trim_prefix("--ragdoll-evidence=")
		if argument.begins_with("--stress-case="):cases.append(argument.trim_prefix("--stress-case="))
		if argument.begins_with("--stress-hz="):physics_hz=clampi(argument.trim_prefix("--stress-hz=").to_int(),30,120)
	folder=ProjectSettings.globalize_path(folder);DirAccess.make_dir_recursive_absolute(folder)
	Engine.physics_ticks_per_second=physics_hz
	if cases.is_empty():cases.assign(STRESS_CASES)
	for name in cases:
		if not name in STRESS_CASES:check(false,"unknown stress case: "+name);quit(1);return
	for name in cases:await run_case(name)
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"cases":summary,"scope":"Finite physical fixtures; instruments add observer cost, not an uninstrumented gameplay frame benchmark."},"  "))
	shared_geometry=null
	print("ZOMBIE_RAGDOLL_STRESS failures=",failures)
	quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends "res://tests/torch_hand_deformation.gd"
func run()->void:
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();root.add_child(tools)
	tools.set_process(false);tools.equip(6)
	var view:Node3D=tools.human;view.set_process(false);view.torch_effects.set_burning(false)
	check(view.swing_profile().is_empty(),"review candidate does not enable gameplay attacks")
	var library:AnimationLibrary=load("res://addons/characters/authoring/Human.torch_attack.res")
	view.animation_player.add_animation_library("attack_review",library)
	view.clips["FP_Torch_Swing"]="attack_review/FP_Torch_Swing"
	var animation:=library.get_animation("FP_Torch_Swing")
	check(library.get_animation_list().size()==1 and is_equal_approx(animation.length,1.1) and animation.loop_mode==Animation.LOOP_NONE,"one non-looping 1.1 second candidate")
	var only_pose:=true
	for track in animation.get_track_count():only_pose=only_pose and animation.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D,Animation.TYPE_BLEND_SHAPE]
	check(only_pose,"no damage, audio, methods or gameplay event tracks")
	var skeleton:Skeleton3D=view.model.find_children("*","Skeleton3D",true,false)[0]
	var torch_root:Node3D=view.torch_effects.get_parent()
	var skin:Skin=view.body_mesh.skin;var bindings:Array[int]=[]
	for index in skin.get_bind_count():
		var name:=String(skin.get_bind_name(index));bindings.append(skeleton.find_bone(name) if not name.is_empty() else skin.get_bind_bone(index))
	var vertices:Array[Dictionary]=[]
	for surface in view.body_mesh.mesh.get_surface_count():
		var arrays:Array=view.body_mesh.mesh.surface_get_arrays(surface)
		var width:int=arrays[Mesh.ARRAY_WEIGHTS].size()/arrays[Mesh.ARRAY_VERTEX].size()
		for vertex in arrays[Mesh.ARRAY_VERTEX].size():
			var indices:Array[int]=[];var weights:Array[float]=[];var hand_weight:=0.0;var strongest:=0.0;var label:=""
			for slot in width:
				var binding:int=arrays[Mesh.ARRAY_BONES][vertex*width+slot];var weight:float=arrays[Mesh.ARRAY_WEIGHTS][vertex*width+slot]
				indices.append(binding);weights.append(weight)
				var name:=String(skeleton.get_bone_name(bindings[binding]))
				if name.begins_with("RightHand"):
					hand_weight+=weight
					if weight>strongest:label=name;strongest=weight
			if hand_weight>.8:vertices.append({"point":arrays[Mesh.ARRAY_VERTEX][vertex],"bindings":indices,"weights":weights,"label":label})
	pose(view,"FP_Torch_Idle",0)
	var ready:Array[Transform3D]=[]
	for bone in skeleton.get_bone_count():ready.append(skeleton.get_bone_pose(bone))
	var max_wrist:=0.0;var max_step:=0.0;var clearance:=INF;var grip_error:=0.0;var seam:=0.0;var body_error:=0.0
	var previous:={};var closest:={};var grip:Transform3D;var maximum_joint:={}
	var frames:Array=[];var heads:Array[Vector3]=[]
	for frame in 133:
		pose(view,"FP_Torch_Swing",frame/120.0)
		skeleton.force_update_all_bone_transforms();torch_root.get_parent().on_skeleton_update()
		var inverse:Transform3D=(skeleton.global_transform.affine_inverse()*torch_root.global_transform).affine_inverse()
		var hand:=skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))
		var current_grip:=inverse*hand
		if frame==0:grip=current_grip
		grip_error=maxf(grip_error,difference(grip,current_grip))
		for side:String in ["Right","Left"]:
			var wrist:=skeleton.get_bone_global_pose(skeleton.find_bone(side+"Hand"));var elbow:=skeleton.get_bone_global_pose(skeleton.find_bone(side+"ForeArm"))
			max_wrist=maxf(max_wrist,rad_to_deg((wrist.origin-elbow.origin).angle_to(wrist.basis.y)))
			for part:String in ["Shoulder","Arm","ForeArm","Hand"]:
				var bone:=skeleton.find_bone(side+part);var q:=skeleton.get_bone_pose(bone).basis.get_rotation_quaternion()
				if previous.has(bone):
					var step:=rad_to_deg(previous[bone].angle_to(q))
					if step>max_step:maximum_joint={"frame":frame*.5,"bone":side+part,"degrees":step}
					max_step=maxf(max_step,step)
				previous[bone]=q
		for bone in skeleton.get_bone_count():
			var name:=String(skeleton.get_bone_name(bone))
			if frame in [0,132]:seam=maxf(seam,difference(ready[bone],skeleton.get_bone_pose(bone)))
			if not name.begins_with("Right") and name!="Weapon_Axe":body_error=maxf(body_error,difference(ready[bone],skeleton.get_bone_pose(bone)))
		var palette:Array[Transform3D]=[]
		for index in bindings.size():palette.append(skeleton.get_bone_global_pose(bindings[index])*skin.get_bind_pose(index))
		var frame_clearance:=INF
		for vertex in vertices:
			var point:=Vector3.ZERO
			for slot in vertex.bindings.size():point+=(palette[vertex.bindings[slot]]*vertex.point)*vertex.weights[slot]
			point=inverse*point
			if point.y<-.20 or point.y>.16:continue
			frame_clearance=minf(frame_clearance,shaft_clearance(point))
			closest[vertex.label]=minf(closest.get(vertex.label,INF),Vector2(point.x,point.z).length())
		clearance=minf(clearance,frame_clearance)
		var head:Vector3=skeleton.global_transform.affine_inverse()*torch_root.global_transform*Vector3(0,.376,0)
		heads.append(head);frames.append({"frame":frame*.5,"clearance":frame_clearance,"crown":var_to_str(head)})
	check(max_wrist<35,"wrists stay within 35 degrees at all 133 keys/half-keys")
	check(max_step<12,"arm joints remain continuous through the fast strike")
	check(clearance>-.0005,"CPU-skinned hand clears the curved handle within 0.5 mm tolerance")
	check(grip_error<.0001,"runtime hand attachment keeps the rigid fitted grip")
	var touching:=true
	for finger:String in ["Index","Middle","Ring","Pinky","Thumb"]:touching=touching and closest.get("RightHand"+finger+"3",INF)<.029
	check(touching,"all five fingertips remain close to the handle")
	check(seam<.0001,"first and last poses match the existing carry without a jump")
	check(body_error<.0001,"left hand, body and feet retain carry pose without root motion")
	check(heads[52].distance_to(heads[30])>.15,"crown has a distinct strike stroke between pullback and proposed contact")
	var report:={"checks":checks,"failures":failures,"sample_count":133,"hand_vertices":vertices.size(),"max_wrist_degrees":max_wrist,"max_joint_half_key_degrees":max_step,"minimum_clearance_m":clearance,"grip_error":grip_error,"endpoint_error":seam,"body_error":body_error,"finger_radii":closest,"frames":frames,"approval":"Player review pending; scoped engineering checks only"}
	DirAccess.make_dir_recursive_absolute("res://reports/torch_attack")
	FileAccess.open("res://reports/torch_attack/checks.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print("TORCH_ATTACK_CANDIDATE ",JSON.stringify(report.merged({"frames":[],"maximum_joint":maximum_joint},true)))
	tools.free();quit(1 if failures else 0)

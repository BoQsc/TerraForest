# SPDX-License-Identifier: 0BSD
extends "res://tests/torch_hand_deformation.gd"
func skin_point(vertex:Dictionary,palette:Array[Transform3D])->Vector3:
	var point:=Vector3.ZERO
	for slot in vertex.bindings.size():point+=(palette[vertex.bindings[slot]]*vertex.point)*vertex.weights[slot]
	return point
func run()->void:
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();root.add_child(tools)
	tools.set_process(false);tools.equip(6)
	var view:Node3D=tools.human;view.set_process(false);view.torch_effects.set_burning(false)
	check(view.swing_profile().is_empty(),"review candidate does not enable gameplay attacks")
	var baseline:=OS.get_cmdline_user_args().has("--rejected-baseline")
	var library:AnimationLibrary=load("res://reports/torch_attack/rejected01.res" if baseline else "res://addons/characters/authoring/Human.torch_attack.res")
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
	var vertices:Array[Dictionary]=[];var shoulder_vertices:Array[Dictionary]=[];var shoulder_triangles:Array=[]
	for surface in view.body_mesh.mesh.get_surface_count():
		var arrays:Array=view.body_mesh.mesh.surface_get_arrays(surface)
		var width:int=arrays[Mesh.ARRAY_WEIGHTS].size()/arrays[Mesh.ARRAY_VERTEX].size()
		var surface_vertices:Array[Dictionary]=[];var shoulder_weights:Array[float]=[]
		for vertex in arrays[Mesh.ARRAY_VERTEX].size():
			var indices:Array[int]=[];var weights:Array[float]=[];var hand_weight:=0.0;var strongest:=0.0;var label:="";var shoulder_weight:=0.0
			for slot in width:
				var binding:int=arrays[Mesh.ARRAY_BONES][vertex*width+slot];var weight:float=arrays[Mesh.ARRAY_WEIGHTS][vertex*width+slot]
				indices.append(binding);weights.append(weight)
				var name:=String(skeleton.get_bone_name(bindings[binding]))
				if name in ["RightArm","RightShoulder"]:shoulder_weight+=weight
				if name.begins_with("RightHand"):
					hand_weight+=weight
					if weight>strongest:label=name;strongest=weight
			if hand_weight>.8:vertices.append({"point":arrays[Mesh.ARRAY_VERTEX][vertex],"bindings":indices,"weights":weights,"label":label})
			surface_vertices.append({"point":arrays[Mesh.ARRAY_VERTEX][vertex],"bindings":indices,"weights":weights})
			shoulder_weights.append(shoulder_weight)
		var remap:={};var mesh_indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for triangle in mesh_indices.size()/3:
			var corners:=[mesh_indices[triangle*3],mesh_indices[triangle*3+1],mesh_indices[triangle*3+2]]
			if maxf(shoulder_weights[corners[0]],maxf(shoulder_weights[corners[1]],shoulder_weights[corners[2]]))<.1:continue
			var mapped:Array[int]=[]
			for corner:int in corners:
				if not remap.has(corner):remap[corner]=shoulder_vertices.size();shoulder_vertices.append(surface_vertices[corner])
				mapped.append(remap[corner])
			shoulder_triangles.append(mapped)
	pose(view,"FP_Torch_Idle",0)
	var ready:Array[Transform3D]=[]
	for bone in skeleton.get_bone_count():ready.append(skeleton.get_bone_pose(bone))
	var ready_global:Array[Transform3D]=[]
	for bone in skeleton.get_bone_count():ready_global.append(skeleton.get_bone_global_pose(bone))
	var reference_palette:Array[Transform3D]=[]
	for index in bindings.size():reference_palette.append(skeleton.get_bone_global_pose(bindings[index])*skin.get_bind_pose(index))
	var reference_points:Array[Vector3]=[]
	for vertex in shoulder_vertices:reference_points.append(skin_point(vertex,reference_palette))
	var max_wrist:=0.0;var max_step:=0.0;var clearance:=INF;var grip_error:=0.0;var seam:=0.0;var body_error:=0.0
	var minimum_elbow_drop:=INF;var maximum_arm_turn:=0.0;var torso_turn:=0.0;var free_hand_motion:=0.0
	var minimum_triangle_area:=INF;var maximum_edge_stretch:=0.0;var minimum_edge_ratio:=INF
	var previous:={};var closest:={};var grip:Transform3D;var maximum_joint:={}
	var frames:Array=[];var heads:Array[Vector3]=[]
	for frame in 133:
		pose(view,"FP_Torch_Swing",frame/120.0)
		skeleton.force_update_all_bone_transforms();torch_root.get_parent().on_skeleton_update()
		var inverse:Transform3D=(skeleton.global_transform.affine_inverse()*torch_root.global_transform).affine_inverse()
		var hand:=skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))
		var upper:=skeleton.get_bone_global_pose(skeleton.find_bone("RightArm"))
		var elbow_pose:=skeleton.get_bone_global_pose(skeleton.find_bone("RightForeArm"))
		minimum_elbow_drop=minf(minimum_elbow_drop,upper.origin.y-elbow_pose.origin.y)
		maximum_arm_turn=maxf(maximum_arm_turn,rad_to_deg(upper.basis.get_rotation_quaternion().angle_to(ready_global[skeleton.find_bone("RightArm")].basis.get_rotation_quaternion())))
		var torso:=skeleton.get_bone_global_pose(skeleton.find_bone("Spine2"))
		torso_turn=maxf(torso_turn,rad_to_deg(torso.basis.get_rotation_quaternion().angle_to(ready_global[skeleton.find_bone("Spine2")].basis.get_rotation_quaternion())))
		free_hand_motion=maxf(free_hand_motion,skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).origin.distance_to(ready_global[skeleton.find_bone("LeftHand")].origin))
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
			if name in ["Root","Hips"] or "Leg" in name or "Foot" in name or "Toe" in name:body_error=maxf(body_error,difference(ready[bone],skeleton.get_bone_pose(bone)))
		var palette:Array[Transform3D]=[]
		for index in bindings.size():palette.append(skeleton.get_bone_global_pose(bindings[index])*skin.get_bind_pose(index))
		var shoulder_points:Array[Vector3]=[]
		for vertex in shoulder_vertices:shoulder_points.append(skin_point(vertex,palette))
		for triangle:Array in shoulder_triangles:
			var a:Vector3=reference_points[triangle[0]];var b:Vector3=reference_points[triangle[1]];var c:Vector3=reference_points[triangle[2]]
			var x:Vector3=shoulder_points[triangle[0]];var y:Vector3=shoulder_points[triangle[1]];var z:Vector3=shoulder_points[triangle[2]]
			var area:float=(b-a).cross(c-a).length()
			if area<.000001:continue
			minimum_triangle_area=minf(minimum_triangle_area,(y-x).cross(z-x).length()/area)
			for pair in [[a,b,x,y],[b,c,y,z],[c,a,z,x]]:
				var edge:float=pair[0].distance_to(pair[1])
				if edge<.001:continue
				var ratio:float=pair[2].distance_to(pair[3])/edge
				maximum_edge_stretch=maxf(maximum_edge_stretch,ratio);minimum_edge_ratio=minf(minimum_edge_ratio,ratio)
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
	check(body_error<.0001,"hips, feet and root retain carry pose without root motion")
	check(heads[52].distance_to(heads[30])>.15,"crown has a distinct strike stroke between pullback and proposed contact")
	check(minimum_elbow_drop>.06 and maximum_arm_turn<65,"elbow stays below the shoulder and upper arm avoids the rejected high roll")
	check(minimum_triangle_area>.25 and minimum_edge_ratio>.45 and maximum_edge_stretch<1.75,"actual skinned shoulder/sleeve triangles avoid severe collapse and stretch")
	check(torso_turn>3 and torso_turn<10 and free_hand_motion>.01 and free_hand_motion<.09,"bounded torso and free-hand follow-through supports the strike")
	var contact_speed:=INF
	for sample in range(49,55):contact_speed=minf(contact_speed,heads[sample].distance_to(heads[sample-1])*120)
	check(contact_speed>1.5,"torch carries at least 1.5 m/s through the contact neighborhood")
	var report:={"checks":checks,"failures":failures,"sample_count":133,"hand_vertices":vertices.size(),"max_wrist_degrees":max_wrist,"max_joint_half_key_degrees":max_step,"minimum_clearance_m":clearance,"grip_error":grip_error,"endpoint_error":seam,"body_error":body_error,"finger_radii":closest,"frames":frames,"approval":"Player review pending; scoped engineering checks only"}
	report.merge({"minimum_contact_speed_m_s":contact_speed,"minimum_elbow_drop_m":minimum_elbow_drop,"maximum_upper_arm_turn_degrees":maximum_arm_turn,"torso_turn_degrees":torso_turn,"free_hand_motion_m":free_hand_motion,"shoulder_triangles":shoulder_triangles.size(),"minimum_shoulder_triangle_area_ratio":minimum_triangle_area,"minimum_shoulder_edge_ratio":minimum_edge_ratio,"maximum_shoulder_edge_ratio":maximum_edge_stretch,"rejected_baseline":baseline})
	DirAccess.make_dir_recursive_absolute("res://reports/torch_attack")
	FileAccess.open("res://reports/torch_attack/"+("rejected01-checks.json" if baseline else "checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print("TORCH_ATTACK_CANDIDATE ",JSON.stringify(report.merged({"frames":[],"maximum_joint":maximum_joint},true)))
	tools.free();quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends "res://tests/pickaxe_side_strike.gd"
const BUCKET_LIBRARY=preload("res://addons/characters/runtime/assets/Human.bucket.res")
func run()->void:
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();root.add_child(tools);tools.set_process(false)
	var view:Node3D=tools.human;view.set_process(false)
	tools.equip(401,0)
	check(view.current==401 and view.active_clip=="FP_Bucket_Idle" and not tools.tools.has(401),"bucket uses the character rig and no floating procedural preview")
	check(view.body_mesh.mesh==view.unarmed_body_mesh,"bucket uses the repaired finger weights")
	check(not view.bucket_water.visible and view.bucket_fill==0,"empty bucket has no water surface")
	tools.equip(401,1000000)
	check(view.bucket_water.visible and is_equal_approx(view.bucket_fill,1),"current item 401 water metadata displays the full surface")
	tools.equip(401,250000)
	check(view.bucket_water.visible and is_equal_approx(view.bucket_fill,.25),"older partial metadata displays its fill level")
	tools.equip(411)
	check(view.current==401 and view.bucket_fill==1,"legacy filled item IDs still normalize to the same visual")
	var bucket:MeshInstance3D=view.model.find_child("Equipment_Bucket",true,false)
	var bail:MeshInstance3D=view.model.find_child("Equipment_Bucket_Bail",true,false)
	var triangles:=0;var pbr:=false;var valid_uvs:=true
	for part:MeshInstance3D in [bucket,bail]:
		for surface in part.mesh.get_surface_count():
			triangles+=part.mesh.surface_get_array_index_len(surface)/3
			var material:StandardMaterial3D=part.mesh.surface_get_material(surface)
			if material.metallic>.8 and material.albedo_texture!=null and material.roughness_texture!=null and material.normal_enabled and material.normal_texture!=null:pbr=true
			var arrays:=part.mesh.surface_get_arrays(surface);valid_uvs=valid_uvs and arrays[Mesh.ARRAY_TEX_UV].size()==arrays[Mesh.ARRAY_VERTEX].size()
	check(triangles>=15000 and pbr and valid_uvs,"dense hollow bucket has UVs and embedded metal base-color/roughness/normal maps")
	check(preload("res://addons/volumetric_water/bucket_model.gd").mesh().get_surface_count()==bucket.mesh.get_surface_count()+bail.mesh.get_surface_count(),"world pickup combines both articulated parts")
	var skeleton:Skeleton3D=view.model.find_child("Skeleton3D",true,false)
	var weapon:=skeleton.find_bone("Weapon_Axe");var hand:=skeleton.find_bone("RightHand")
	var pail_bone:=skeleton.find_bone("Weapon_Pickaxe");var left_hand:=skeleton.find_bone("LeftHand")
	pose(view,"FP_Bucket_Idle",0)
	var grip:=skeleton.get_bone_global_pose(weapon).affine_inverse()*skeleton.get_bone_global_pose(hand)
	var root_index:=skeleton.find_bone("Root");var root_pose:=skeleton.get_bone_global_pose(root_index)
	var finger_poses:={}
	for index in skeleton.get_bone_count():
		if "RightHand" in skeleton.get_bone_name(index) and index!=hand:finger_poses[index]=skeleton.get_bone_pose(index)
	var records:={}
	for clip:StringName in BUCKET_LIBRARY.get_animation_list():
		var animation:Animation=BUCKET_LIBRARY.get_animation(clip)
		var grip_error:=0.0;var root_error:=0.0;var fingers_error:=0.0;var seam_error:=0.0;var event_free:=true
		var hinge_error:=0.0;var support_error:=0.0;var support_angle:=0.0;var wrist_bend:=0.0;var forearm_clear:=true
		var support:=Transform3D.IDENTITY;var support_found:=false
		for track in animation.get_track_count():event_free=event_free and animation.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D,Animation.TYPE_BLEND_SHAPE]
		var count:=roundi(animation.length*60)
		var first:Array[Transform3D]=[]
		for frame in count*2+1:
			var time:=frame/120.0
			pose(view,String(clip),time)
			var tool:=skeleton.get_bone_global_pose(weapon)
			var pail:=skeleton.get_bone_global_pose(pail_bone)
			var tool_model:=tool*skeleton.get_bone_global_rest(weapon).affine_inverse()
			var pail_model:=pail*skeleton.get_bone_global_rest(pail_bone).affine_inverse()
			for sign:float in [-1.0,1.0]:
				var ear:=Vector3(sign*.153,-.22,0)
				hinge_error=maxf(hinge_error,(tool_model*ear-pail_model*ear).length())
			var supported:bool=(String(clip).ends_with("Pour") and time>=.55 and time<=2.08) or (String(clip).ends_with("Scoop") and time>=.6 and time<=1.65)
			if supported:
				var contact:=pail.affine_inverse()*skeleton.get_bone_global_pose(left_hand)
				if not support_found:support=contact;support_found=true
				support_error=maxf(support_error,(support.origin-contact.origin).length())
				support_angle=maxf(support_angle,support.basis.get_rotation_quaternion().angle_to(contact.basis.get_rotation_quaternion()))
			for side:String in ["Left","Right"]:
				var wrist:=skeleton.get_bone_global_pose(skeleton.find_bone(side+"Hand"))
				var elbow:=skeleton.get_bone_global_pose(skeleton.find_bone(side+"ForeArm"))
				wrist_bend=maxf(wrist_bend,rad_to_deg((wrist.origin-elbow.origin).angle_to(wrist.basis.y)))
				for step in 21:
					var point:=pail_model.affine_inverse()*elbow.origin.lerp(wrist.origin,step/20.0)
					var radius:=.11+.15*(point.y+.437)+.025
					if point.y>-.437 and point.y<-.204 and Vector2(point.x,point.z).length()<radius:forearm_clear=false
			grip_error=maxf(grip_error,difference(grip,tool.affine_inverse()*skeleton.get_bone_global_pose(hand)))
			root_error=maxf(root_error,difference(root_pose,skeleton.get_bone_global_pose(root_index)))
			for index:int in finger_poses:fingers_error=maxf(fingers_error,difference(finger_poses[index],skeleton.get_bone_pose(index)))
			for index in skeleton.get_bone_count():
				if frame==0:first.append(skeleton.get_bone_pose(index))
				if frame==count*2:seam_error=maxf(seam_error,difference(first[index],skeleton.get_bone_pose(index)))
		check(grip_error<.0005 and fingers_error<.0001,String(clip)+" preserves closed grip through keys and interpolation")
		check(root_error<.0001 and event_free,String(clip)+" is presentation only, without root motion or gameplay events")
		check(seam_error<.0001,String(clip)+" returns cleanly to its starting pose")
		check(hinge_error<.0005,String(clip)+" keeps both bail ears attached through rotation")
		check(support_error<.0005 and support_angle<.002 and wrist_bend<50,String(clip)+" holds the supporting palm without a reversed wrist")
		check(forearm_clear,String(clip)+" keeps forearm centres and a 25 mm clearance outside the pail volume")
		records[clip]={"grip_error":grip_error,"finger_error":fingers_error,"root_error":root_error,"seam_error":seam_error,"hinge_error":hinge_error,"support_error_m":support_error,"support_angle_radians":support_angle,"wrist_bend_degrees":wrist_bend,"forearm_clear":forearm_clear}
	# Bone-centre clearance alone misses fingertips through the floor. Skin the
	# actual runtime support hand, including its repaired finger weights.
	var skin:Skin=view.body_mesh.skin
	var bindings:Array[int]=[]
	for index in skin.get_bind_count():
		var name:=String(skin.get_bind_name(index))
		bindings.append(skeleton.find_bone(name) if not name.is_empty() else skin.get_bind_bone(index))
	var vertices:Array[Dictionary]=[]
	for surface in view.body_mesh.mesh.get_surface_count():
		var arrays:Array=view.body_mesh.mesh.surface_get_arrays(surface)
		var width:int=arrays[Mesh.ARRAY_WEIGHTS].size()/arrays[Mesh.ARRAY_VERTEX].size()
		for vertex in arrays[Mesh.ARRAY_VERTEX].size():
			var indices:Array[int]=[];var weights:Array[float]=[];var hand_weight:=0.0
			for slot in width:
				var binding:int=arrays[Mesh.ARRAY_BONES][vertex*width+slot]
				var weight:float=arrays[Mesh.ARRAY_WEIGHTS][vertex*width+slot]
				indices.append(binding);weights.append(weight)
				if String(skeleton.get_bone_name(bindings[binding])).begins_with("LeftHand"):hand_weight+=weight
			if hand_weight>.8:vertices.append({"point":arrays[Mesh.ARRAY_VERTEX][vertex],"bindings":indices,"weights":weights})
	for entry in [["Pour",.8],["Pour",1.208333333],["Pour",1.9],["Scoop",.9],["Scoop",1.308333333]]:
		pose(view,"FP_Bucket_"+entry[0],entry[1])
		var palette:Array[Transform3D]=[]
		for index in bindings.size():palette.append(skeleton.get_bone_global_pose(bindings[index])*skin.get_bind_pose(index))
		var inverse:Transform3D=(skeleton.get_bone_global_pose(pail_bone)*skeleton.get_bone_global_rest(pail_bone).affine_inverse()).affine_inverse()
		var hand_clear:=true;var contact_height:=-INF
		for vertex in vertices:
			var point:=Vector3.ZERO
			for slot in vertex.bindings.size():point+=(palette[vertex.bindings[slot]]*vertex.point)*vertex.weights[slot]
			point=inverse*point
			var radial:=Vector2(point.x,point.z).length()
			if radial<.108:contact_height=maxf(contact_height,point.y)
			if point.y>-.435 and point.y<-.204 and radial<.11+.15*(point.y+.437):hand_clear=false
		check(vertices.size()>100 and hand_clear and contact_height>-.447,"%s %.3f keeps the actual supporting skin underneath and against the floor"%entry)
	tools.equip(401,0)
	check(tools.attack_profile().is_empty() and not tools.begin_attack(101) and tools.attack_identity==0,"bucket use cannot start a combat attack or leave a pending contact")
	check(tools.swing() and view.active_clip=="FP_Bucket_Pour","completed emptying selects the authored pour")
	check(view.bucket_fill==0 and view.bucket_display_fill==1 and view.bucket_water.visible,"confirmed empty inventory retains water visually until tipping")
	for frame in 72:view._process(1.0/60.0)
	check(view.action_remaining>1.0 and view.bucket_display_fill==0 and not view.bucket_water.visible,"pour reaches the empty tipped hold before recovering")
	for frame in 102:view._process(1.0/60.0)
	check(view.active_clip=="FP_Bucket_Idle" and view.action_remaining==0,"pour recovers to carry pose")
	tools.equip(401,1000000)
	check(tools.swing() and view.active_clip=="FP_Bucket_Scoop","completed filling selects the authored scoop")
	check(view.bucket_fill==1 and not view.bucket_water.visible,"confirmed full inventory keeps the dipping pail visually empty")
	for frame in 117:view._process(1.0/60.0)
	check(view.bucket_water.visible and view.bucket_display_fill==1 and view.action_remaining>0,"water appears during the lift before scoop recovery")
	tools.equip(1)
	check(view.active_clip=="FP_Pickaxe_Fresh_Idle" and view.body_mesh.mesh==view.original_body_mesh and not bucket.visible and not view.bucket_water.visible,"switching restores the accepted pickaxe and hides every bucket surface")
	tools.equip(401,1000000);tools.place()
	check(not bucket.visible and not view.bucket_water.visible,"placement hides bucket and water together")
	view._process(3)
	check(bucket.visible and view.bucket_water.visible,"placement recovery restores bucket presentation")
	var body:=CharacterBody3D.new();root.add_child(body);view.body=body
	for entry in [[5.5,"Walk"],[9.9,"Run"],[0.0,"Idle"]]:
		body.velocity=Vector3(0,0,entry[0]);view._process(.12)
		check(view.active_clip=="FP_Bucket_"+entry[1],"actual velocity selects bucket "+entry[1])
	DirAccess.make_dir_recursive_absolute("res://reports/water_bucket_visuals")
	FileAccess.open("res://reports/water_bucket_visuals/runtime.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"triangles":triangles,"clips":records,"scope":"Visual assets, attachment, fill state and presentation routing; water transfers verified separately."},"  "))
	tools.free();body.free();print("WATER_BUCKET_VISUALS checks=",checks," failures=",failures);quit(1 if failures else 0)

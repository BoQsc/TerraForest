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
	var triangles:=0;var pbr:=false;var valid_uvs:=true
	for surface in bucket.mesh.get_surface_count():
		triangles+=bucket.mesh.surface_get_array_index_len(surface)/3
		var material:StandardMaterial3D=bucket.mesh.surface_get_material(surface)
		if material.metallic>.8 and material.albedo_texture!=null and material.roughness_texture!=null and material.normal_enabled and material.normal_texture!=null:pbr=true
		var arrays:=bucket.mesh.surface_get_arrays(surface);valid_uvs=valid_uvs and arrays[Mesh.ARRAY_TEX_UV].size()==arrays[Mesh.ARRAY_VERTEX].size()
	check(triangles>=15000 and pbr and valid_uvs,"dense hollow bucket has UVs and embedded metal base-color/roughness/normal maps")
	check(preload("res://addons/volumetric_water/bucket_model.gd").mesh().get_surface_count()==bucket.mesh.get_surface_count(),"world pickup shares the complete bucket materials and geometry")
	var skeleton:Skeleton3D=view.model.find_child("Skeleton3D",true,false)
	var weapon:=skeleton.find_bone("Weapon_Axe");var hand:=skeleton.find_bone("RightHand")
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
		for track in animation.get_track_count():event_free=event_free and animation.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D,Animation.TYPE_BLEND_SHAPE]
		var count:=roundi(animation.length*60)
		var first:Array[Transform3D]=[]
		for frame in count*2+1:
			pose(view,String(clip),frame/120.0)
			var tool:=skeleton.get_bone_global_pose(weapon)
			grip_error=maxf(grip_error,difference(grip,tool.affine_inverse()*skeleton.get_bone_global_pose(hand)))
			root_error=maxf(root_error,difference(root_pose,skeleton.get_bone_global_pose(root_index)))
			for index:int in finger_poses:fingers_error=maxf(fingers_error,difference(finger_poses[index],skeleton.get_bone_pose(index)))
			for index in skeleton.get_bone_count():
				if frame==0:first.append(skeleton.get_bone_pose(index))
				if frame==count*2:seam_error=maxf(seam_error,difference(first[index],skeleton.get_bone_pose(index)))
		check(grip_error<.0005 and fingers_error<.0001,String(clip)+" preserves closed grip through keys and interpolation")
		check(root_error<.0001 and event_free,String(clip)+" is presentation only, without root motion or gameplay events")
		check(seam_error<.0001,String(clip)+" returns cleanly to its starting pose")
		records[clip]={"grip_error":grip_error,"finger_error":fingers_error,"root_error":root_error,"seam_error":seam_error}
	tools.equip(401,0)
	check(tools.attack_profile().is_empty() and not tools.begin_attack(101) and tools.attack_identity==0,"bucket use cannot start a combat attack or leave a pending contact")
	check(tools.swing() and view.active_clip=="FP_Bucket_Pour","completed emptying selects the authored pour")
	view._process(1.3)
	check(view.active_clip=="FP_Bucket_Idle" and view.action_remaining==0,"pour recovers to carry pose")
	tools.equip(401,1000000)
	check(tools.swing() and view.active_clip=="FP_Bucket_Scoop","completed filling selects the authored scoop")
	view._process(.1);tools.equip(1)
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

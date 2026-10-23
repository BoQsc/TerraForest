# SPDX-License-Identifier: 0BSD
extends "res://tests/pickaxe_diagonal.gd"

func transform_error(a:Transform3D,b:Transform3D)->float:
	var result:float=(a.origin-b.origin).length()
	for axis in 3:result=maxf(result,(a.basis[axis]-b.basis[axis]).length())
	return result

func run()->void:
	var stage:=Node3D.new();root.add_child(stage)
	var camera:=Camera3D.new();camera.fov=75;camera.position=Vector3(0,1.68,0);stage.add_child(camera)
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();camera.add_child(tools)
	tools.equip(1);tools.set_process(false)
	var view:Node3D=tools.human;view.set_process(false)
	check(view.active_clip=="FP_Pickaxe_Diagonal_Idle" and view.clips.size()==77,"normal controller still uses kept v4; review copy is not loaded by default")
	var library:=preload("res://addons/characters/runtime/assets/Human.pickaxe_left_follow.res")
	view.animation_player.add_animation_library("left_follow",library)
	for name in library.get_animation_list():view.clips[String(name)]="left_follow/"+String(name)
	check(library.get_animation_list().size()==1 and view.clips.size()==78,"separate library contains only the new swing beside all kept actions")
	var animation:Animation=library.get_animation("FP_Pickaxe_LeftFollow_Swing")
	check(is_equal_approx(animation.length,1.2) and animation.loop_mode==Animation.LOOP_NONE,"copy retains the 1.2-second one-shot duration")
	var animation_only:=true
	for track in animation.get_track_count():animation_only=animation_only and animation.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D,Animation.TYPE_BLEND_SHAPE]
	check(animation_only,"copy adds no gameplay, audio or method events")
	var skeleton:Skeleton3D=view.model.find_child("Skeleton3D",true,false)
	var pick:MeshInstance3D=view.model.find_child("Equipment_Pickaxe",true,false)
	var weapon:=skeleton.find_bone("Weapon_Pickaxe")
	var left:=skeleton.find_bone("LeftHand");var right:=skeleton.find_bone("RightHand")
	var root_index:=skeleton.find_bone("Root")
	var preserved_error:=0.0
	# Compare the imported animations, including every original finger/body key.
	for frame in 33:
		pose(view,"FP_Pickaxe_Diagonal_Swing",float(frame)/60)
		var kept:Array[Transform3D]=[]
		for index in skeleton.get_bone_count():kept.append(skeleton.get_bone_pose(index))
		pose(view,"FP_Pickaxe_LeftFollow_Swing",float(frame)/60)
		for index in skeleton.get_bone_count():preserved_error=maxf(preserved_error,transform_error(kept[index],skeleton.get_bone_pose(index)))
	check(preserved_error<.0001,"all 59 bone poses through forward contact match the kept animation")
	pose(view,"FP_Pickaxe_Diagonal_Idle",0)
	var ready:Array[Transform3D]=[]
	for index in skeleton.get_bone_count():ready.append(skeleton.get_bone_pose(index))
	var root_pose:Transform3D=skeleton.get_bone_global_pose(root_index)
	var left_grip:Transform3D=skeleton.get_bone_global_pose(weapon).affine_inverse()*skeleton.get_bone_global_pose(left)
	var right_grip:Transform3D=skeleton.get_bone_global_pose(weapon).affine_inverse()*skeleton.get_bone_global_pose(right)
	var root_error:=0.0;var grip_error:=0.0;var seam_error:=0.0
	var tool_basis:Basis;var body_reference:={};var tool_error:=0.0;var body_error:=0.0
	var contact:=Vector3.ZERO;var finish:=Vector3.ZERO;var previous_x:=INF;var continues_left:=true;var stays_forward:=true
	var camera_inverse:=camera.global_transform.affine_inverse()
	for frame in 73:
		pose(view,"FP_Pickaxe_LeftFollow_Swing",float(frame)/60)
		var tool:Transform3D=skeleton.get_bone_global_pose(weapon)
		root_error=maxf(root_error,transform_error(root_pose,skeleton.get_bone_global_pose(root_index)))
		grip_error=maxf(grip_error,transform_error(left_grip,tool.affine_inverse()*skeleton.get_bone_global_pose(left)))
		grip_error=maxf(grip_error,transform_error(right_grip,tool.affine_inverse()*skeleton.get_bone_global_pose(right)))
		var point:Vector3=camera_inverse*tool_head(pick,skeleton,true)
		if frame==32:
			contact=point;tool_basis=tool.basis
			for name in ["Root","Spine","Spine1","Spine2"]:body_reference[name]=skeleton.get_bone_global_pose(skeleton.find_bone(name))
		if frame>=32 and frame<=48:
			continues_left=continues_left and point.x<=previous_x+.0001;previous_x=point.x
			stays_forward=stays_forward and -point.z>.90 and point.z-contact.z<.08
			for axis in 3:tool_error=maxf(tool_error,(tool.basis[axis]-tool_basis[axis]).length())
			for name in body_reference:body_error=maxf(body_error,transform_error(body_reference[name],skeleton.get_bone_global_pose(skeleton.find_bone(name))))
		if frame==48:finish=point
		if frame in [0,20,32,40,48,60,72]:rows.append({"frame":frame,"working_point_camera":[point.x,point.y,point.z]})
		if frame in [0,72]:
			for index in skeleton.get_bone_count():seam_error=maxf(seam_error,transform_error(ready[index],skeleton.get_bone_pose(index)))
	check(root_error<.0001,"animation leaves root in place for the full action")
	check(grip_error<.0001,"both fitted hands remain attached to the handle throughout continuation and recovery")
	check(tool_error<.0001 and body_error<.0001,"imported tool and torso orientations remain fixed from contact through left follow-through")
	check(continues_left and contact.x>.1 and finish.x<-.1 and contact.x-finish.x>.3,"evaluated cutting point continues from right of aim to left of aim")
	check(stays_forward and contact.y-finish.y>.05 and contact.y-finish.y<.15,"left continuation stays forward and descends without pulling the pick close to the camera")
	check(seam_error<.0001,"first and final poses exactly match the kept ready hold")
	view._play("FP_Pickaxe_LeftFollow_Swing",true)
	var remaining:float=view.action_remaining;view.swing()
	check(is_equal_approx(remaining,view.action_remaining),"an unfinished review swing cannot be restarted by held input")
	view._process(1.3)
	check(view.active_clip=="FP_Pickaxe_Diagonal_Idle" and view.action_remaining==0,"review swing returns to kept idle after the action")
	view.swing()
	check(view.active_clip=="FP_Pickaxe_Diagonal_Swing","normal gameplay selection still selects the kept swing")
	var folder:="res://reports/pickaxe_left_follow";DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"approval":"PENDING USER VISUAL REVIEW; do not commit","checks":checks,"failures":failures,"preserved_pose_error":preserved_error,"grip_error":grip_error,"root_error":root_error,"tool_basis_error":tool_error,"body_error":body_error,"seam_error":seam_error,"samples":rows,"scope":"Actual runtime rig, evaluated cutting-point mesh and view controller in an isolated camera fixture. No changes to world collision, damage, mining or default animation selection; no world/performance claims."},"  "))
	stage.free();print("PICKAXE_LEFT_FOLLOW checks=",checks," failures=",failures);quit(1 if failures else 0)

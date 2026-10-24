# SPDX-License-Identifier: 0BSD
extends "res://tests/pickaxe_diagonal.gd"

func difference(a:Transform3D,b:Transform3D)->float:
	var value:float=(a.origin-b.origin).length()
	for axis in 3:value=maxf(value,(a.basis[axis]-b.basis[axis]).length())
	return value

func run()->void:
	var stage:=Node3D.new();root.add_child(stage)
	var camera:=Camera3D.new();camera.fov=75;camera.position=Vector3(0,1.68,0);stage.add_child(camera)
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();camera.add_child(tools)
	tools.equip(1);tools.set_process(false)
	var view:Node3D=tools.human;view.set_process(false)
	view.pickaxe_swing="pullback";view.equip(1)
	check(view.active_clip=="FP_Pickaxe_Diagonal_Idle" and view.clips.has("FP_Pickaxe_Fresh_Swing"),"explicit pullback alternate retains diagonal holds beside the new default")
	var library:=preload("res://addons/characters/runtime/assets/Human.pickaxe_side_strike.res")
	view.animation_player.add_animation_library("side_strike",library)
	for name in library.get_animation_list():view.clips[String(name)]="side_strike/"+String(name)
	var animation:Animation=library.get_animation("FP_Pickaxe_SideStrike_Swing")
	check(library.get_animation_list().size()==1 and is_equal_approx(animation.length,1.2) and animation.loop_mode==Animation.LOOP_NONE,"separate library adds one 1.2-second swing")
	var animation_only:=true
	for track in animation.get_track_count():animation_only=animation_only and animation.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D,Animation.TYPE_BLEND_SHAPE]
	check(animation_only,"no method, gameplay, audio or damage events are added")
	var skeleton:Skeleton3D=view.model.find_child("Skeleton3D",true,false)
	var pick:MeshInstance3D=view.model.find_child("Equipment_Pickaxe",true,false)
	var weapon:=skeleton.find_bone("Weapon_Pickaxe")
	var left:=skeleton.find_bone("LeftHand");var right:=skeleton.find_bone("RightHand")
	pose(view,"FP_Pickaxe_Diagonal_Idle",0)
	var ready:Array[Transform3D]=[]
	for index in skeleton.get_bone_count():ready.append(skeleton.get_bone_pose(index))
	var left_grip:Transform3D=skeleton.get_bone_global_pose(weapon).affine_inverse()*skeleton.get_bone_global_pose(left)
	var right_grip:Transform3D=skeleton.get_bone_global_pose(weapon).affine_inverse()*skeleton.get_bone_global_pose(right)
	var body_reference:={}
	for name in ["Root","Spine","Spine1","Spine2"]:body_reference[name]=skeleton.get_bone_global_pose(skeleton.find_bone(name))
	var camera_inverse:=camera.global_transform.affine_inverse()
	var ready_head:Vector3=camera_inverse*tool_head(pick,skeleton)
	var body_error:=0.0;var grip_error:=0.0;var seam_error:=0.0
	var points:={};var heads:={};var angled_right:=true;var forward:=true;var previous_depth:=-INF;var highest_tip:=-INF
	for frame in 73:
		pose(view,"FP_Pickaxe_SideStrike_Swing",float(frame)/60)
		var tool:Transform3D=skeleton.get_bone_global_pose(weapon)
		for name in body_reference:body_error=maxf(body_error,difference(body_reference[name],skeleton.get_bone_global_pose(skeleton.find_bone(name))))
		grip_error=maxf(grip_error,difference(left_grip,tool.affine_inverse()*skeleton.get_bone_global_pose(left)))
		grip_error=maxf(grip_error,difference(right_grip,tool.affine_inverse()*skeleton.get_bone_global_pose(right)))
		var point:Vector3=camera_inverse*tool_head(pick,skeleton,true)
		var head:Vector3=camera_inverse*tool_head(pick,skeleton)
		var pivot:Vector3=camera_inverse*skeleton.global_transform*tool.origin
		var lean:=rad_to_deg(atan2(head.x-pivot.x,head.y-pivot.y))
		if frame>=20 and frame<=38:
			angled_right=angled_right and lean>25 and lean<75
			forward=forward and -point.z>=previous_depth-.002;previous_depth=-point.z
			highest_tip=maxf(highest_tip,point.y)
		if frame in [0,20,26,32,38,44,56,72]:
			points[frame]=point;heads[frame]=head
			rows.append({"frame":frame,"working_point_camera":[point.x,point.y,point.z],"head_camera":[head.x,head.y,head.z],"right_shaft_lean_degrees":lean})
		if frame in [0,72]:
			for index in skeleton.get_bone_count():seam_error=maxf(seam_error,difference(ready[index],skeleton.get_bone_pose(index)))
	check(body_error<.0001,"root and torso remain at the preserved neutral pose for the whole action")
	check(grip_error<.0001,"both hands stay attached at their preserved handle stations")
	check(seam_error<.0001,"first and final poses match all 59 bones of the preserved ready grip")
	var chamber:Vector3=points[20];var contact:Vector3=points[32];var finish:Vector3=points[38]
	check(heads[20].y<ready_head.y-.1 and chamber.x>.4 and chamber.y<=contact.y+.03 and highest_tip<contact.y+.04,"wind-up is lower on the right and approaches at target height, without an overhead chop")
	check(forward and chamber.z-contact.z>.25 and chamber.x-contact.x>.3 and absf(contact.y)<.06 and -contact.z>.95,"actual sharpened point drives forward diagonally from the right toward the target")
	check(angled_right and finish.x>0 and contact.x-finish.x<.12,"shaft keeps leaning right and follow-through stays short in front")
	view._play("FP_Pickaxe_SideStrike_Swing",true);var remaining:float=view.action_remaining;view.swing()
	check(is_equal_approx(remaining,view.action_remaining),"held input cannot restart the trial action")
	view._process(1.3)
	check(view.active_clip=="FP_Pickaxe_Diagonal_Idle" and view.action_remaining==0,"trial action returns to preserved idle")
	view.swing()
	check(view.active_clip=="FP_Pickaxe_SidePullback_Swing","explicit pullback alternate remains selected after review")
	var folder:="res://reports/pickaxe_side_strike";DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"approval":"PENDING USER VISUAL REVIEW; do not commit","checks":checks,"failures":failures,"body_error":body_error,"grip_error":grip_error,"seam_error":seam_error,"samples":rows,"scope":"Actual runtime rig, cutting-point mesh and animation controller in an isolated camera fixture. This does not approve visuals or test world collision/mining/performance."},"  "))
	stage.free();print("PICKAXE_SIDE_STRIKE checks=",checks," failures=",failures);quit(1 if failures else 0)

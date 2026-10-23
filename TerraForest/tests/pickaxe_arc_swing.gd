# SPDX-License-Identifier: 0BSD
extends "res://tests/pickaxe_side_strike.gd"

func chord_distance(point:Vector3,a:Vector3,b:Vector3)->float:
	var delta:=b-a
	return (point-(a+delta*clampf((point-a).dot(delta)/delta.length_squared(),0,1))).length()

func run()->void:
	var stage:=Node3D.new();root.add_child(stage)
	var camera:=Camera3D.new();camera.position=Vector3(0,1.68,0);stage.add_child(camera)
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();camera.add_child(tools)
	tools.equip(1);tools.set_process(false)
	var view:Node3D=tools.human;view.set_process(false)
	check(view.clips.size()==78 and view.active_clip=="FP_Pickaxe_Diagonal_Idle","arc-swing test remains separate from the selected pullback action")
	var kept:=preload("res://addons/characters/runtime/assets/Human.pickaxe_side_pullback.res")
	var trial:=preload("res://addons/characters/runtime/assets/Human.pickaxe_arc_swing.res")
	for entry in [["kept_pullback",kept],["arc_swing",trial]]:
		view.animation_player.add_animation_library(entry[0],entry[1].duplicate())
		for name in entry[1].get_animation_list():view.clips[String(name)]=entry[0]+"/"+String(name)
	var animation:Animation=trial.get_animation("FP_Pickaxe_ArcSwing_Swing")
	check(trial.get_animation_list().size()==1 and is_equal_approx(animation.length,1.2) and animation.loop_mode==Animation.LOOP_NONE,"separate copy retains a single 1.2-second action")
	var animation_only:=true
	for track in animation.get_track_count():animation_only=animation_only and animation.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D,Animation.TYPE_BLEND_SHAPE]
	check(animation_only,"no gameplay, audio, collision or method events are added")
	var skeleton:Skeleton3D=view.model.find_child("Skeleton3D",true,false)
	var pick:MeshInstance3D=view.model.find_child("Equipment_Pickaxe",true,false)
	var weapon:=skeleton.find_bone("Weapon_Pickaxe")
	var left:=skeleton.find_bone("LeftHand");var right:=skeleton.find_bone("RightHand")
	var camera_inverse:=camera.global_transform.affine_inverse()
	pose(view,"FP_Pickaxe_SidePullback_Swing",0)
	var ready:Array[Transform3D]=[]
	for index in skeleton.get_bone_count():ready.append(skeleton.get_bone_pose(index))
	var left_grip:Transform3D=skeleton.get_bone_global_pose(weapon).affine_inverse()*skeleton.get_bone_global_pose(left)
	var right_grip:Transform3D=skeleton.get_bone_global_pose(weapon).affine_inverse()*skeleton.get_bone_global_pose(right)
	var body_reference:={}
	for name in ["Root","Spine","Spine1","Spine2"]:body_reference[name]=skeleton.get_bone_global_pose(skeleton.find_bone(name))
	pose(view,"FP_Pickaxe_SidePullback_Swing",20.0/60)
	var old_hand_start:Vector3=camera_inverse*skeleton.global_transform*skeleton.get_bone_global_pose(left).origin
	pose(view,"FP_Pickaxe_SidePullback_Swing",32.0/60)
	var kept_contact:Vector3=camera_inverse*tool_head(pick,skeleton,true)
	var old_hand_end:Vector3=camera_inverse*skeleton.global_transform*skeleton.get_bone_global_pose(left).origin
	var old_head:Vector3=camera_inverse*tool_head(pick,skeleton)
	var old_pivot:Vector3=camera_inverse*skeleton.global_transform*skeleton.get_bone_global_pose(weapon).origin
	var old_lean:=rad_to_deg(atan2(old_head.x-old_pivot.x,old_head.y-old_pivot.y))
	var body_error:=0.0;var grip_error:=0.0;var seam_error:=0.0;var contact_lean:=0.0
	var points:={};var hands:={};var basis_at_chamber:Basis;var angular_stroke:=0.0
	for frame in 73:
		pose(view,"FP_Pickaxe_ArcSwing_Swing",float(frame)/60)
		var tool:Transform3D=skeleton.get_bone_global_pose(weapon)
		for name in body_reference:body_error=maxf(body_error,difference(body_reference[name],skeleton.get_bone_global_pose(skeleton.find_bone(name))))
		grip_error=maxf(grip_error,difference(left_grip,tool.affine_inverse()*skeleton.get_bone_global_pose(left)))
		grip_error=maxf(grip_error,difference(right_grip,tool.affine_inverse()*skeleton.get_bone_global_pose(right)))
		points[frame]=camera_inverse*tool_head(pick,skeleton,true)
		hands[frame]=camera_inverse*skeleton.global_transform*skeleton.get_bone_global_pose(left).origin
		if frame==20:basis_at_chamber=tool.basis
		if frame==32:
			var head:Vector3=camera_inverse*tool_head(pick,skeleton)
			var pivot:Vector3=camera_inverse*skeleton.global_transform*tool.origin
			contact_lean=rad_to_deg(atan2(head.x-pivot.x,head.y-pivot.y))
			angular_stroke=rad_to_deg(basis_at_chamber.get_rotation_quaternion().angle_to(tool.basis.get_rotation_quaternion()))
		if frame in [0,72]:
			for index in skeleton.get_bone_count():seam_error=maxf(seam_error,difference(ready[index],skeleton.get_bone_pose(index)))
		if frame in [0,12,20,26,32,40,54,72]:
			var point:Vector3=points[frame];var hand:Vector3=hands[frame]
			rows.append({"frame":frame,"working_point_camera":[point.x,point.y,point.z],"lower_hand_camera":[hand.x,hand.y,hand.z]})
	check(body_error<.0001,"root and torso remain neutral during the entire swing")
	check(grip_error<.0001,"both fitted hands stay attached to the handle")
	check(seam_error<.0001,"first and final bone poses match the kept ready grip")
	check((points[32]-kept_contact).length()<.001 and absf(contact_lean-old_lean-5)<.1,"forward contact is preserved with only five degrees of extra rightward tilt")
	var hand_forward:float=hands[20].z-hands[32].z
	var old_hand_forward:float=old_hand_start.z-old_hand_end.z
	var tip_forward:float=points[20].z-points[32].z
	check(hand_forward<.13 and hand_forward<old_hand_forward*.6 and tip_forward>hand_forward*3 and angular_stroke>40,"strike is driven by angular tool travel with much less forward hand extension")
	var windup_curve:=0.0;var strike_curve:=0.0;var recovery_curve:=0.0
	for frame in range(1,20):windup_curve=maxf(windup_curve,chord_distance(hands[frame],hands[0],hands[20]))
	for frame in range(21,40):strike_curve=maxf(strike_curve,chord_distance(hands[frame],hands[20],hands[40]))
	for frame in range(41,72):recovery_curve=maxf(recovery_curve,chord_distance(hands[frame],hands[40],hands[72]))
	check(windup_curve>.025 and strike_curve>.025 and recovery_curve>.025,"wind-up, strike and recovery all follow curved grip paths")
	var follow:Vector3=points[40]
	check(follow.z<-.95 and follow.x>-.10 and points[32].y-follow.y>.05,"follow-through stays forward with a bounded left/down continuation")
	view._play("FP_Pickaxe_ArcSwing_Swing",true);view._process(1.3)
	check(view.active_clip=="FP_Pickaxe_Diagonal_Idle" and view.action_remaining==0,"test action returns to the kept idle")
	view.swing();check(view.active_clip=="FP_Pickaxe_SidePullback_Swing","normal game selects the liked pullback candidate")
	var folder:="res://reports/pickaxe_arc_swing";DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"approval":"PENDING USER VISUAL REVIEW; do not commit","checks":checks,"failures":failures,"body_error":body_error,"grip_error":grip_error,"seam_error":seam_error,"extra_right_contact_tilt_degrees":contact_lean-old_lean,"hand_forward_m":hand_forward,"previous_hand_forward_m":old_hand_forward,"tip_forward_m":tip_forward,"angular_stroke_degrees":angular_stroke,"grip_curve_deviation_m":{"windup":windup_curve,"strike":strike_curve,"recovery":recovery_curve},"samples":rows,"scope":"Actual rig, evaluated cutting-point mesh and view controller in an isolated camera fixture. Engineering checks do not approve animation appearance or world collision/mining/performance."},"  "))
	stage.free();print("PICKAXE_ARC_SWING checks=",checks," failures=",failures);quit(1 if failures else 0)

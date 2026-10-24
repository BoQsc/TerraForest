# SPDX-License-Identifier: 0BSD
extends "res://tests/pickaxe_side_strike.gd"

func run()->void:
	var stage:=Node3D.new();root.add_child(stage)
	var camera:=Camera3D.new();camera.position=Vector3(0,1.68,0);stage.add_child(camera)
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();camera.add_child(tools)
	tools.equip(1);tools.set_process(false)
	var view:Node3D=tools.human;view.set_process(false)
	view.pickaxe_swing="pullback";view.equip(1)
	check(view.clips.has("FP_Pickaxe_Fresh_Swing") and view.active_clip=="FP_Pickaxe_Diagonal_Idle","explicit pullback alternate coexists with new default and kept diagonal holds")
	var kept:=preload("res://addons/characters/runtime/assets/Human.pickaxe_side_strike.res")
	var trial:=preload("res://addons/characters/runtime/assets/Human.pickaxe_side_pullback.res")
	for entry in [["kept_side",kept],["pullback",trial]]:
		view.animation_player.add_animation_library(entry[0],entry[1].duplicate())
		for name in entry[1].get_animation_list():view.clips[String(name)]=entry[0]+"/"+String(name)
	var animation:Animation=trial.get_animation("FP_Pickaxe_SidePullback_Swing")
	check(trial.get_animation_list().size()==1 and is_equal_approx(animation.length,1.2) and animation.loop_mode==Animation.LOOP_NONE,"new copy retains the single 1.2-second swing")
	var animation_only:=true
	for track in animation.get_track_count():animation_only=animation_only and animation.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D,Animation.TYPE_BLEND_SHAPE]
	check(animation_only,"trial contains no gameplay or method events")
	var skeleton:Skeleton3D=view.model.find_child("Skeleton3D",true,false)
	var pick:MeshInstance3D=view.model.find_child("Equipment_Pickaxe",true,false)
	var weapon:=skeleton.find_bone("Weapon_Pickaxe")
	var left:=skeleton.find_bone("LeftHand");var right:=skeleton.find_bone("RightHand")
	var preserved_error:=0.0;var body_error:=0.0;var orientation_error:=0.0;var grip_error:=0.0
	var lateral_error:=0.0;var extra_peak:=0.0;var depth_only:=true
	var camera_inverse:=camera.global_transform.affine_inverse()
	for frame in 73:
		pose(view,"FP_Pickaxe_SideStrike_Swing",float(frame)/60)
		var original:Array[Transform3D]=[];var body_reference:={}
		for index in skeleton.get_bone_count():original.append(skeleton.get_bone_pose(index))
		for name in ["Root","Spine","Spine1","Spine2"]:body_reference[name]=skeleton.get_bone_global_pose(skeleton.find_bone(name))
		var old_tool:Transform3D=skeleton.get_bone_global_pose(weapon)
		var old_left:Transform3D=old_tool.affine_inverse()*skeleton.get_bone_global_pose(left)
		var old_right:Transform3D=old_tool.affine_inverse()*skeleton.get_bone_global_pose(right)
		var old_tip:Vector3=camera_inverse*tool_head(pick,skeleton,true)
		pose(view,"FP_Pickaxe_SidePullback_Swing",float(frame)/60)
		if frame<=4 or frame>=28:
			for index in skeleton.get_bone_count():preserved_error=maxf(preserved_error,difference(original[index],skeleton.get_bone_pose(index)))
		for name in body_reference:body_error=maxf(body_error,difference(body_reference[name],skeleton.get_bone_global_pose(skeleton.find_bone(name))))
		var tool:Transform3D=skeleton.get_bone_global_pose(weapon)
		for axis in 3:orientation_error=maxf(orientation_error,(old_tool.basis[axis]-tool.basis[axis]).length())
		grip_error=maxf(grip_error,difference(old_left,tool.affine_inverse()*skeleton.get_bone_global_pose(left)))
		grip_error=maxf(grip_error,difference(old_right,tool.affine_inverse()*skeleton.get_bone_global_pose(right)))
		var point:Vector3=camera_inverse*tool_head(pick,skeleton,true)
		var delta:=point-old_tip
		lateral_error=maxf(lateral_error,Vector2(delta.x,delta.y).length())
		depth_only=depth_only and delta.z>=-.0001 and delta.z<.081
		if frame==20:extra_peak=delta.z
		if frame in [0,12,20,26,28,32,38,56,72]:rows.append({"frame":frame,"kept_tip_camera":[old_tip.x,old_tip.y,old_tip.z],"trial_tip_camera":[point.x,point.y,point.z],"extra_pullback_m":delta.z})
	check(preserved_error<.0001,"all 59 bones preserve ready frames and frames 28-72 including contact, follow-through and recovery")
	check(body_error<.0001 and orientation_error<.0001,"body pose and tool orientation match the liked side version at every frame")
	check(grip_error<.0001,"both hand wraps remain attached at the original handle stations")
	check(depth_only and lateral_error<.0001 and absf(extra_peak-.08)<.001,"wind-up adds 8 cm toward the player with no lateral or vertical redirection")
	view._play("FP_Pickaxe_SidePullback_Swing",true);view._process(1.3)
	check(view.action_remaining==0 and view.active_clip=="FP_Pickaxe_Diagonal_Idle","trial returns to the preserved idle after the action")
	view.swing()
	check(view.active_clip=="FP_Pickaxe_SidePullback_Swing","explicit pullback alternate remains selected after comparison")
	var folder:="res://reports/pickaxe_side_pullback";DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"approval":"PENDING USER VISUAL REVIEW; do not commit","checks":checks,"failures":failures,"preserved_pose_error":preserved_error,"body_error":body_error,"tool_basis_error":orientation_error,"grip_error":grip_error,"lateral_error":lateral_error,"peak_extra_pullback_m":extra_peak,"samples":rows,"scope":"Comparison of both imported animations on actual runtime rig and evaluated sharpened-point mesh in an isolated camera fixture. No visual acceptance, gameplay collision or performance claim."},"  "))
	stage.free();print("PICKAXE_SIDE_PULLBACK checks=",checks," failures=",failures);quit(1 if failures else 0)

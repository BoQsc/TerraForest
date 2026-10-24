# SPDX-License-Identifier: 0BSD
extends "res://tests/pickaxe_side_strike.gd"
const STUDY=preload("res://addons/characters/runtime/assets/Human.pickaxe_fresh.res")
func run()->void:
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,1.65,0)
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();camera.add_child(tools);tools.equip(1);tools.set_process(false)
	var view:Node3D=tools.human;view.set_process(false)
	check(view.swing_profile().clip=="FP_Pickaxe_Fresh_Swing" and is_equal_approx(view.swing_profile().contact,50.0/60.0) and view.active_clip=="FP_Pickaxe_Fresh_Idle","normal game selects accepted fixed-grip hold and frame-50 contact")
	check(STUDY.get_animation_list().size()==2 and is_equal_approx(STUDY.get_animation("FP_Pickaxe_Fresh_Swing").length,1.7),"new hold and 1.7-second action are isolated in their own library")
	var event_free:=true
	for name in STUDY.get_animation_list():
		var action:Animation=STUDY.get_animation(name)
		for track in action.get_track_count():event_free=event_free and action.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D,Animation.TYPE_BLEND_SHAPE]
	check(event_free,"review library contains animation only, with no gameplay/method/audio events")
	var skeleton:Skeleton3D=view.model.find_child("Skeleton3D",true,false)
	var mesh:MeshInstance3D=view.model.find_child("Equipment_Pickaxe",true,false)
	var weapon:=skeleton.find_bone("Weapon_Pickaxe");var left:=skeleton.find_bone("LeftHand");var right:=skeleton.find_bone("RightHand")
	pose(view,"FP_Pickaxe_Fresh_Idle",0)
	var ready:Array[Transform3D]=[]
	for index in skeleton.get_bone_count():ready.append(skeleton.get_bone_pose(index))
	var feet:={}
	for name in ["Root","LeftFoot","RightFoot"]:
		var index:=skeleton.find_bone(name);feet[index]=skeleton.get_bone_global_pose(index)
	var left_ref:Transform3D=skeleton.get_bone_global_pose(weapon).affine_inverse()*skeleton.get_bone_global_pose(left)
	var right_ref:Transform3D=skeleton.get_bone_global_pose(weapon).affine_inverse()*skeleton.get_bone_global_pose(right)
	var fixed_error:=0.0;var grip_error:=0.0;var seam_error:=0.0;var largest_step:=0.0
	var stations:Array[float]=[];var tips:Array[Vector3]=[];var previous:Array[Quaternion]=[]
	for frame in 103:
		pose(view,"FP_Pickaxe_Fresh_Swing",frame/60.0)
		var tool:Transform3D=skeleton.get_bone_global_pose(weapon)
		var l:Transform3D=tool.affine_inverse()*skeleton.get_bone_global_pose(left)
		var r:Transform3D=tool.affine_inverse()*skeleton.get_bone_global_pose(right)
		stations.append(r.origin.z)
		grip_error=maxf(grip_error,maxf(difference(l,left_ref),difference(r,right_ref)))
		for index:int in feet:fixed_error=maxf(fixed_error,difference(feet[index],skeleton.get_bone_global_pose(index)))
		var rotations:Array[Quaternion]=[]
		for index in skeleton.get_bone_count():
			var transform:=skeleton.get_bone_pose(index);rotations.append(transform.basis.get_rotation_quaternion())
			if frame in [0,102]:seam_error=maxf(seam_error,difference(ready[index],transform))
			if not previous.is_empty():largest_step=maxf(largest_step,rad_to_deg(rotations[index].angle_to(previous[index])))
		previous=rotations;tips.append(tool_head(mesh,skeleton,true))
	check(seam_error<.0001,"new swing begins and ends at its own newly authored hold")
	check(fixed_error<.0001,"both feet remain planted and root remains stationary during body movement")
	var station_travel:float=stations.max()-stations.min()
	check(grip_error<.0001 and station_travel<.0001,"both hands maintain full fixed transforms on shaft, with no axial slide or regrip")
	check(largest_step<25,"sampled bone motion has no abrupt rotation or elbow flips")
	check(tips[32].y-tips[50].y>.5,"actual cutting point descends from shoulder load to contact")
	view.action_remaining=0;view.swing(271)
	check(view.active_clip=="FP_Pickaxe_Fresh_Swing","ordinary swing uses the accepted default after pose evaluation")
	view.cancel_swing()
	check(view._motion_clip("Walk")=="FP_Pickaxe_Fresh_Walk" and view._motion_clip("Run")=="FP_Pickaxe_Fresh_Run" and view._motion_clip("Jump")=="FP_Pickaxe_Fresh_Jump","movement selects dedicated fixed-grip locomotion clips")
	view.pickaxe_swing="pullback";view.equip(1)
	check(view.swing_profile().clip=="FP_Pickaxe_SidePullback_Swing","previous pullback remains available as an explicit alternate")
	var report:={"status":"USER ACCEPTED fixed-grip default, 2026-10-24","checks":checks,"failures":failures,"grip_error":grip_error,"fixed_error":fixed_error,"seam_error":seam_error,"largest_bone_step_degrees":largest_step,"right_hand_slide_m":station_travel,"tip_descent_m":tips[32].y-tips[50].y,"scope":"Runtime skeleton, mesh and default selection integrity. World contact is checked separately by pickaxe_fresh_world."}
	FileAccess.open("res://reports/pickaxe_fresh/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	camera.free();print("PICKAXE_FRESH checks=",checks," failures=",failures);quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends "res://tests/pickaxe_side_strike.gd"

func run()->void:
	var camera:=Camera3D.new();root.add_child(camera)
	var body:=CharacterBody3D.new();root.add_child(body)
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();camera.add_child(tools);tools.equip(1);tools.set_process(false)
	var view:Node3D=tools.human;view.set_process(false);view.body=body
	var skeleton:Skeleton3D=view.model.find_child("Skeleton3D",true,false)
	var weapon:=skeleton.find_bone("Weapon_Pickaxe")
	pose(view,"FP_Pickaxe_Fresh_Idle",0)
	var grip:={};var fingers:={}
	var root_index:=skeleton.find_bone("Root");var root_pose:=skeleton.get_bone_global_pose(root_index)
	for name in ["LeftHand","RightHand"]:
		var index:=skeleton.find_bone(name)
		grip[index]=skeleton.get_bone_global_pose(weapon).affine_inverse()*skeleton.get_bone_global_pose(index)
	for index in skeleton.get_bone_count():
		var name:=skeleton.get_bone_name(index)
		if "Hand" in name and name not in ["LeftHand","RightHand"]:fingers[index]=skeleton.get_bone_pose(index)
	var records:={}
	for suffix:String in ["Walk","Run","Jump"]:
		var clip:="FP_Pickaxe_Fresh_"+suffix
		var action:Animation=view.animation_player.get_animation(view.clips[clip])
		var duration:float=action.length;var count:=roundi(duration*60)
		var grip_error:=0.0;var finger_error:=0.0;var root_error:=0.0;var seam_error:=0.0;var max_step:=0.0
		var first:Array[Transform3D]=[];var previous:Array[Quaternion]=[]
		var low:=Vector3(INF,INF,INF);var high:=-low
		var events_free:=true
		for track in action.get_track_count():events_free=events_free and action.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D,Animation.TYPE_BLEND_SHAPE]
		for frame in count*2+1:
			# Include halfway samples between baked keys, not just exact keyframes.
			pose(view,clip,frame/120.0)
			var tool:Transform3D=skeleton.get_bone_global_pose(weapon)
			var head:Vector3=tool*Vector3(0,0,.6)
			low=low.min(head);high=high.max(head)
			for index:int in grip:grip_error=maxf(grip_error,difference(grip[index],tool.affine_inverse()*skeleton.get_bone_global_pose(index)))
			for index:int in fingers:finger_error=maxf(finger_error,difference(fingers[index],skeleton.get_bone_pose(index)))
			root_error=maxf(root_error,difference(root_pose,skeleton.get_bone_global_pose(root_index)))
			var rotations:Array[Quaternion]=[]
			for index in skeleton.get_bone_count():
				var current:=skeleton.get_bone_pose(index);rotations.append(current.basis.get_rotation_quaternion())
				if frame==0:first.append(current)
				if frame==count*2:seam_error=maxf(seam_error,difference(first[index],current))
				if not previous.is_empty():max_step=maxf(max_step,rad_to_deg(rotations[index].angle_to(previous[index])))
			previous=rotations
		check(grip_error<.0002 and finger_error<.0001,suffix+": both hand transforms and finger wraps stay fixed on the shaft")
		check(root_error<.0001 and events_free,suffix+": presentation adds no root motion or gameplay events")
		check(seam_error<.0001,suffix+": endpoints form a seamless cycle")
		check(max_step<15,suffix+": no abrupt joint rotation between samples")
		check((high-low).length()>.02 and (high-low).length()<.13,suffix+": visible but restrained tool movement")
		records[suffix]={"grip_error":grip_error,"finger_error":finger_error,"seam_error":seam_error,"root_error":root_error,"max_half_frame_rotation_degrees":max_step,"head_travel":high-low}
	pose(view,"FP_Pickaxe_Fresh_Idle",0);view.equip(1)
	var position_before:=body.position
	for entry in [[Vector3(0,0,5.5),"Walk"],[Vector3(0,0,9.9),"Run"],[Vector3(0,4,3),"Jump"],[Vector3.ZERO,"Idle"]]:
		body.velocity=entry[0];view._process(.12)
		check(view.active_clip=="FP_Pickaxe_Fresh_"+entry[1],"actual velocity selects "+entry[1])
	check(body.position==position_before and body.velocity==Vector3.ZERO,"animation does not integrate or alter player movement")
	var blend_grip_error:=0.0;var blend_position_error:=0.0;var blend_angle_degrees:=0.0
	for speed in [3.0,7.0,0.0]:
		body.velocity=Vector3(0,0,speed)
		for frame in 18:
			view._process(1.0/120.0)
			var tool:Transform3D=skeleton.get_bone_global_pose(weapon)
			for index:int in grip:
				var hand:Transform3D=tool.affine_inverse()*skeleton.get_bone_global_pose(index)
				blend_grip_error=maxf(blend_grip_error,difference(grip[index],hand))
				blend_position_error=maxf(blend_position_error,grip[index].origin.distance_to(hand.origin))
				blend_angle_degrees=maxf(blend_angle_degrees,rad_to_deg(grip[index].basis.get_rotation_quaternion().angle_to(hand.basis.get_rotation_quaternion())))
	check(blend_position_error<.005 and blend_angle_degrees<2,"brief idle/walk/run crossfades keep hands within 5 mm and 2 degrees of the shaft grip")
	body.velocity=Vector3(0,0,3);view._process(.12)
	view.swing(390);view._process(.2)
	check(view.active_clip=="FP_Pickaxe_Fresh_Swing","approved swing takes priority while moving")
	for frame in 120:view._process(1.0/60.0)
	check(view.active_clip=="FP_Pickaxe_Fresh_Walk" and view.action_remaining==0,"movement resumes after the complete approved swing")
	view.equip(2);view._process(.12)
	check(view.active_clip=="FP_Axe_Walk","axe locomotion remains unchanged")
	var folder:="res://reports/pickaxe_locomotion";DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"clips":records,"blend_grip_error":blend_grip_error,"blend_position_error_m":blend_position_error,"blend_angle_degrees":blend_angle_degrees,"scope":"Rig, interpolation and velocity dispatch. Appearance needs playtest; world motor checked separately."},"  "))
	camera.free();body.free();print("PICKAXE_LOCOMOTION checks=",checks," failures=",failures);quit(1 if failures else 0)

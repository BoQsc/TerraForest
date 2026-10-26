# SPDX-License-Identifier: 0BSD
extends "res://tests/pickaxe_side_strike.gd"
const CANDIDATE=preload("res://addons/characters/runtime/assets/Human.pickaxe_crosscut.res")
func run()->void:
	var ordinary:=preload("res://addons/player_runtime/tool_view.gd").new();root.add_child(ordinary);ordinary.equip(1)
	check(ordinary.attack_profile().clip=="FP_Pickaxe_Fresh_Swing" and ordinary.human.active_clip=="FP_Pickaxe_Fresh_Idle","ordinary game still selects the accepted default")
	ordinary.human.set_process(false);ordinary.set_process(false)
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,1.65,0)
	var tool:=preload("res://addons/characters/experiments/pickaxe_crosscut_tools.gd").new();camera.add_child(tool);tool.equip(1);tool.set_process(false)
	var view:Node3D=tool.human;view.set_process(false)
	var skeleton:Skeleton3D=view.model.find_child("Skeleton3D",true,false);var mesh:MeshInstance3D=view.model.find_child("Equipment_Pickaxe",true,false)
	var weapon:=skeleton.find_bone("Weapon_Pickaxe");var hands:={};var fingers:={};var roots:={}
	pose(view,"FP_Pickaxe_Crosscut_Idle",0)
	var ready_head:Vector3=camera.global_transform.affine_inverse()*tool_head(mesh,skeleton)
	check(ready_head.x>.4 and ready_head.y>.2 and ready_head.y<.5,"ready pickaxe head is raised into the upper-right quadrant")
	for side:String in ["Left","Right"]:hands[side]=skeleton.get_bone_global_pose(weapon).affine_inverse()*skeleton.get_bone_global_pose(skeleton.find_bone(side+"Hand"))
	for bone in skeleton.get_bone_count():
		var name:=String(skeleton.get_bone_name(bone))
		if "Hand" in name and name not in ["LeftHand","RightHand"]:fingers[bone]=skeleton.get_bone_pose(bone)
	for name:String in ["Root","LeftFoot","RightFoot"]:roots[name]=skeleton.get_bone_global_pose(skeleton.find_bone(name))
	var records:={};var swing_tips:Array[Vector3]=[]
	for suffix:String in ["Idle","Swing","Walk","Run","Jump","Crouch"]:
		var clip:="FP_Pickaxe_Crosscut_"+suffix;var animation:Animation=CANDIDATE.get_animation(clip)
		var grip_error:=0.0;var key_error:=0.0;var position_error:=0.0;var angle_error:=0.0;var finger_error:=0.0;var wrist:=0.0;var step:=0.0;var root_error:=0.0;var previous:={};var samples:Array=[]
		for frame in roundi(animation.length*240)+1:
			pose(view,clip,frame/240.0);var row:={"frame":frame*.5}
			for side:String in ["Left","Right"]:
				var hand:=skeleton.get_bone_global_pose(skeleton.find_bone(side+"Hand"));var elbow:=skeleton.get_bone_global_pose(skeleton.find_bone(side+"ForeArm"))
				var relative:Transform3D=skeleton.get_bone_global_pose(weapon).affine_inverse()*hand
				var error:=difference(hands[side],relative);grip_error=maxf(grip_error,error)
				if frame%2==0:key_error=maxf(key_error,error)
				position_error=maxf(position_error,hands[side].origin.distance_to(relative.origin))
				angle_error=maxf(angle_error,rad_to_deg(hands[side].basis.get_rotation_quaternion().angle_to(relative.basis.get_rotation_quaternion())))
				var angle:=rad_to_deg((hand.origin-elbow.origin).angle_to(hand.basis.y));wrist=maxf(wrist,angle);row[side]=angle
				for part:String in ["Arm","ForeArm","Hand"]:
					var name:=side+part;var q:=skeleton.get_bone_pose(skeleton.find_bone(name)).basis.get_rotation_quaternion()
					if previous.has(name):step=maxf(step,rad_to_deg(previous[name].angle_to(q)))
					previous[name]=q
			for bone:int in fingers:finger_error=maxf(finger_error,difference(fingers[bone],skeleton.get_bone_pose(bone)))
			if suffix=="Swing":
				for name:String in roots:root_error=maxf(root_error,difference(roots[name],skeleton.get_bone_global_pose(skeleton.find_bone(name))))
				var tip:=camera.global_transform.affine_inverse()*tool_head(mesh,skeleton,true);swing_tips.append(tip);row.tip_camera=[tip.x,tip.y,tip.z]
			samples.append(row)
		check(key_error<.0001 and position_error<.001 and angle_error<.3 and finger_error<.0001,suffix+": fixed keyed grips; interpolation stays under 1 mm and 0.3 degrees")
		check(wrist<40 and step<12,suffix+": wrists stay aligned and arms have no rotation flips")
		if suffix=="Swing":check(root_error<.002,"swing plants both feet and keeps the player root still")
		records[suffix]={"grip_error":grip_error,"key_error":key_error,"position_error":position_error,"angle_error":angle_error,"finger_error":finger_error,"wrist_degrees":wrist,"joint_step":step,"root_error":root_error,"samples":samples}
	var start:=swing_tips[112];var hit:=swing_tips[168];var follow:=swing_tips[200];var descending:=true
	for index in range(113,201):descending=descending and swing_tips[index].x<swing_tips[index-1].x+.0001 and swing_tips[index].y<swing_tips[index-1].y+.0001
	check(start.x>0 and start.y>0 and follow.x<0 and follow.y<0 and descending,"actual cutting point travels from upper right to lower left through impact")
	check(start.x-follow.x>.45 and start.y-follow.y>.35 and hit.z<start.z-.08,"descending strike travels across the cursor with forward depth")
	check(Vector2(hit.x,hit.y).length()<.015 and hit.z<-.85,"actual cutting point reaches the cursor centerline at the gameplay contact time")
	var contacts:Array=[];var finishes:Array=[]
	tool.attack_contact.connect(func(identity:int):contacts.append([identity,view.animation_player.current_animation_position]))
	tool.attack_finished.connect(func(identity:int,cancelled:bool):finishes.append([identity,cancelled]))
	view.action_remaining=0;view.equip(1)
	check(tool.begin_attack(401),"candidate starts through normal attack signals")
	view._process(.6);check(contacts.is_empty(),"no impact during windup")
	view._process(.3);check(contacts.size()==1 and contacts[0][0]==401 and is_equal_approx(contacts[0][1],.7),"long frame emits exactly one impact on authored frame 42")
	view._process(1);check(finishes==[[401,false]] and view.active_clip=="FP_Pickaxe_Crosscut_Idle","recovery returns to its diagonal hold")
	tool.begin_attack(402);view._process(.2);tool.cancel_attack();view._process(1)
	check(contacts.size()==1 and finishes.back()==[402,true],"interrupted stroke cannot produce an extra impact")
	view.set_candidate(false);check(tool.attack_profile().clip=="FP_Pickaxe_Fresh_Swing" and view.active_clip=="FP_Pickaxe_Fresh_Idle","A/B switch restores accepted hold and timing")
	view.set_candidate(true);check(tool.attack_profile().clip=="FP_Pickaxe_Crosscut_Swing","A/B switch restores the separate candidate")
	tool.equip(2);check(tool.attack_profile().clip=="FP_Axe_Swing","other tools retain their ordinary animation")
	DirAccess.make_dir_recursive_absolute("res://reports/pickaxe_crosscut")
	FileAccess.open("res://reports/pickaxe_crosscut/runtime.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"clips":records,"ready_head":[ready_head.x,ready_head.y,ready_head.z],"tip_load":[start.x,start.y,start.z],"tip_contact":[hit.x,hit.y,hit.z],"tip_follow":[follow.x,follow.y,follow.z]},"  "))
	ordinary.free();camera.free();print("PICKAXE_CROSSCUT checks=",checks," failures=",failures);quit(1 if failures else 0)

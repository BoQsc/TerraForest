# SPDX-License-Identifier: 0BSD
extends "res://tests/pickaxe_side_strike.gd"
const CANDIDATE=preload("res://addons/characters/runtime/assets/Human.pickaxe_crosscut.res")
func screen_position(point:Vector3)->Vector2:
	var half_height:float=-point.z*tan(deg_to_rad(75.0)*.5)
	return Vector2(.5+point.x/(2*half_height*16.0/9.0),.5-point.y/(2*half_height))
func foremost_steel(mesh:MeshInstance3D,skeleton:Skeleton3D,camera:Camera3D)->float:
	var depth:=INF
	for surface in mesh.mesh.get_surface_count():
		if not "steel" in mesh.mesh.surface_get_material(surface).resource_name.to_lower():continue
		var arrays:=mesh.mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES];var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
		var influences:=bones.size()/vertices.size()
		for vertex in vertices.size():
			var current:=Vector3.ZERO
			for influence in influences:
				var offset:=vertex*influences+influence;var bind:int=bones[offset]
				if weights[offset]<=0:continue
				var name:=mesh.skin.get_bind_name(bind)
				var bone:=skeleton.find_bone(name) if name!=&"" else mesh.skin.get_bind_bone(bind)
				current+=(skeleton.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(bind)*vertices[vertex])*weights[offset]
			depth=minf(depth,(camera.global_transform.affine_inverse()*skeleton.global_transform*current).z)
	return depth
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
	var head_screen:=screen_position(ready_head)
	check(head_screen.x>.6 and head_screen.x<.85 and head_screen.y>.12 and head_screen.y<.35,"ready head stays inside the upper-right view instead of crowding its outer corner")
	var ready_hands:={}
	for side:String in ["Left","Right"]:
		ready_hands[side]=camera.global_transform.affine_inverse()*skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(side+"Hand")).origin
	check(ready_hands.Left.y<-.35 and ready_hands.Left.z<-.26 and ready_hands.Left.length()>.43 and ready_hands.Right.y<-.15 and ready_hands.Right.z<-.35,"ready grips stay low and away from the camera center")
	for side:String in ["Left","Right"]:hands[side]=skeleton.get_bone_global_pose(weapon).affine_inverse()*skeleton.get_bone_global_pose(skeleton.find_bone(side+"Hand"))
	for bone in skeleton.get_bone_count():
		var name:=String(skeleton.get_bone_name(bone))
		if "Hand" in name and name not in ["LeftHand","RightHand"]:fingers[bone]=skeleton.get_bone_pose(bone)
	for name:String in ["Root","LeftFoot","RightFoot"]:roots[name]=skeleton.get_bone_global_pose(skeleton.find_bone(name))
	var records:={};var swing_tips:Array[Vector3]=[];var swing_grips:Array[Vector3]=[];var swing_rotations:Array[Quaternion]=[]
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
				swing_grips.append(camera.global_transform.affine_inverse()*skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).origin)
				swing_rotations.append(skeleton.get_bone_global_pose(weapon).basis.get_rotation_quaternion())
			samples.append(row)
		check(key_error<.0001 and position_error<.001 and angle_error<.3 and finger_error<.0001,suffix+": fixed keyed grips; interpolation stays under 1 mm and 0.3 degrees")
		check(wrist<40 and step<12,suffix+": wrists stay aligned and arms have no rotation flips")
		if suffix=="Swing":check(root_error<.002,"swing plants both feet and keeps the player root still")
		records[suffix]={"grip_error":grip_error,"key_error":key_error,"position_error":position_error,"angle_error":angle_error,"finger_error":finger_error,"wrist_degrees":wrist,"joint_step":step,"root_error":root_error,"samples":samples}
	var start:=swing_tips[112];var hit:=swing_tips[168];var follow:=swing_tips[200];var descending:=true
	for index in range(113,201):descending=descending and swing_tips[index].x<swing_tips[index-1].x+.0001 and swing_tips[index].y<swing_tips[index-1].y+.0001
	check(start.x>0 and start.y>0 and follow.x<0 and follow.y<0 and descending,"actual cutting point travels from upper right to lower left through impact")
	check(start.x-follow.x>.45 and start.y-follow.y>.28 and hit.z<start.z-.3,"point drives forward from the upper right, then follows down-left")
	var hit_screen:=screen_position(hit)
	check(hit_screen.x>.45 and hit_screen.x<.56 and hit_screen.y>.40 and hit_screen.y<.49 and hit.z<-.85,"point reaches the upper-center target area without forcing the shaft onto the cursor")
	var rotation_sweep:=rad_to_deg(swing_rotations[112].angle_to(swing_rotations[200]));var tip_travel:=0.0;var grip_travel:=0.0
	for index in range(113,201):
		tip_travel+=swing_tips[index].distance_to(swing_tips[index-1]);grip_travel+=swing_grips[index].distance_to(swing_grips[index-1])
	# A 100-degree reversal of screen lean passed the old test while making the
	# head swipe sideways. Qualify the direction and leading part, not arc size.
	check(rotation_sweep>40 and grip_travel<.35 and tip_travel>grip_travel*3,"forward pitch produces the stroke around a compact fixed grip")
	pose(view,"FP_Pickaxe_Crosscut_Swing",.7)
	var contact_head:=camera.global_transform.affine_inverse()*tool_head(mesh,skeleton)
	var velocity:Vector3=(swing_tips[169]-swing_tips[167])*120
	var direction:Vector3=(hit-contact_head).normalized()
	var alignment:=direction.dot(velocity.normalized())
	var forward_fraction:float=-velocity.normalized().z
	check(alignment>.9 and forward_fraction>.3 and velocity.x<0 and velocity.y<0,"point faces its forward-left descending impact velocity")
	check(hit.z<contact_head.z-.15 and hit.z<=foremost_steel(mesh,skeleton,camera)+.005,"sharpened point reaches the surface before the socket or broad back")
	check(contact_head.x>hit.x+.15 and screen_position(contact_head).x-hit_screen.x>.08,"socket and back remain visibly to the right of the point at impact")
	var impact:={"head":[contact_head.x,contact_head.y,contact_head.z],"velocity":[velocity.x,velocity.y,velocity.z],"point_alignment":alignment,"forward_fraction":forward_fraction,"tip_screen":[hit_screen.x,hit_screen.y]}
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
	FileAccess.open("res://reports/pickaxe_crosscut/runtime.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"clips":records,"impact":impact,"ready_head":[ready_head.x,ready_head.y,ready_head.z],"ready_head_screen":[head_screen.x,head_screen.y],"ready_left_hand":[ready_hands.Left.x,ready_hands.Left.y,ready_hands.Left.z],"ready_right_hand":[ready_hands.Right.x,ready_hands.Right.y,ready_hands.Right.z],"rotation_sweep_degrees":rotation_sweep,"tip_travel_m":tip_travel,"grip_travel_m":grip_travel,"tip_load":[start.x,start.y,start.z],"tip_contact":[hit.x,hit.y,hit.z],"tip_follow":[follow.x,follow.y,follow.z]},"  "))
	ordinary.free();camera.free();print("PICKAXE_CROSSCUT checks=",checks," failures=",failures);quit(1 if failures else 0)

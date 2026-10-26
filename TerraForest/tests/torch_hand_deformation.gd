# SPDX-License-Identifier: 0BSD
extends "res://tests/pickaxe_side_strike.gd"
# Torch wood has a curved centre and a gently irregular profile. Evaluate that
# authored surface instead of treating the shaft's deeply embedded core as safe.
# 0.5 mm tolerance below covers its 64-segment/64-row polygon approximation.
func shaft_clearance(point:Vector3)->float:
	var z:=point.y/.8 if point.y>0 else point.y
	var v:=clampf((z+.22)/.675,0,1)
	var cross_section:=Vector2(point.x-.003*sin(z*7),-point.z-.002*sin(z*11))
	var angle:=cross_section.angle()
	var radius:=(.0205+.001*pow(sin(PI*v),.6))*(1+.035*sin(angle*5+v*3)+.022*sin(angle*9-v*7))
	return cross_section.length()-radius
func run()->void:
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();root.add_child(tools);tools.set_process(false);tools.equip(6)
	var view:Node3D=tools.human;view.set_process(false);view.torch_effects.set_burning(false)
	var baseline:="--baseline" in OS.get_cmdline_user_args()
	if baseline:
		view.animation_player.remove_animation_library("torch");view.animation_player.add_animation_library("torch",load("res://reports/torch_hands/before.res"))
	var skeleton:Skeleton3D=view.model.find_children("*","Skeleton3D",true,false)[0]
	var torch_root:Node3D=view.torch_effects.get_parent()
	var skin:Skin=view.body_mesh.skin;var bindings:Array[int]=[]
	for index in skin.get_bind_count():
		var name:=String(skin.get_bind_name(index));bindings.append(skeleton.find_bone(name) if not name.is_empty() else skin.get_bind_bone(index))
	var vertices:Array[Dictionary]=[]
	for surface in view.body_mesh.mesh.get_surface_count():
		var arrays:Array=view.body_mesh.mesh.surface_get_arrays(surface)
		var width:int=arrays[Mesh.ARRAY_WEIGHTS].size()/arrays[Mesh.ARRAY_VERTEX].size()
		for vertex in arrays[Mesh.ARRAY_VERTEX].size():
			var indices:Array[int]=[];var weights:Array[float]=[];var hand_weight:=0.0;var strongest:=0.0;var label:=""
			for slot in width:
				var binding:int=arrays[Mesh.ARRAY_BONES][vertex*width+slot];var weight:float=arrays[Mesh.ARRAY_WEIGHTS][vertex*width+slot]
				indices.append(binding);weights.append(weight)
				var name:=String(skeleton.get_bone_name(bindings[binding]))
				if name.begins_with("RightHand"):
					hand_weight+=weight
					if weight>strongest:label=name;strongest=weight
			if hand_weight>.8:vertices.append({"point":arrays[Mesh.ARRAY_VERTEX][vertex],"bindings":indices,"weights":weights,"label":label})
	var records:={};var weapon:=skeleton.find_bone("Weapon_Axe")
	for suffix:String in (["Idle","Walk","Run","Jump","Crouch"] if baseline else ["Idle","Walk","Run","Jump","Crouch","Equip"]):
		var animation:Animation=view.animation_player.get_animation(view.clips["FP_Torch_"+suffix])
		var rows:Array=[];var worst_bend:=0.0;var minimum_radius:=INF;var minimum_clearance:=INF;var closest_by_bone:={};var max_step:=0.0;var previous:={}
		for frame in roundi(animation.length*120)+1:
			pose(view,"FP_Torch_"+suffix,frame/120.0)
			var row:={"frame":frame*.5};var palette:Array[Transform3D]=[]
			for index in bindings.size():palette.append(skeleton.get_bone_global_pose(bindings[index])*skin.get_bind_pose(index))
			skeleton.force_update_all_bone_transforms()
			# This synchronous audit does not yield to the render frame. Refresh
			# BoneAttachment exactly as its normal skeleton_updated callback does.
			torch_root.get_parent().on_skeleton_update()
			var inverse:Transform3D=(skeleton.get_bone_global_pose(weapon)*skeleton.get_bone_global_rest(weapon).affine_inverse()).affine_inverse() if baseline else (skeleton.global_transform.affine_inverse()*torch_root.global_transform).affine_inverse()
			for side:String in ["Left","Right"]:
				var hand:=skeleton.get_bone_global_pose(skeleton.find_bone(side+"Hand"));var elbow:=skeleton.get_bone_global_pose(skeleton.find_bone(side+"ForeArm"))
				var bend:=rad_to_deg((hand.origin-elbow.origin).angle_to(hand.basis.y));worst_bend=maxf(worst_bend,bend);row[side]=bend
				for part:String in ["Arm","ForeArm","Hand"]:
					var bone:=skeleton.find_bone(side+part);var rotation:=skeleton.get_bone_pose(bone).basis.get_rotation_quaternion()
					if previous.has(bone):
						var step:=rad_to_deg(previous[bone].angle_to(rotation))
						if step>max_step:row.maximum_step_bone=side+part;row.maximum_step=step
						max_step=maxf(max_step,step)
					previous[bone]=rotation
			var nearest:=INF;var clearance:=INF
			for vertex in vertices:
				var point:=Vector3.ZERO
				for slot in vertex.bindings.size():point+=(palette[vertex.bindings[slot]]*vertex.point)*vertex.weights[slot]
				point=inverse*point
				if point.y<-.20 or point.y>.16:continue
				var radial:=Vector2(point.x,point.z).length()
				nearest=minf(nearest,radial)
				clearance=minf(clearance,shaft_clearance(point))
				closest_by_bone[vertex.label]=minf(closest_by_bone.get(vertex.label,INF),radial)
			row.nearest_shaft_radius=nearest;row.shaft_clearance=clearance;minimum_clearance=minf(minimum_clearance,clearance);minimum_radius=minf(minimum_radius,nearest);rows.append(row)
		check(worst_bend<35,suffix+": both wrists remain within 35 degrees at every key and half-key")
		check(max_step<5,suffix+": arms, forearms and wrists have no roll flips")
		check(minimum_clearance>-.0005,suffix+": actual hand skin clears the curved wooden shaft (0.5 mm tolerance)")
		var all_touch:=true
		for finger:String in ["Index","Middle","Ring","Pinky","Thumb"]:
			all_touch=all_touch and closest_by_bone.get("RightHand"+finger+"3",INF)<.029
		check(all_touch,suffix+": every distal finger pad stays close to the handle")
		records[suffix]={"max_wrist_bend":worst_bend,"max_joint_step":max_step,"minimum_skin_radius":minimum_radius,"minimum_clearance":minimum_clearance,"closest_by_bone":closest_by_bone,"frames":rows}
		print("SKIN ",suffix," wrist=",worst_bend," radius=",minimum_radius," by_bone=",closest_by_bone)
	var transitions:={}
	if not baseline:
		for item in [0,1,2,3,5,401]:
			tools.equip(item)
			for frame in 30:view._process(1.0/120)
			tools.equip(6);var maximum:=0.0
			for frame in 90:
				view._process(1.0/120)
				for side:String in ["Left","Right"]:
					var hand:=skeleton.get_bone_global_pose(skeleton.find_bone(side+"Hand"));var elbow:=skeleton.get_bone_global_pose(skeleton.find_bone(side+"ForeArm"))
					maximum=maxf(maximum,rad_to_deg((hand.origin-elbow.origin).angle_to(hand.basis.y)))
			transitions[item]=maximum
			check(maximum<50,"item %d to torch: equip blend does not fold the wrist"%item)
		view._play("FP_Torch_Idle",false,0);view.animation_player.advance(0)
		skeleton.force_update_all_bone_transforms()
		torch_root.get_parent().on_skeleton_update()
		var grip:Transform3D=(skeleton.global_transform.affine_inverse()*torch_root.global_transform).affine_inverse()*skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))
		for suffix:String in ["Walk","Run","Jump","Idle","Crouch","Idle"]:
			view._play("FP_Torch_"+suffix);var bend:=0.0;var drift:=0.0;var position_drift:=0.0;var rotation_drift:=0.0
			for frame in 36:
				view.animation_player.advance(1.0/120)
				skeleton.force_update_all_bone_transforms()
				torch_root.get_parent().on_skeleton_update()
				var hand:=skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"));var elbow:=skeleton.get_bone_global_pose(skeleton.find_bone("RightForeArm"))
				bend=maxf(bend,rad_to_deg((hand.origin-elbow.origin).angle_to(hand.basis.y)))
				var current:Transform3D=(skeleton.global_transform.affine_inverse()*torch_root.global_transform).affine_inverse()*hand
				drift=maxf(drift,difference(grip,current));position_drift=maxf(position_drift,grip.origin.distance_to(current.origin));rotation_drift=maxf(rotation_drift,rad_to_deg(grip.basis.get_rotation_quaternion().angle_to(current.basis.get_rotation_quaternion())))
			print("BLEND ",suffix," bend=",bend," drift=",drift," position=",position_drift," rotation=",rotation_drift)
			check(bend<35 and drift<.002,"motion blend into "+suffix+": wrist alignment and fixed grip survive interpolation")
	DirAccess.make_dir_recursive_absolute("res://reports/torch_hands")
	FileAccess.open("res://reports/torch_hands/"+("before_skin.json" if baseline else "deformation.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"vertices":vertices.size(),"clips":records,"equip_bends":transitions},"  ")+"\n")
	tools.free();print("TORCH_HAND_DEFORMATION checks=",checks," failures=",failures);quit(1 if failures else 0)

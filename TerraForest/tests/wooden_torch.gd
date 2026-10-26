# SPDX-License-Identifier: 0BSD
extends "res://tests/pickaxe_side_strike.gd"
func run()->void:
	var camera:=Camera3D.new();root.add_child(camera)
	var body:=CharacterBody3D.new();root.add_child(body)
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();camera.add_child(tools);tools.set_process(false);tools.equip(6)
	var view:Node3D=tools.human;view.set_process(false);view.body=body;view.torch_effects.set_process(false)
	var skeleton:Skeleton3D=view.model.find_children("*","Skeleton3D",true,false)[0]
	var hand:=skeleton.find_bone("RightHand");var weapon:=skeleton.find_bone("Weapon_Axe")
	pose(view,"FP_Torch_Idle",0)
	var grip:Transform3D=skeleton.get_bone_global_pose(weapon).affine_inverse()*skeleton.get_bone_global_pose(hand)
	var fingers:={}
	for bone in skeleton.get_bone_count():
		if String(skeleton.get_bone_name(bone)).begins_with("RightHand") and bone!=hand:fingers[bone]=skeleton.get_bone_pose(bone)
	var records:={}
	for suffix:String in ["Idle","Walk","Run","Jump","Crouch","Equip"]:
		var clip:="FP_Torch_"+suffix;var animation:Animation=view.animation_player.get_animation(view.clips[clip])
		var grip_error:=0.0;var finger_error:=0.0;var previous:Quaternion;var max_step:=0.0;var events_free:=true
		for track in animation.get_track_count():events_free=events_free and animation.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D,Animation.TYPE_BLEND_SHAPE]
		for frame in roundi(animation.length*120)+1:
			pose(view,clip,frame/120.0)
			var relative:=skeleton.get_bone_global_pose(weapon).affine_inverse()*skeleton.get_bone_global_pose(hand)
			grip_error=maxf(grip_error,difference(grip,relative))
			for bone:int in fingers:finger_error=maxf(finger_error,difference(fingers[bone],skeleton.get_bone_pose(bone)))
			var rotation:=skeleton.get_bone_global_pose(hand).basis.get_rotation_quaternion()
			if frame>0:max_step=maxf(max_step,rad_to_deg(previous.angle_to(rotation)))
			previous=rotation
		check(grip_error<.0003 and finger_error<.0001,suffix+": firm shaft grip and finger wrap at 120 Hz")
		check(events_free and max_step<5,suffix+": smooth presentation without gameplay event tracks")
		records[suffix]={"grip_error":grip_error,"finger_error":finger_error,"maximum_hand_step_degrees":max_step}
	tools.equip(6)
	for frame in 60:view._process(1.0/120)
	check(tools.attack_profile().is_empty() and not tools.begin_attack(91),"torch does not silently punch, mine or damage targets")
	check(view.body_mesh.mesh==view.unarmed_body_mesh,"torch uses corrected hand skin weights")
	for row in [[Vector3(0,0,5.5),"Walk"],[Vector3(0,0,9.9),"Run"],[Vector3(0,4,3),"Jump"],[Vector3.ZERO,"Idle"]]:
		body.velocity=row[0];view._process(.12);check(view.active_clip=="FP_Torch_"+row[1],"velocity dispatches torch "+row[1])
	view.set_third_person(true);view.crouched=true;view._process(.12)
	check(view.active_clip=="FP_Torch_Crouch","third-person crouch retains the torch grip")
	view.crouched=false;view.set_third_person(false)
	check(view.torch_effects.burning and view.torch_effects.lamp.shadow_enabled,"equipped torch has burning effects and shadowed local light")
	var minimum:=INF;var maximum:=0.0
	for i in 240:
		view.torch_effects.advance(1.0/60);minimum=minf(minimum,view.torch_effects.lamp.light_energy);maximum=maxf(maximum,view.torch_effects.lamp.light_energy)
	check(minimum>1.45 and maximum<1.85 and maximum-minimum>.1,"light flicker remains gentle and bounded")
	tools.hide();view.torch_effects.advance(0)
	check(view.torch_effects.lamp.light_energy==0,"hidden player/tool extinguishes local lighting")
	tools.show();view.torch_effects.advance(0)
	check(view.torch_effects.lamp.light_energy>0,"visible held torch resumes lighting")
	tools.place();check(not view.torch_effects.burning and view.torch_effects.lamp.light_energy==0,"placement hides fire as well as the shaft")
	for frame in 120:view._process(1.0/60)
	check(view.torch_effects.burning,"carry flame returns after placement")
	tools.equip(1)
	check(not view.torch_effects.burning and not view.torch_effects.is_processing() and view.torch_effects.lamp.light_energy==0,"switching slots stops all torch processing and lighting")
	check(view.active_clip=="FP_Pickaxe_Fresh_Idle","accepted pickaxe remains the default")
	var triangles:=0;var mapped:=0
	for mesh:MeshInstance3D in view.meshes:
		if not String(mesh.name).to_lower().contains("equipment_torch") and not String(mesh.name).to_lower().contains("equipment.torch"):continue
		for surface in mesh.mesh.get_surface_count():
			triangles+=mesh.mesh.surface_get_array_index_len(surface)/3
			var material:StandardMaterial3D=mesh.mesh.surface_get_material(surface)
			if material.albedo_texture!=null and material.roughness_texture!=null and material.normal_texture!=null:mapped+=1
	check(triangles>15000 and mapped>=3,"torch has detailed winding geometry and three embedded PBR materials")
	DirAccess.make_dir_recursive_absolute("res://reports/wooden_torch")
	FileAccess.open("res://reports/wooden_torch/runtime.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"triangles":triangles,"mapped_materials":mapped,"clips":records},"  ")+"\n")
	camera.free();body.free();print("WOODEN_TORCH checks=",checks," failures=",failures);quit(1 if failures else 0)

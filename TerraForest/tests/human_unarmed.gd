# SPDX-License-Identifier: 0BSD
extends "res://tests/pickaxe_side_strike.gd"
func run() -> void:
	var tools = preload("res://addons/player_runtime/tool_view.gd").new(); root.add_child(tools)
	tools.set_process(false); var view = tools.human; view.set_process(false); tools.equip(0)
	check(view.active_clip == "FP_Unarmed_Idle", "empty equipment selects its own relaxed hold")
	var hidden := true
	for mesh in view.meshes:
		if String(mesh.name).to_lower().replace("_", ".").begins_with("equipment."): hidden = hidden and not mesh.visible
	check(hidden, "empty hands hide all tool and weapon meshes")
	check(view._motion_clip("Walk") == "FP_Unarmed_Idle" and view._motion_clip("Jump") == "FP_Unarmed_Idle", "movement does not raise hands or trigger attacks")
	view.set_third_person(true)
	check(view._motion_clip("Walk") == "Walk" and view._motion_clip("Run") == "Run", "third-person walking and running retain their original body locomotion")
	view.set_third_person(false)
	var skeleton: Skeleton3D = view.model.find_child("Skeleton3D",true,false)
	verify_hand_mesh(view,skeleton)
	pose(view,"FP_Unarmed_Idle",0)
	var right_palm := skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).basis.z.normalized()
	var left_palm := skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).basis.z.normalized()
	var palm_symmetry := left_palm.dot(Vector3(-right_palm.x,right_palm.y,right_palm.z))
	check(palm_symmetry > .99, "neutral palms mirror each other instead of inverting the left hand")
	var idle: Array[Transform3D] = []
	for bone in skeleton.get_bone_count(): idle.append(skeleton.get_bone_pose(bone))
	var stable := {}; var fixed_error := 0.0; var seam_error := 0.0; var wrist_alignment := 1.0
	for name in ["Root","Hips","LeftFoot","RightFoot"]:
		var index := skeleton.find_bone(name); stable[index] = skeleton.get_bone_global_pose(index)
	var start := skeleton.get_bone_global_pose(skeleton.find_bone("RightHandMiddle1")).origin
	var extent := 0.0; var closed_fingers := {}; var fist_error := 0.0
	var loaded_knuckle := Vector3.ZERO; var contact_knuckle := Vector3.ZERO
	for frame in 69:
		pose(view,"FP_Unarmed_Punch",frame/60.0)
		for index: int in stable: fixed_error = maxf(fixed_error,difference(stable[index],skeleton.get_bone_global_pose(index)))
		if frame in [0,68]:
			for bone in skeleton.get_bone_count(): seam_error = maxf(seam_error,difference(idle[bone],skeleton.get_bone_pose(bone)))
		var hand := skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))
		var arm := skeleton.get_bone_global_pose(skeleton.find_bone("RightForeArm"))
		if frame >= 8 and frame <= 42: wrist_alignment = minf(wrist_alignment, hand.basis.y.normalized().dot(arm.basis.y.normalized()))
		if frame == 12: loaded_knuckle = skeleton.get_bone_global_pose(skeleton.find_bone("RightHandMiddle1")).origin
		if frame == 28:
			contact_knuckle = skeleton.get_bone_global_pose(skeleton.find_bone("RightHandMiddle1")).origin
			extent = contact_knuckle.distance_to(start)
		if frame >= 8 and frame <= 42:
			for bone in skeleton.get_bone_count():
				var name := String(skeleton.get_bone_name(bone))
				if not (name.begins_with("RightHand") or name.begins_with("LeftHand")) or name.ends_with("Hand"): continue
				if frame == 8: closed_fingers[bone] = skeleton.get_bone_pose(bone)
				else: fist_error = maxf(fist_error,difference(closed_fingers[bone],skeleton.get_bone_pose(bone)))
	check(fixed_error < .0001 and seam_error < .0001, "root and feet stay planted; punch begins and ends at neutral pose")
	check(wrist_alignment > .999 and extent > .18, "wrist stays straight through a distinct forward stroke")
	check(fist_error < .0001, "both fists stay firmly closed throughout extension, impact and withdrawal")
	var drive := contact_knuckle-loaded_knuckle
	check(absf(drive.z) > .30 and absf(drive.z) > absf(drive.y)*3, "loaded fist travels predominantly into world depth, rather than upward across the screen")
	check(absf(contact_knuckle.x)<.035 and absf(contact_knuckle.y-1.65)<.025, "striking knuckles line up with the eye-camera aim axis at contact")
	var contacts: Array = []; var ends: Array = []
	tools.attack_contact.connect(func(id: int): contacts.append([id,view.animation_player.current_animation_position,tools.contact_ready(id)]))
	tools.attack_finished.connect(func(id: int,cancelled: bool): ends.append([id,cancelled]))
	tools.equip(0)
	check(tools.begin_attack(101) and view.active_clip == "FP_Unarmed_Punch", "empty attack uses punch instead of placement")
	var contact: float = tools.attack_profile().contact
	view._process(contact-.01)
	check(contacts.is_empty() and not tools.begin_attack(102), "windup has no contact and cannot be restarted")
	view._process(.1)
	check(contacts.size() == 1 and contacts[0][0] == 101 and is_equal_approx(contacts[0][1],contact) and contacts[0][2], "contact emits once at the fist extension frame")
	view._process(1.0)
	check(contacts.size() == 1 and ends == [[101,false]] and view.active_clip == "FP_Unarmed_Idle", "recovery returns to relaxed hands without extra hits")
	tools.begin_attack(103); view._process(.1); tools.equip(1); view._process(1)
	check(contacts.size() == 1 and ends[-1] == [103,true] and view.active_clip == "FP_Pickaxe_Fresh_Idle", "tool equip cancels the punch and preserves accepted pickaxe")
	check(view.body_mesh.mesh == view.original_body_mesh, "equipping pickaxe restores the exact original body mesh and grip weights")
	tools.equip(0); tools.place(); view._process(1)
	check(view.active_clip == "FP_Unarmed_Idle" and contacts.size() == 1, "placement remains a separate gesture and returns to neutral without damage")
	check(view.body_mesh.mesh == view.unarmed_body_mesh, "returning to empty hands restores repaired finger weights")
	DirAccess.make_dir_recursive_absolute("res://reports/unarmed")
	FileAccess.open("res://reports/unarmed/runtime.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"fixed_error":fixed_error,"seam_error":seam_error,"wrist_alignment":wrist_alignment,"knuckle_travel":extent,"palm_symmetry":palm_symmetry,"fist_error":fist_error},"\t"))
	tools.free(); print("HUMAN_UNARMED checks=",checks," failures=",failures); quit(1 if failures else 0)

func verify_hand_mesh(view: Node, skeleton: Skeleton3D) -> void:
	var original: Mesh = view.original_body_mesh; var repaired: ArrayMesh = view.unarmed_body_mesh
	check(view.body_mesh.mesh == repaired and repaired != original, "empty hands select the separately repaired skin")
	var bind_names: Array[String] = []
	var skin: Skin = view.body_mesh.skin
	for i in skin.get_bind_count():
		var name := String(skin.get_bind_name(i))
		if name.is_empty(): name = String(skeleton.get_bone_name(skin.get_bind_bone(i)))
		bind_names.append(name)
	var geometry_matches := original.get_surface_count() == repaired.get_surface_count()
	var materials_match := true; var weights_valid := true; var changed := 0; var shading_error := 0.0
	for surface in original.get_surface_count():
		var before := original.surface_get_arrays(surface); var after := repaired.surface_get_arrays(surface)
		for attribute in Mesh.ARRAY_MAX:
			if attribute in [Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT]:
				# Godot repacks normals/tangents into its quantized surface format.
				geometry_matches = geometry_matches and before[attribute].size() == after[attribute].size()
				for i in before[attribute].size():
					var error: float = before[attribute][i].distance_to(after[attribute][i]) if attribute == Mesh.ARRAY_NORMAL else absf(before[attribute][i]-after[attribute][i])
					shading_error = maxf(shading_error,error)
			elif attribute not in [Mesh.ARRAY_BONES,Mesh.ARRAY_WEIGHTS]:
				geometry_matches = geometry_matches and before[attribute] == after[attribute]
		materials_match = materials_match and original.surface_get_material(surface) == repaired.surface_get_material(surface)
		var width: int = after[Mesh.ARRAY_WEIGHTS].size()/after[Mesh.ARRAY_VERTEX].size()
		for vertex in after[Mesh.ARRAY_VERTEX].size():
			var edited := false
			for slot in width:
				var at: int = vertex*width+slot
				edited = edited or before[Mesh.ARRAY_BONES][at] != after[Mesh.ARRAY_BONES][at] or absf(before[Mesh.ARRAY_WEIGHTS][at]-after[Mesh.ARRAY_WEIGHTS][at]) > .00001
			if not edited: continue
			changed += 1
			var total := 0.0; var family := ""; var side := ""; var influences := 0
			for slot in width:
				var at: int = vertex*width+slot; var weight: float = after[Mesh.ARRAY_WEIGHTS][at]
				if weight <= .000001: continue
				total += weight; influences += 1
				var name: String = bind_names[after[Mesh.ARRAY_BONES][at]]
				var hand := "LeftHand" if name.begins_with("LeftHand") else "RightHand"
				weights_valid = weights_valid and name.begins_with(hand) and (side.is_empty() or side == hand)
				side = hand
				if name == hand: continue
				var finger := name.left(-1)
				weights_valid = weights_valid and (family.is_empty() or family == finger); family = finger
			weights_valid = weights_valid and absf(total-1.0) < .0001 and influences <= 2
	print("UNARMED_SKIN shading_repack_error=",shading_error," changed_vertices=",changed)
	check(geometry_matches and materials_match and shading_error < .0002, "skin repair preserves rest geometry, topology, UVs, shading within quantization and original materials")
	check(changed > 1000 and weights_valid, "repaired hand vertices have normalized weights without pulling neighboring fingers")
	var shapes_match: bool = original.get_blend_shape_count() == repaired.get_blend_shape_count()
	for shape in original.get_blend_shape_count(): shapes_match = shapes_match and original.get_blend_shape_name(shape) == repaired.get_blend_shape_name(shape)
	check(shapes_match, "skin repair retains every original blend shape identity")

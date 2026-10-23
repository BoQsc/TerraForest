extends "res://tests/runtime_behavior_check.gd"
## Native new-pose ragdoll/self-contact regression. Uses the R4 scene explicitly.
## Tests five representative new poses plus a matched mutual-mask control.

var ragdoll_cases: Array[Dictionary] = []


func _initialize() -> void:
	output_path = "res://tests/runtime_ragdoll_validation.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
	call_deferred("run")


func _parent_body(body: PhysicalBone3D) -> PhysicalBone3D:
	var skeleton := zombie.get("skeleton") as Skeleton3D
	var bones: Dictionary = zombie.get("physical_bones")
	var parent := skeleton.get_bone_parent(body.get_bone_id())
	while parent >= 0:
		var name := String(skeleton.get_bone_name(parent))
		if bones.has(name):
			return bones[name] as PhysicalBone3D
		parent = skeleton.get_bone_parent(parent)
	return null


func _joint_anchors() -> Array[Dictionary]:
	var anchors: Array[Dictionary] = []
	var skeleton := zombie.get("skeleton") as Skeleton3D
	for body: PhysicalBone3D in (zombie.get("physical_bones") as Dictionary).values():
		var parent := _parent_body(body)
		if parent == null:
			continue
		var child_world := skeleton.global_transform * skeleton.get_bone_global_pose(body.get_bone_id()) * body.body_offset
		var parent_world := skeleton.global_transform * skeleton.get_bone_global_pose(parent.get_bone_id()) * parent.body_offset
		var anchor := child_world * body.joint_offset.origin
		anchors.append({"child": body, "parent": parent, "parent_local": parent_world.affine_inverse() * anchor})
	return anchors


func _policy(label: String) -> void:
	var bodies: Array = (zombie.get("physical_bones") as Dictionary).values()
	var invalid: Array = []
	var excluded := 0
	var enabled := 0
	for index in bodies.size():
		var a: PhysicalBone3D = bodies[index]
		if a.collision_layer != 8 or (a.collision_mask & 8) == 0:
			invalid.append({"body": String(a.name), "layer": a.collision_layer, "mask": a.collision_mask})
		for next in range(index + 1, bodies.size()):
			var b: PhysicalBone3D = bodies[next]
			var adjacent := _parent_body(a) == b or _parent_body(b) == a
			var a_excludes := a.get_collision_exceptions().has(b)
			var b_excludes := b.get_collision_exceptions().has(a)
			if a_excludes:
				excluded += 1
			if not adjacent and not a_excludes and not b_excludes:
				enabled += 1
			if a_excludes != adjacent or b_excludes != adjacent:
				invalid.append({"a": String(a.name), "b": String(b.name), "adjacent": adjacent, "a_excludes": a_excludes, "b_excludes": b_excludes})
	var expected_enabled := int((bodies.size() - 1) * (bodies.size() - 2) / 2)
	_check(label + " exempts only directly connected joint neighbors", invalid.is_empty() and excluded == bodies.size() - 1 and enabled == expected_enabled, {"bodies": bodies.size(), "excluded_pairs": excluded, "collidable_nonadjacent_pairs": enabled, "expected_nonadjacent": expected_enabled, "invalid": invalid})
	var hands: Dictionary = {}
	var compound_valid := true
	for body: PhysicalBone3D in bodies:
		if String(body.get_meta("limb_key", "")).begins_with("hand"):
			var groups: Array = body.get_meta("hand_proxy_groups", [])
			hands[String(body.name)] = groups
			compound_valid = compound_valid and groups.size() >= 6 and groups.has("Palm")
	_check(label + " keeps palm/finger grip concavity with native compound shapes", compound_valid and not hands.is_empty(), hands)


func _morph_values() -> Dictionary:
	var values: Dictionary = {}
	for source: MeshInstance3D in (zombie.get("part_meshes") as Dictionary).values():
		for index in source.mesh.get_blend_shape_count():
			values[String(source.name) + "/" + String(source.mesh.get_blend_shape_name(index))] = source.get_blend_shape_value(index)
	return values


func _pose_for(label: String) -> Dictionary:
	await _spawn("r4", Vector3(0, 0.025, -0.4) if label == "ladder_grip" else Vector3(0, 0.025, 0))
	target.position = Vector3(8, 0, 8)
	var player := zombie.get("animation_player") as AnimationPlayer
	if label == "crawl":
		zombie.call("sever_limb", "thigh_l", Vector3(-0.1, 0, 0))
		zombie.call("sever_limb", "thigh_r", Vector3(0.1, 0, 0))
		await _ticks(200)
		zombie.call("play_clip", "Zombie_Crawl")
		player.seek(0.45, true)
		player.pause()
	elif label == "ladder_grip":
		var ladder := _make_ladder()
		await _ticks(3)
		_check(label + " entered real climb", bool(zombie.call("request_climb", ladder)))
		await _ticks(260)
		player.pause()
	elif label == "jump_apex":
		_check(label + " entered real jump", bool(zombie.call("request_jump", 0.4)))
		await _ticks(130)
		player.pause()
	else:
		var clip := "Zombie_Attack_Bite" if label == "bite_contact" else "Zombie_Attack_Both"
		zombie.call("play_clip", clip)
		player.seek(0.6 if label == "bite_contact" else 0.7, true)
		player.pause()
	var skeleton := zombie.get("skeleton") as Skeleton3D
	skeleton.force_update_all_bone_transforms()
	return {"clip": String(zombie.get("_current_clip")), "animation_time": player.current_animation_position, "movement_mode": _snapshot().movement_mode, "model_offset": (zombie.get("model") as Node3D).position, "root_position": zombie.global_position, "mesh_morphs": _morph_values()}


func _sample_collapse(label: String, mutual_collision: bool = true) -> Dictionary:
	var pose := await _pose_for(label)
	var anchors := _joint_anchors()
	var bodies: Array = (zombie.get("physical_bones") as Dictionary).values()
	for body: PhysicalBone3D in bodies:
		PhysicsServer3D.body_set_max_contacts_reported(body.get_rid(), 32)
	var start := zombie.global_position
	var skeleton := zombie.get("skeleton") as Skeleton3D
	var pose_before: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		pose_before.append(skeleton.get_bone_global_pose(index))
	zombie.call("die", Vector3(0.4, 0.0, -0.8))
	var death_pose: Array = zombie.get("_death_pose")
	var saved_pose_error := 0.0
	for index in pose_before.size():
		saved_pose_error = maxf(saved_pose_error, pose_before[index].origin.distance_to((death_pose[index] as Transform3D).origin))
	var frozen_morphs := _morph_values()
	_check(label + " preserves the exact evaluated pose at death", saved_pose_error < 0.000001 and frozen_morphs == pose.mesh_morphs, {"maximum_bone_origin_error": saved_pose_error, "source_pose": pose, "mesh_morphs_preserved": frozen_morphs == pose.mesh_morphs})
	await _ticks(2)
	if mutual_collision:
		_policy(label)
	else:
		for body: PhysicalBone3D in bodies:
			body.collision_mask = 1
		await _ticks(6)
	var finite := true
	var maximum_speed := 0.0
	var maximum_angular := 0.0
	var maximum_joint_error := 0.0
	var maximum_radius := 0.0
	var minimum_y := INF
	var contact_records := 0
	var maximum_impulse := 0.0
	var contact_pairs: Dictionary = {}
	var worst_joint: Dictionary = {}
	var worst_angular: Dictionary = {}
	var worst_speed: Dictionary = {}
	for tick in 720:
		await _ticks(1)
		for body: PhysicalBone3D in bodies:
			finite = finite and body.global_transform.is_finite() and body.linear_velocity.is_finite() and body.angular_velocity.is_finite()
			if body.linear_velocity.length() > maximum_speed:
				maximum_speed = body.linear_velocity.length()
				worst_speed = {"body": String(body.name), "tick": tick, "speed_mps": maximum_speed}
			if body.angular_velocity.length() > maximum_angular:
				maximum_angular = body.angular_velocity.length()
				worst_angular = {"body": String(body.name), "tick": tick, "angular_speed_radps": maximum_angular}
			maximum_radius = maxf(maximum_radius, body.global_position.distance_to(start))
			minimum_y = minf(minimum_y, body.global_position.y)
			var direct := PhysicsServer3D.body_get_direct_state(body.get_rid())
			if direct == null:
				continue
			for contact in direct.get_contact_count():
				var other := direct.get_contact_collider_object(contact)
				if not other is PhysicalBone3D or not bodies.has(other) or _parent_body(body) == other or _parent_body(other) == body:
					continue
				var impulse := direct.get_contact_impulse(contact).length()
				var names: Array[String] = [String(body.name), String(other.name)]
				names.sort()
				var key := " / ".join(names)
				contact_pairs[key] = maxf(float(contact_pairs.get(key, 0.0)), impulse)
				contact_records += 1
				maximum_impulse = maxf(maximum_impulse, impulse)
		for anchor in anchors:
			var child: PhysicalBone3D = anchor.child
			var parent: PhysicalBone3D = anchor.parent
			var error := (child.global_transform * child.joint_offset.origin).distance_to(parent.global_transform * (anchor.parent_local as Vector3))
			if error > maximum_joint_error:
				maximum_joint_error = error
				worst_joint = {"child": String(child.name), "parent": String(parent.name), "tick": tick, "error_m": error}
	var morphs_preserved := _morph_values() == frozen_morphs
	var result := {"pose": label, "mutual_collision_enabled": mutual_collision, "ticks": 720, "seconds": 3.0, "source_pose": pose, "finite": finite, "mesh_morphs_preserved": morphs_preserved, "maximum_speed_mps": maximum_speed, "maximum_angular_speed_radps": maximum_angular, "maximum_joint_anchor_error_m": maximum_joint_error, "worst_joint": worst_joint, "worst_angular": worst_angular, "worst_speed": worst_speed, "minimum_body_y": minimum_y, "maximum_radius_from_spawn": maximum_radius, "nonadjacent_contact_records": contact_records, "maximum_nonadjacent_impulse_ns": maximum_impulse, "contact_impulses_by_pair_ns": contact_pairs}
	ragdoll_cases.append(result)
	_check(label + (" mutual masks disabled" if not mutual_collision else " native collapse") + " stays finite with attached joints", finite and morphs_preserved and maximum_speed < 35.0 and maximum_angular < 120.0 and maximum_joint_error < 0.15 and maximum_radius < 12.0 and minimum_y > -0.45, result)
	return result


func _mesh_geometry(mesh: Mesh) -> Array:
	var result: Array = []
	for surface in mesh.get_surface_count():
		result.append(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].duplicate())
	return result


func _open_head_detachment() -> void:
	await _spawn()
	target.position = Vector3(8, 0, 8)
	zombie.call("play_clip", "Zombie_Attack_Bite")
	var player := zombie.get("animation_player") as AnimationPlayer
	player.seek(0.50, true)
	player.pause()
	var head: MeshInstance3D = (zombie.get("part_meshes") as Dictionary).head
	var original_mesh: Mesh = head.mesh
	var original_geometry := _mesh_geometry(original_mesh)
	var morph_amount := head.get_blend_shape_value(0)
	var world_bake: ArrayMesh = zombie.call("_bake_cpu", head, Transform3D.IDENTITY)
	zombie.call("sever_limb", "head", Vector3.ZERO)
	var debris: Array = zombie.get("detached_parts")
	var body := debris.back() as RigidBody3D
	var detached := body.find_child("Z_Head", true, false) as MeshInstance3D
	var maximum_error := 0.0
	var matches := detached != null and detached.skin == null and detached.skeleton.is_empty() and detached.mesh != original_mesh
	if detached != null:
		for surface in world_bake.get_surface_count():
			var expected: PackedVector3Array = world_bake.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var actual: PackedVector3Array = detached.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			matches = matches and actual.size() == expected.size()
			for index in mini(actual.size(), expected.size()):
				maximum_error = maxf(maximum_error, (detached.global_transform * actual[index]).distance_to(expected[index]))
	_check("severed open mouth is an exact independent posed mesh", matches and morph_amount > 0.95 and maximum_error < 0.000005 and not bool(zombie.get("alive")), {"morph_amount": morph_amount, "maximum_world_vertex_error": maximum_error})
	var fixed_geometry := _mesh_geometry(detached.mesh) if detached != null else []
	var source_unchanged := _mesh_geometry(original_mesh) == original_geometry
	await _ticks(360)
	_check("detached mouth pose stays frozen while source mesh remains unmodified", detached != null and detached.global_transform.is_finite() and _mesh_geometry(detached.mesh) == fixed_geometry and _mesh_geometry(original_mesh) == original_geometry and source_unchanged, {"source_morph_instance_value": head.get_blend_shape_value(0), "source_mesh_sha_preserved": source_unchanged, "detached_vertex_arrays_fixed": detached != null and _mesh_geometry(detached.mesh) == fixed_geometry})


func run() -> void:
	_record_version_inputs()
	world = Node3D.new()
	root.add_child(world)
	_box(world, Vector3(0, -0.10, 0), Vector3(40, 0.20, 40))
	var total_contacts := 0
	var maximum_impulse := 0.0
	for label in ["bite_contact", "both_impact", "crawl", "ladder_grip", "jump_apex"]:
		var result := await _sample_collapse(label)
		total_contacts += int(result.nonadjacent_contact_records)
		maximum_impulse = maxf(maximum_impulse, float(result.maximum_nonadjacent_impulse_ns))
	_check("new-pose ragdolls exchange real nonadjacent collision impulses", total_contacts > 0 and maximum_impulse > 0.001, {"solver_contact_records": total_contacts, "maximum_solver_impulse_ns": maximum_impulse})
	var negative := await _sample_collapse("both_impact", false)
	_check("matched negative control produces no mutual solver contacts", int(negative.nonadjacent_contact_records) == 0 and is_zero_approx(float(negative.maximum_nonadjacent_impulse_ns)), negative)
	await _open_head_detachment()
	_check_version_inputs()
	var failures := checks.filter(func(check): return not bool(check.passed))
	var report := {"passed": failures.is_empty(), "checks": checks, "check_count": checks.size(), "failure_count": failures.size(), "physics_ticks": tick_count, "cases": ragdoll_cases, "version_inputs": version_inputs, "controller_sha256": FileAccess.get_sha256("res://scripts/zombie.gd"), "r4_glb_sha256": FileAccess.get_sha256("res://assets/Zombie.r4.glb"), "scope": "Five new R4 pose collapses, actual native body collision impulses with a matched disabled-mask control, direct-neighbor exception policy, joint-anchor stability, and exact frozen open-mouth detachment. Numeric simulation; visual deformation inspection is reported separately."}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	await _clear_subject()
	world.queue_free()
	await _ticks(3)
	print("R4_RAGDOLL_RESULT ", JSON.stringify({"passed": failures.is_empty(), "checks": checks.size(), "failures": failures.size(), "report": output_path}))
	quit(0 if failures.is_empty() else 1)

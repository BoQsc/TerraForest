extends SceneTree
## Measure signed distances to visible pads during actual controller attacks.
## Negative values are penetration; unlike the contact solver this records it.

var lab
var samples: Dictionary = {}
var contacts: Array = []
var report_path = "res://validation/r4.contact_fixture.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			report_path = arg.trim_prefix("--report=")
	lab = load("res://main.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	Engine.max_fps = 0
	if not lab.start_demo():
		quit(2)
		return
	lab.subject.attack_contact.connect(_on_contact)
	var ticks = 0
	while lab.demonstration.active and not lab.demonstration.complete and ticks < Engine.physics_ticks_per_second * 70:
		await physics_frame
		ticks += 1
		var snapshot: Dictionary = lab.subject.get_behavior_snapshot()
		var action = String(snapshot.get("active_action", ""))
		if not action in ["bite", "left", "right", "both", "crawl_bite"]:
			continue
		var stage = String(lab.demonstration.stage)
		var measurement = _measure(action)
		measurement["action_time"] = snapshot.action_time
		measurement["elapsed"] = lab.demonstration.elapsed
		if not samples.has(stage):
			samples[stage] = {"sample_count": 0, "worst": measurement}
		samples[stage].sample_count += 1
		if float(measurement.entire_part_signed_distance_m) < float(samples[stage].worst.entire_part_signed_distance_m):
			samples[stage].worst = measurement
	var checks: Array = []
	checks.append({"check": "actual demo cycle completed", "passed": lab.demonstration.complete})
	checks.append({"check": "all six actual contacts sampled", "passed": contacts.size() == 6})
	for contact in contacts:
		checks.append({"check": "%s lip or hand reaches the visible pad within 15 mm" % contact.stage, "passed": float(contact.contact_region_signed_distance_m) >= -0.015 and float(contact.contact_region_signed_distance_m) <= 0.015})
	for stage in samples:
		checks.append({"check": "%s full posed head or hand stays within 15 mm pad compression" % stage, "passed": float(samples[stage].worst.entire_part_signed_distance_m) >= -0.015})
	var failures = checks.filter(func(row): return not row.passed).size()
	var report = {
		"passed": failures == 0, "failures": failures, "check_count": checks.size(), "checks": checks,
		"native_controller": true, "sampling_hz": Engine.physics_ticks_per_second,
		"signed_distance_convention": "positive clearance, negative visible-surface penetration",
		"contacts": contacts, "attack_samples": samples,
		"source_sha256": {
			"assets/Zombie.r4.glb": FileAccess.get_sha256("res://assets/Zombie.r4.glb"),
			"scripts/zombie.gd": FileAccess.get_sha256("res://scripts/zombie.gd"),
			"scripts/zombie_demo.gd": FileAccess.get_sha256("res://scripts/zombie_demo.gd"),
			"scripts/zombie_demo_target.gd": FileAccess.get_sha256("res://scripts/zombie_demo_target.gd")
		}
	}
	var file = FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[R4 Visible Fixture] ", checks.size() - failures, "/", checks.size(), " passed | ", report_path)
	for check in checks:
		if not check.passed:
			printerr("[R4 Visible Fixture] FAIL: ", check.check)
	quit(0 if failures == 0 else 2)


func _on_contact(action: String, _damage: float, _point: Vector3) -> void:
	var row = _measure(action)
	row["action"] = action
	row["stage"] = lab.demonstration.stage
	row["elapsed"] = lab.demonstration.elapsed
	row["action_time"] = lab.subject.get_behavior_snapshot().action_time
	contacts.append(row)


func _measure(action: String) -> Dictionary:
	var zombie = lab.subject
	var target = lab.demonstration.target
	var parts: Array = ["head"] if "bite" in action else ["hand_l", "hand_r"] if action == "both" else ["hand_l"] if action == "left" else ["hand_r"]
	var entire_distance = INF
	var contact_distance = INF
	var whole_point = Vector3.ZERO
	var mouth: Dictionary = zombie.behavior_contract.get("contact_regions", {}).get("mouth", {})
	var minimum: Array = mouth.get("bind_min_godot_m", [-0.027, 1.597, 0.098])
	var maximum: Array = mouth.get("bind_max_godot_m", [0.027, 1.624, 0.122])
	zombie.skeleton.force_update_all_bone_transforms()
	for part in parts:
		var source: MeshInstance3D = zombie.part_meshes[part]
		var baked: ArrayMesh = zombie._bake_cpu(source, Transform3D.IDENTITY)
		for surface in range(baked.get_surface_count()):
			var vertices: PackedVector3Array = baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var binds: PackedVector3Array = source.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for index in range(vertices.size()):
				var distance: float = target.get_signed_contact_surface_distance(action, vertices[index])
				if distance < entire_distance:
					entire_distance = distance
					whole_point = vertices[index]
				var bind = binds[index]
				if part == "head" and (bind.x < minimum[0] or bind.y < minimum[1] or bind.z < minimum[2] or bind.x > maximum[0] or bind.y > maximum[1] or bind.z > maximum[2]):
					continue
				contact_distance = minf(contact_distance, distance)
	return {
		"contact_region_signed_distance_m": contact_distance,
		"entire_part_signed_distance_m": entire_distance,
		"entire_part_nearest_point": [whole_point.x, whole_point.y, whole_point.z],
		"target_root_distance_m": Vector2(target.global_position.x - zombie.global_position.x, target.global_position.z - zombie.global_position.z).length()
	}

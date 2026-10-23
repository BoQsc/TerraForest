extends SceneTree
## Read native evaluated contact surfaces before positioning demonstration padding.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab = load("res://main.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	Engine.max_fps = 0
	lab.select_revision("r4")
	var report = {"asset_sha256": FileAccess.get_sha256("res://assets/Zombie.r4.glb"), "actions": {}}
	for row in [{"action": "bite", "clip": "Zombie_Attack_Bite", "frame": 36, "parts": ["head"]}, {"action": "left", "clip": "Zombie_Attack_Left", "frame": 32, "parts": ["hand_l"]}, {"action": "right", "clip": "Zombie_Attack_Right", "frame": 36, "parts": ["hand_r"]}, {"action": "both", "clip": "Zombie_Attack_Both", "frame": 42, "parts": ["hand_l", "hand_r"]}, {"action": "crawl_bite", "clip": "Zombie_Crawl_Bite", "frame": 30, "parts": ["head"]}]:
		lab.select_action(row.clip)
		lab._seek_animation_frame(row.frame)
		lab.subject.skeleton.force_update_all_bone_transforms()
		var parts: Dictionary = {}
		var contact_points: Array[Vector3] = []
		var all_points: Array[Vector3] = []
		for part in row.parts:
			var points = _points(lab.subject, part, part == "head")
			contact_points.append_array(points)
			all_points.append_array(_points(lab.subject, part, false))
			parts[part] = {"contact_bounds": _bounds(points), "point_count": points.size()}
		var measurement = {"parts": parts, "frame": row.frame}
		if "bite" in row.action:
			var candidates: Array = []
			var heights = [1.36, 1.38, 1.40, 1.42, 1.44, 1.46, 1.48, 1.50] if row.action == "bite" else [0.24, 0.26, 0.28, 0.30, 0.32, 0.34, 0.36, 0.38, 0.40, 0.42, 0.44, 0.46]
			for height in heights:
				for radius in [0.08, 0.10, 0.12, 0.14, 0.16, 0.18, 0.20]:
					var lower = float(_bounds(contact_points)[1][2]) + 0.0001
					var upper = 0.90
					for iteration in range(32):
						var middle = (lower + upper) * 0.5
						var gap = _sphere_gap(contact_points, Vector3(0, height, middle), radius)
						if gap < 0.002:
							lower = middle
						else:
							upper = middle
					var at = (lower + upper) * 0.5
					candidates.append({"height": height, "radius": radius, "stand_off": at, "lip_gap": _sphere_gap(contact_points, Vector3(0, height, at), radius), "all_head_gap": _sphere_gap(all_points, Vector3(0, height, at), radius), "within_action_range": at <= (0.64 if row.action == "bite" else 0.86)})
			measurement["sphere_candidates"] = candidates
		else:
			var lower = 0.50
			var upper = 1.20
			for iteration in range(32):
				var middle = (lower + upper) * 0.5
				if _box_gap(contact_points, Vector3(0, 1.15, middle), Vector3(0.19, 0.29, 0.115)) < 0.002:
					lower = middle
				else:
					upper = middle
			var at = (lower + upper) * 0.5
			measurement["box_stand_off"] = at
			measurement["signed_surface_gap"] = _box_gap(contact_points, Vector3(0, 1.15, at), Vector3(0.19, 0.29, 0.115))
		report.actions[row.action] = measurement
	var file = FileAccess.open("res://validation/r4.contact_fixture.measure.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[R4 Fixture Measurement] complete")
	quit()


func _points(zombie, part: String, mouth_only: bool) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var source: MeshInstance3D = zombie.part_meshes[part]
	var baked: ArrayMesh = zombie._bake_cpu(source, zombie.global_transform.affine_inverse())
	var region: Dictionary = zombie.behavior_contract.get("contact_regions", {}).get("mouth", {})
	var minimum: Array = region.get("bind_min_godot_m", [-0.027, 1.597, 0.098])
	var maximum: Array = region.get("bind_max_godot_m", [0.027, 1.624, 0.122])
	for surface in range(baked.get_surface_count()):
		var vertices: PackedVector3Array = baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var binds: PackedVector3Array = source.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for index in range(vertices.size()):
			if mouth_only:
				var bind = binds[index]
				if bind.x < minimum[0] or bind.y < minimum[1] or bind.z < minimum[2] or bind.x > maximum[0] or bind.y > maximum[1] or bind.z > maximum[2]:
					continue
			points.append(vertices[index])
	return points


func _sphere_gap(points: Array[Vector3], center: Vector3, radius: float) -> float:
	var distance = INF
	for point in points:
		distance = minf(distance, point.distance_to(center) - radius)
	return distance


func _box_gap(points: Array[Vector3], center: Vector3, half_extents: Vector3) -> float:
	var distance = INF
	for point in points:
		var delta = (point - center).abs() - half_extents
		var signed = delta.max(Vector3.ZERO).length() + minf(maxf(delta.x, maxf(delta.y, delta.z)), 0.0)
		distance = minf(distance, signed)
	return distance


func _bounds(points: Array[Vector3]) -> Array:
	var minimum = Vector3(INF, INF, INF)
	var maximum = -minimum
	for point in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return [[minimum.x, minimum.y, minimum.z], [maximum.x, maximum.y, maximum.z]]

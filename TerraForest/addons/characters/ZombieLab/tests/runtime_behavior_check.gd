extends SceneTree
## Physical integration checks for the R4 behavior expansion. Native Godot only.
## Run after import: godot --headless --path . --fixed-fps 240
## --script res://tests/runtime_behavior_check.gd

class ContactTarget extends Node3D:
	var received: Array[float] = []
	var point_offset := Vector3.ZERO
	var contact_radius := 0.20
	var use_exact_shapes := true
	var hand_half_extents := Vector3(0.19, 0.29, 0.115)

	func get_zombie_attack_target_point(action: String) -> Vector3:
		var height := 1.5 if action == "bite" else 0.45 if action == "crawl_bite" else 1.15 if action == "left" else 1.25 if action == "right" else 1.35
		return global_position + Vector3.UP * height + point_offset

	func get_zombie_attack_radius() -> float:
		return contact_radius

	func get_zombie_attack_contact_shapes(action: String) -> Array:
		if not use_exact_shapes:
			return []
		if action.contains("bite"):
			return [{"type": "sphere", "transform": Transform3D(Basis.IDENTITY, get_zombie_attack_target_point(action)), "radius": 0.20}]
		return [{"type": "box", "transform": Transform3D(Basis.IDENTITY, global_position + Vector3(0, 1.15, 0) + point_offset), "half_extents": hand_half_extents}]

	func receive_zombie_attack(damage: float) -> void:
		received.append(damage)

const CONTROLLER = preload("res://scripts/zombie.gd")
const EXPECTED_ORIGINAL = "8486a5b6441f8242cdac0dc96c411cbb763c46aa6b38ae1cd458d94db891f5a0"
const EXPECTED_R2 = "7ba891bc1c72cb31a9ec4d807ea81cc10dad37d767041048da464d1e0bb6028b"
var world: Node3D
var zombie: CharacterBody3D
var target: ContactTarget
var fixtures: Node3D
var checks: Array[Dictionary] = []
var events: Array[Dictionary] = []
var action_ends: Array[String] = []
var output_path := "res://tests/runtime_behavior_validation.json"
var phase_samples: Dictionary = {}
var tick_count := 0
var version_inputs: Dictionary = {}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
	call_deferred("run")


func _ticks(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame
		tick_count += 1


func _check(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"name": label, "passed": passed, "details": details})
	print("R4_RUNTIME_CHECK ", JSON.stringify(checks.back()))


func _imported_r4_source_md5() -> String:
	var config := ConfigFile.new()
	if config.load("res://assets/Zombie.r4.glb.import") != OK:
		return ""
	var scene_path := String(config.get_value("remap", "path", ""))
	if scene_path.is_empty():
		return ""
	var hash_path := scene_path.get_basename() + ".md5"
	if not FileAccess.file_exists(hash_path):
		return ""
	for line in FileAccess.get_file_as_string(hash_path).split("\n"):
		if line.begins_with("source_md5="):
			return line.get_slice('"', 1)
	return ""


func _record_version_inputs() -> void:
	version_inputs = {"r4_glb_sha256": FileAccess.get_sha256("res://assets/Zombie.r4.glb"), "r4_glb_md5": FileAccess.get_md5("res://assets/Zombie.r4.glb"), "imported_r4_source_md5": _imported_r4_source_md5(), "controller_sha256": FileAccess.get_sha256("res://scripts/zombie.gd"), "behavior_sha256": FileAccess.get_sha256("res://assets/Zombie.r4.behavior.json")}
	_check("native R4 imported cache matches the GLB being validated", version_inputs.r4_glb_md5 == version_inputs.imported_r4_source_md5, version_inputs)


func _check_version_inputs() -> void:
	_check("model, controller and timing contract stayed unchanged throughout validation", version_inputs.r4_glb_sha256 == FileAccess.get_sha256("res://assets/Zombie.r4.glb") and version_inputs.controller_sha256 == FileAccess.get_sha256("res://scripts/zombie.gd") and version_inputs.behavior_sha256 == FileAccess.get_sha256("res://assets/Zombie.r4.behavior.json"), version_inputs)


func _box(parent: Node3D, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body


func _clear_subject() -> void:
	if is_instance_valid(zombie):
		zombie.queue_free()
	if is_instance_valid(target):
		target.queue_free()
	if is_instance_valid(fixtures):
		fixtures.queue_free()
	await _ticks(4)


func _spawn(revision: String = "r4", position: Vector3 = Vector3(0.0, 0.025, 0.0)) -> void:
	await _clear_subject()
	events.clear()
	action_ends.clear()
	fixtures = Node3D.new()
	world.add_child(fixtures)
	target = ContactTarget.new()
	target.position = Vector3(0.0, 0.0, 0.90)
	world.add_child(target)
	var target_body := StaticBody3D.new()
	target_body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.16
	shape.height = 1.65
	collision.shape = shape
	collision.position.y = 0.825
	target_body.add_child(collision)
	target.add_child(target_body)
	zombie = CharacterBody3D.new()
	zombie.set_script(CONTROLLER)
	zombie.set("revision_id", revision)
	var path := "res://assets/Zombie.glb" if revision == "original" else "res://assets/Zombie." + revision + ".glb"
	zombie.set("model_path", path)
	zombie.set("model_scene", load(path))
	zombie.set("walk_reference_speed", 0.72 if revision == "r4" else 0.0)
	zombie.position = position
	world.add_child(zombie)
	zombie.set("target", target)
	zombie.connect("attack_contact", _contact)
	zombie.connect("attack_missed", _miss)
	zombie.connect("action_finished", _action_end)
	await _ticks(26)


func _contact(action: String, damage: float, point: Vector3) -> void:
	var snapshot: Dictionary = zombie.call("get_behavior_snapshot")
	events.append({"action": action, "landed": true, "damage": damage, "point": [point.x, point.y, point.z], "action_time": snapshot.action_time, "animation_time": snapshot.animation_time, "surface_distance": snapshot.last_contact.surface_distance, "target_distance": snapshot.target_distance})


func _miss(action: String, reason: String) -> void:
	var snapshot: Dictionary = zombie.call("get_behavior_snapshot")
	events.append({"action": action, "landed": false, "reason": reason, "action_time": snapshot.action_time, "animation_time": snapshot.animation_time, "surface_gap": snapshot.last_contact.get("surface_gap", -1.0), "target_distance": snapshot.target_distance, "learned_contact_distance": snapshot.learned_contact_distance})


func _action_end(action: String) -> void:
	action_ends.append(action)


func _snapshot() -> Dictionary:
	return zombie.call("get_behavior_snapshot")


func _run_attack(action: String, distance: float) -> void:
	await _spawn()
	target.position.z = distance
	var accepted := bool(zombie.call("request_attack", action))
	await _ticks(430)
	var contacts := events.filter(func(event): return bool(event.landed))
	var contract: Dictionary = zombie.get("behavior_contract")
	var clip: String = zombie.R4_ATTACKS[action].clip
	var expected_time := float(contract.actions[clip].contact_time_seconds)
	_check(action + " actual animated contact and full recovery", accepted and contacts.size() == 1 and target.received.size() == 1 and action_ends.has(action) and String(_snapshot().active_action).is_empty(), {"accepted": accepted, "events": events.duplicate(true), "finished": action_ends.duplicate(), "snapshot": _snapshot()})
	if contacts.size() == 1:
		_check(action + " marker matches pose within one physics tick", absf(float(contacts[0].action_time) - expected_time) <= 1.0 / 240.0 + 0.0001 and absf(float(contacts[0].animation_time) - expected_time) <= 1.0 / 240.0 + 0.0001, {"expected": expected_time, "event": contacts[0]})


func _attack_rejection_checks() -> void:
	await _spawn()
	target.position.z = 2.0
	_check("out-of-range attack request rejected", not bool(zombie.call("request_attack", "right")))
	target.position.z = 0.90
	var started := bool(zombie.call("request_attack", "right"))
	await _ticks(65)
	target.position.z = 2.4
	await _ticks(330)
	_check("target can evade a committed attack", started and events.size() == 1 and not bool(events[0].landed) and target.received.is_empty(), {"events": events.duplicate(true)})
	await _spawn()
	target.position.z = -0.90
	started = bool(zombie.call("request_attack", "right"))
	await _ticks(390)
	_check("target outside strike arc is not hit", started and target.received.is_empty(), {"events": events.duplicate(true)})
	await _spawn()
	target.point_offset.y = 1.6
	started = bool(zombie.call("request_attack", "right"))
	await _ticks(390)
	_check("target above animated reach is not hit", started and target.received.is_empty(), {"events": events.duplicate(true)})
	await _spawn()
	_box(fixtures, Vector3(0, 0.90, 0.45), Vector3(1.8, 1.8, 0.05))
	await _ticks(2)
	started = bool(zombie.call("request_attack", "right"))
	await _ticks(390)
	_check("solid wall blocks damage even when animated hand crosses it", started and target.received.is_empty(), {"events": events.duplicate(true)})
	await _spawn()
	started = bool(zombie.call("request_attack", "left"))
	await _ticks(45)
	zombie.call("sever_limb", "forearm_l", Vector3(-0.4, 0.1, 0.0))
	await _ticks(360)
	var available: Array = zombie.call("get_available_attacks")
	_check("severing striking arm cancels contact and removes unavailable choices", started and target.received.is_empty() and not available.has("left") and not available.has("both") and available.has("right") and available.has("bite"), {"events": events.duplicate(true), "available": available})
	await _spawn()
	target.position.z = 0.62
	zombie.call("set_behavior", true)
	await _ticks(2100)
	var sequence: Array[String] = []
	for event in events:
		sequence.append(String(event.action))
	var no_repeat := sequence.size() >= 4
	for index in range(1, sequence.size()):
		no_repeat = no_repeat and sequence[index] != sequence[index - 1]
	for action in ["bite", "left", "right", "both"]:
		no_repeat = no_repeat and sequence.has(action)
	_check("autonomous close-range choices vary without immediate repeats", no_repeat, {"sequence": sequence})
	await _spawn()
	target.position.z = 1.50
	# The final authored hands reach the ordinary 23cm-deep torso at the
	# default stand-off. A real 4cm pad leaves an initial geometric gap, so
	# this regression still exercises a miss, physical approach and retry.
	target.hand_half_extents.z = 0.02
	zombie.call("set_behavior", true)
	await _ticks(2200)
	_check("pursuit closes after a real thin-surface miss and then lands contacts", int(_snapshot().miss_count) >= 1 and int(_snapshot().contact_count) >= 2 and float(_snapshot().learned_contact_distance) < 0.94 and _snapshot().target_distance < 0.94, {"events": events.duplicate(true), "snapshot": _snapshot(), "target_contact_box_size_m": [target.hand_half_extents.x * 2.0, target.hand_half_extents.y * 2.0, target.hand_half_extents.z * 2.0], "target_movement_capsule_radius_m": 0.16})


func _crawl_checks() -> void:
	await _spawn()
	target.position.z = 3.0
	zombie.call("set_behavior", true)
	zombie.call("sever_limb", "thigh_l", Vector3(-0.3, 0.05, 0))
	await _ticks(205)
	_check("one leg loss survives and completes down transition", bool(zombie.get("alive")) and bool(_snapshot().crawling) and action_ends.has("to_crawl") and (zombie.get("capsule") as CollisionShape3D).rotation.x > 1.5, {"snapshot": _snapshot()})
	var start := zombie.global_position
	await _ticks(240)
	_check("one-leg crawler physically pursues target", zombie.global_position.z - start.z > 0.22, {"distance": zombie.global_position.distance_to(start), "snapshot": _snapshot()})
	zombie.call("sever_limb", "thigh_r", Vector3(0.3, 0.05, 0))
	await _ticks(10)
	_check("second leg loss remains alive and prone", bool(zombie.get("alive")) and bool(_snapshot().crawling), {"snapshot": _snapshot()})
	zombie.call("receive_hit", "torso", 2.0, zombie.global_position, Vector3.ZERO)
	await _ticks(15)
	_check("crawl hit stays in prone hit animation", String(_snapshot().clip).ends_with("Zombie_Crawl_Hit") and bool(_snapshot().crawling))
	await _ticks(140)
	zombie.call("set_behavior", false)
	zombie.rotation.y = 0.0
	target.global_position = zombie.global_position + Vector3(0, -zombie.global_position.y, 0.73)
	events.clear()
	target.received.clear()
	var accepted := bool(zombie.call("request_attack", "bite"))
	await _ticks(320)
	_check("prone bite uses low real contact", accepted and target.received.size() == 1 and String(events[0].action) == "crawl_bite", {"events": events.duplicate(true), "snapshot": _snapshot()})
	_check("missing legs reject jumping and ladder", not bool(zombie.call("request_jump")) and not bool(zombie.call("request_climb", {})))
	zombie.call("sever_limb", "upper_arm_l", Vector3(-0.2, 0, 0))
	zombie.call("sever_limb", "upper_arm_r", Vector3(0.2, 0, 0))
	target.position.z += 2.0
	zombie.call("set_behavior", true)
	await _ticks(30)
	start = zombie.global_position
	await _ticks(240)
	_check("crawler without arms cannot propel itself but retains bite", bool(zombie.get("alive")) and zombie.global_position.distance_to(start) < 0.025 and is_zero_approx(float(_snapshot().crawl_speed)) and (zombie.call("get_available_attacks") as Array).has("crawl_bite"), {"drift": zombie.global_position.distance_to(start), "snapshot": _snapshot()})


func _crawl_inspection_checks() -> void:
	await _spawn()
	zombie.call("sever_limb", "thigh_l", Vector3(-0.1, 0, 0))
	await _ticks(72)
	var player := zombie.get("animation_player") as AnimationPlayer
	var capsule := zombie.get("capsule") as CollisionShape3D
	zombie.call("set_behavior", false)
	zombie.call("play_clip", "Zombie_To_Crawl")
	player.pause()
	player.seek(0.3, true)
	await _ticks(2)
	var held_capsule := capsule.transform
	var held_pose := (zombie.get("skeleton") as Skeleton3D).get_bone_global_pose(0)
	await _ticks(250)
	var pose := (zombie.get("skeleton") as Skeleton3D).get_bone_global_pose(0)
	_check("pause during the live drop holds its exact pose and capsule beyond clip duration", bool(_snapshot().crawl_transition) and absf(float(_snapshot().action_time) - 0.3) < 0.000001 and absf(float(_snapshot().animation_time) - 0.3) < 0.000001 and capsule.transform.is_equal_approx(held_capsule) and pose.is_equal_approx(held_pose), {"snapshot": _snapshot(), "capsule_transform": capsule.transform})
	player.seek(0.5, true)
	await _ticks(3)
	_check("seeking the paused drop keeps collider and pose cursor synchronized", bool(_snapshot().crawl_transition) and absf(float(_snapshot().action_time) - 0.5) < 0.000001 and capsule.rotation.x > held_capsule.basis.get_euler().x, {"snapshot": _snapshot(), "capsule_rotation": capsule.rotation})
	player.play()
	await _ticks(90)
	_check("resuming the paused drop completes normal prone conversion", bool(_snapshot().crawling) and not bool(_snapshot().crawl_transition) and action_ends.has("to_crawl"), {"snapshot": _snapshot()})
	await _spawn()
	zombie.call("sever_limb", "thigh_l", Vector3(-0.1, 0, 0))
	await _ticks(60)
	zombie.call("set_behavior", false)
	zombie.call("play_clip", "Zombie_Walk")
	await _ticks(3)
	_check("selecting another action during the drop chooses a valid prone preview", bool(_snapshot().crawling) and not bool(_snapshot().crawl_transition) and String(_snapshot().clip).ends_with("Zombie_Crawl") and String(_snapshot().state) == "preview", {"snapshot": _snapshot()})


func _jump_checks() -> void:
	await _spawn()
	target.position = Vector3(5, 0, 5)
	_box(fixtures, Vector3(0, 0.05, 0.32), Vector3(1.2, 0.10, 0.06))
	await _ticks(2)
	var start := zombie.global_position
	var accepted := bool(zombie.call("request_jump", 1.4))
	var peak := start.y
	var min_model_y := 0.0
	var trajectory: Array[Dictionary] = []
	for tick in 370:
		await _ticks(1)
		peak = maxf(peak, zombie.global_position.y)
		min_model_y = minf(min_model_y, (zombie.get("model") as Node3D).position.y)
		if tick % 12 == 0:
			trajectory.append({"tick": tick, "y": zombie.global_position.y, "z": zombie.global_position.z, "model_y": (zombie.get("model") as Node3D).position.y, "phase": _snapshot().traversal_state})
	_check("short hop clears real 10cm obstacle and recovers", accepted and action_ends.has("jump") and String(_snapshot().traversal_state) == "none" and zombie.global_position.z > 0.50 and zombie.is_on_floor(), {"accepted": accepted, "start": start, "end": zombie.global_position, "peak_m": peak - start.y, "trajectory": trajectory})
	_check("physics hop uses one 18cm elevation, not doubled authored height", peak - start.y > 0.16 and peak - start.y < 0.205 and min_model_y < -0.16 and absf((zombie.get("model") as Node3D).position.y) < 0.0001, {"physical_peak": peak - start.y, "lowest_model_offset": min_model_y})
	phase_samples.jump = trajectory


func _make_ladder() -> Dictionary:
	_box(fixtures, Vector3(1.10, 0.45, -0.45), Vector3(1.50, 0.90, 1.10))
	for side in [-1.0, 1.0]:
		_box(fixtures, Vector3(side * 0.37, 1.525, 0.0), Vector3(0.045, 3.05, 0.07))
	for rung in range(1, 10):
		_box(fixtures, Vector3(0, rung * 0.30, 0), Vector3(0.78, 0.036, 0.040))
	return {"base": Vector3.ZERO, "facing": Vector3(0, 0, 1), "height": 0.90, "exit": Vector3(0.85, 0.925, -0.45), "rung_pitch": 0.30}


func _ladder_checks() -> void:
	await _spawn("r4", Vector3(0, 0.025, -0.4))
	target.position = Vector3(4, 0, 4)
	var ladder := _make_ladder()
	await _ticks(3)
	var accepted := bool(zombie.call("request_climb", ladder))
	var maximum := zombie.global_position.y
	var phases: Array[String] = []
	for tick in 1350:
		await _ticks(1)
		maximum = maxf(maximum, zombie.global_position.y)
		var phase := String(_snapshot().traversal_state)
		if not phases.has(phase):
			phases.append(phase)
	_check("ladder climbs physical rungs and exits on real platform", accepted and action_ends.has("climb") and zombie.global_position.distance_to(Vector3(0.85, 0.90, -0.45)) < 0.10 and zombie.is_on_floor() and phases.has("ladder_climb") and phases.has("ladder_exit"), {"accepted": accepted, "maximum_y": maximum, "end": zombie.global_position, "phases": phases, "snapshot": _snapshot()})
	await _spawn("r4", Vector3(0, 0.025, -0.4))
	target.position = Vector3(4, 0, 4)
	ladder = _make_ladder()
	await _ticks(3)
	accepted = bool(zombie.call("request_climb", ladder))
	await _ticks(250)
	var before := zombie.global_position.y
	zombie.call("sever_limb", "hand_l", Vector3(-0.1, 0, 0))
	await _ticks(240)
	_check("losing ladder grip releases climb and real gravity takes over", accepted and before > 0.12 and String(_snapshot().traversal_state) == "none" and zombie.global_position.y < before - 0.10 and bool(zombie.get("alive")), {"height_before": before, "height_after": zombie.global_position.y, "snapshot": _snapshot()})


func _original_checks() -> void:
	_check("Original GLB remains byte-identical", FileAccess.get_sha256("res://assets/Zombie.glb") == EXPECTED_ORIGINAL)
	_check("R2 GLB remains byte-identical", FileAccess.get_sha256("res://assets/Zombie.r2.glb") == EXPECTED_R2)
	for revision in ["original", "r2"]:
		await _spawn(revision)
		_check(revision + " retains legacy action path", not bool(_snapshot().r4_actions_enabled) and (zombie.call("get_available_attacks") as Array).is_empty() and not bool(zombie.call("request_jump")))
		zombie.call("sever_limb", "thigh_l", Vector3(0.1, 0.1, 0))
		await _ticks(20)
		_check(revision + " retains original leg-loss ragdoll behavior", not bool(zombie.get("alive")) and String(zombie.get("state")) == "ragdoll")


func _mouth_bake_check() -> void:
	await _spawn()
	var head: MeshInstance3D = (zombie.get("part_meshes") as Dictionary).head
	var count: int = head.mesh.get_blend_shape_count()
	if count == 0:
		_check("BiteOpen exists for pose-preserving sever bake", false)
		return
	var player := zombie.get("animation_player") as AnimationPlayer
	zombie.call("play_clip", "Zombie_Attack_Bite")
	player.seek(0.5, true)
	player.pause()
	_check("paused inspector snapshot retains the evaluated frame", absf(float(_snapshot().animation_time) - 0.5) < 0.000001)
	var amount := head.get_blend_shape_value(0)
	var open: ArrayMesh = zombie.call("_bake_cpu", head, Transform3D.IDENTITY)
	head.set_blend_shape_value(0, 0.0)
	var closed: ArrayMesh = zombie.call("_bake_cpu", head, Transform3D.IDENTITY)
	var largest := 0.0
	for surface in open.get_surface_count():
		var open_vertices: PackedVector3Array = open.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var closed_vertices: PackedVector3Array = closed.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for index in open_vertices.size():
			largest = maxf(largest, open_vertices[index].distance_to(closed_vertices[index]))
	head.set_blend_shape_value(0, amount)
	_check("CPU sever/contact bake includes the animated mouth morph", amount > 0.1 and largest > 0.005, {"blend_shape": String(head.mesh.get_blend_shape_name(0)), "amount": amount, "maximum_pose_difference": largest})


func _corrective_bake_checks() -> void:
	await _spawn()
	var parts: Dictionary = zombie.get("part_meshes")
	var player := zombie.get("animation_player") as AnimationPlayer
	var skeleton := zombie.get("skeleton") as Skeleton3D
	var corrective_parts: Dictionary = {}
	var expected_shapes := {"thigh_l": "BendRelief", "thigh_r": "BendRelief", "shin_l": "BendRelief", "shin_r": "BendRelief", "torso": "SlamDrape"}
	for key: String in expected_shapes:
		var source: MeshInstance3D = parts[key]
		var blend_index := -1
		for index in source.mesh.get_blend_shape_count():
			if String(source.mesh.get_blend_shape_name(index)) == String(expected_shapes[key]):
				blend_index = index
		if blend_index >= 0:
			corrective_parts[key] = {"mesh": source, "blend_index": blend_index, "maximum": 0.0, "clip": "", "frame": 0}
	_check("all five corrected leg and torso meshes include their authored morphs", corrective_parts.size() == expected_shapes.size(), {"parts": corrective_parts.keys(), "expected_shapes": expected_shapes})
	if corrective_parts.size() != expected_shapes.size():
		return
	for clip in ["Zombie_To_Crawl", "Zombie_Climb_Ladder", "Zombie_Attack_Both"]:
		zombie.call("play_clip", clip)
		player.pause()
		var duration := player.get_animation(player.assigned_animation).length
		for frame in range(roundi(duration * 60.0) + 1):
			player.seek(minf(frame / 60.0, duration), true)
			for key: String in corrective_parts:
				var info: Dictionary = corrective_parts[key]
				var source := info.mesh as MeshInstance3D
				var amount := source.get_blend_shape_value(int(info.blend_index))
				if amount > float(info.maximum):
					info.maximum = amount
					info.clip = clip
					info.frame = frame
	for key: String in corrective_parts:
		var info: Dictionary = corrective_parts[key]
		var source := info.mesh as MeshInstance3D
		if String(info.clip).is_empty():
			_check(key + " corrective reaches an authored nonzero pose", false)
			continue
		zombie.call("play_clip", String(info.clip))
		player.seek(float(info.frame) / 60.0, true)
		player.pause()
		skeleton.force_update_all_bone_transforms()
		var amount := source.get_blend_shape_value(int(info.blend_index))
		var original_geometry: Array = []
		for surface in source.mesh.get_surface_count():
			original_geometry.append(source.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].duplicate())
		var corrected: ArrayMesh = zombie.call("_bake_cpu", source, Transform3D.IDENTITY)
		source.set_blend_shape_value(int(info.blend_index), 0.0)
		var uncorrected: ArrayMesh = zombie.call("_bake_cpu", source, Transform3D.IDENTITY)
		source.set_blend_shape_value(int(info.blend_index), amount)
		var maximum_difference := 0.0
		var finite := true
		var source_unchanged := true
		for surface in corrected.get_surface_count():
			var current: PackedVector3Array = corrected.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var plain: PackedVector3Array = uncorrected.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			source_unchanged = source_unchanged and source.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] == original_geometry[surface]
			for index in current.size():
				maximum_difference = maxf(maximum_difference, current[index].distance_to(plain[index]))
				finite = finite and current[index].is_finite() and plain[index].is_finite()
		_check(key + " CPU freeze bake retains its live corrective without changing the source", amount > 0.01 and maximum_difference > 0.0005 and finite and source_unchanged, {"clip": info.clip, "frame": info.frame, "shape_key": expected_shapes[key], "morph_amount": amount, "maximum_world_vertex_difference_m": maximum_difference, "finite": finite, "source_unchanged": source_unchanged})


func _test_vertex_arrays(mesh: Mesh) -> Array:
	var result: Array = []
	for surface in mesh.get_surface_count():
		result.append(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].duplicate())
	return result


func _test_mesh_difference(first: Mesh, second: Mesh) -> float:
	if first.get_surface_count() != second.get_surface_count():
		return INF
	var maximum := 0.0
	for surface in first.get_surface_count():
		var a: PackedVector3Array = first.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var b: PackedVector3Array = second.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		if a.size() != b.size():
			return INF
		for index in a.size():
			if not a[index].is_finite() or not b[index].is_finite():
				return INF
			maximum = maxf(maximum, a[index].distance_to(b[index]))
	return maximum


func _torso_multishape_bake_check() -> void:
	await _spawn()
	var source: MeshInstance3D = (zombie.get("part_meshes") as Dictionary).torso
	var player := zombie.get("animation_player") as AnimationPlayer
	var skeleton := zombie.get("skeleton") as Skeleton3D
	var keys: Dictionary = {}
	for index in source.mesh.get_blend_shape_count():
		keys[String(source.mesh.get_blend_shape_name(index))] = index
	var has_keys := keys.has("SlamDrape") and keys.has("LeftDrape")
	_check("torso imports both named cloth correctives on one mesh", has_keys, {"shape_indices": keys})
	if not has_keys:
		return
	var slam_index := int(keys.SlamDrape)
	var left_index := int(keys.LeftDrape)
	var original_vertices := _test_vertex_arrays(source.mesh)
	var maximum_amount := 0.0
	var maximum_frame := -1
	zombie.call("play_clip", "Zombie_Attack_Left")
	player.pause()
	var duration := player.get_animation(player.assigned_animation).length
	for frame in range(roundi(duration * 60.0) + 1):
		player.seek(minf(frame / 60.0, duration), true)
		var amount := source.get_blend_shape_value(left_index)
		if amount > maximum_amount:
			maximum_amount = amount
			maximum_frame = frame
	if maximum_frame < 0:
		_check("LeftDrape reaches its authored nonzero pose", false)
		return
	player.seek(maximum_frame / 60.0, true)
	skeleton.force_update_all_bone_transforms()
	var slam_during_left := source.get_blend_shape_value(slam_index)
	var left_live: ArrayMesh = zombie.call("_bake_cpu", source, Transform3D.IDENTITY)
	source.set_blend_shape_value(left_index, 0.0)
	var left_plain: ArrayMesh = zombie.call("_bake_cpu", source, Transform3D.IDENTITY)
	var left_difference := _test_mesh_difference(left_live, left_plain)
	source.set_blend_shape_value(left_index, maximum_amount)
	_check("Left attack uses its second torso key in the posed CPU bake", maximum_amount > 0.1 and absf(slam_during_left) < 0.000001 and left_difference > 0.0001 and is_finite(left_difference), {"frame": maximum_frame, "LeftDrape": maximum_amount, "SlamDrape": slam_during_left, "maximum_world_vertex_difference_m": left_difference})

	# Both keys can share a mesh without overwriting one another. This bounded
	# algebra check uses the actual imported deltas at one fixed authored pose.
	source.set_blend_shape_value(slam_index, 0.0)
	source.set_blend_shape_value(left_index, 0.0)
	var base: ArrayMesh = zombie.call("_bake_cpu", source, Transform3D.IDENTITY)
	source.set_blend_shape_value(slam_index, 1.0)
	var slam: ArrayMesh = zombie.call("_bake_cpu", source, Transform3D.IDENTITY)
	source.set_blend_shape_value(slam_index, 0.0)
	source.set_blend_shape_value(left_index, 1.0)
	var left: ArrayMesh = zombie.call("_bake_cpu", source, Transform3D.IDENTITY)
	source.set_blend_shape_value(slam_index, 0.65)
	source.set_blend_shape_value(left_index, 0.80)
	var combined: ArrayMesh = zombie.call("_bake_cpu", source, Transform3D.IDENTITY)
	var additive_error := 0.0
	for surface in base.get_surface_count():
		var plain: PackedVector3Array = base.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var slam_vertices: PackedVector3Array = slam.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var left_vertices: PackedVector3Array = left.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var actual: PackedVector3Array = combined.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for index in plain.size():
			var expected := plain[index] + 0.65 * (slam_vertices[index] - plain[index]) + 0.80 * (left_vertices[index] - plain[index])
			additive_error = maxf(additive_error, expected.distance_to(actual[index]))
	_check("two torso morphs accumulate before skinning without replacing each other", additive_error < 0.000002 and _test_vertex_arrays(source.mesh) == original_vertices, {"SlamDrape": 0.65, "LeftDrape": 0.80, "maximum_additive_error_m": additive_error, "source_vertices_unchanged": _test_vertex_arrays(source.mesh) == original_vertices})

	var action_values: Dictionary = {}
	var independent_actions := true
	for clip in ["Zombie_Attack_Both", "Zombie_Attack_Left", "Zombie_Idle", "Zombie_Walk", "Zombie_Attack", "Zombie_Hit"]:
		zombie.call("play_clip", clip)
		player.pause()
		player.seek(0.7 if clip == "Zombie_Attack_Both" else maximum_frame / 60.0 if clip == "Zombie_Attack_Left" else 0.1, true)
		var slam_amount := source.get_blend_shape_value(slam_index)
		var left_amount := source.get_blend_shape_value(left_index)
		action_values[clip] = {"SlamDrape": slam_amount, "LeftDrape": left_amount}
		if clip == "Zombie_Attack_Both":
			independent_actions = independent_actions and slam_amount > 0.1 and absf(left_amount) < 0.000001
		elif clip == "Zombie_Attack_Left":
			independent_actions = independent_actions and left_amount > 0.1 and absf(slam_amount) < 0.000001
		else:
			independent_actions = independent_actions and absf(slam_amount) < 0.000001 and absf(left_amount) < 0.000001
	_check("torso morph tracks reset across attacks and preserved base clips", independent_actions, action_values)

	zombie.call("play_clip", "Zombie_Attack_Left")
	player.seek(maximum_frame / 60.0, true)
	player.pause()
	skeleton.force_update_all_bone_transforms()
	var before_death: ArrayMesh = zombie.call("_bake_cpu", source, Transform3D.IDENTITY)
	var live_amount := source.get_blend_shape_value(left_index)
	zombie.call("die", Vector3.ZERO)
	var frozen: ArrayMesh = zombie.call("_bake_cpu", source, Transform3D.IDENTITY)
	var freeze_error := _test_mesh_difference(before_death, frozen)
	await _ticks(60)
	_check("Left torso corrective survives pose freeze and actual ragdoll simulation", freeze_error < 0.000005 and absf(source.get_blend_shape_value(left_index) - live_amount) < 0.000001 and absf(source.get_blend_shape_value(slam_index)) < 0.000001 and _test_vertex_arrays(source.mesh) == original_vertices and source.global_transform.is_finite(), {"frame": maximum_frame, "LeftDrape": live_amount, "maximum_world_vertex_error_at_death_m": freeze_error, "source_vertices_unchanged": _test_vertex_arrays(source.mesh) == original_vertices, "physics_seconds_after_freeze": 60.0 / Engine.physics_ticks_per_second})


func run() -> void:
	_record_version_inputs()
	world = Node3D.new()
	root.add_child(world)
	_box(world, Vector3(0, -0.10, 0), Vector3(40, 0.20, 40))
	await _spawn()
	var enabled := bool(_snapshot().r4_actions_enabled)
	_check("complete R4 behavior contract and imported clips loaded", enabled, {"snapshot": _snapshot(), "glb_sha256": FileAccess.get_sha256("res://assets/Zombie.r4.glb")})
	if enabled:
		for action in ["bite", "left", "right", "both"]:
			await _run_attack(action, 0.56 if action == "bite" else 0.90)
		await _attack_rejection_checks()
		await _crawl_checks()
		await _crawl_inspection_checks()
		await _jump_checks()
		await _ladder_checks()
		await _mouth_bake_check()
		await _corrective_bake_checks()
		await _torso_multishape_bake_check()
	await _original_checks()
	_check_version_inputs()
	var failures := checks.filter(func(check): return not bool(check.passed))
	var report := {"passed": failures.is_empty(), "checks": checks, "check_count": checks.size(), "failure_count": failures.size(), "physics_ticks": tick_count, "physics_fps": Engine.physics_ticks_per_second, "controller_sha256": FileAccess.get_sha256("res://scripts/zombie.gd"), "r4_glb_sha256": FileAccess.get_sha256("res://assets/Zombie.r4.glb"), "behavior_contract_sha256": FileAccess.get_sha256("res://assets/Zombie.r4.behavior.json"), "version_inputs": version_inputs, "phase_samples": phase_samples, "scope": "Native controller, marker contacts, limb decisions, physical hop and ladder traversal. Separate Blender/native visual reviews validate deformation and appearance."}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	await _clear_subject()
	world.queue_free()
	await _ticks(3)
	print("R4_RUNTIME_RESULT ", JSON.stringify({"passed": failures.is_empty(), "checks": checks.size(), "failures": failures.size(), "report": output_path}))
	quit(0 if failures.is_empty() else 1)

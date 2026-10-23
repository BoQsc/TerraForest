extends SceneTree
## Native integration regression for preserved, complete zombie revisions.
## Uses bundled Godot APIs only. Start after the project's normal import:
## godot --headless --path . --script res://tests/revision_selection_check.gd --fixed-fps 240
## Optional: -- --output=/absolute/path/revision_selection_validation.json

const MANIFEST = "res://assets/zombie.revisions.json"
const CLIPS = ["Zombie_Idle", "Zombie_Walk", "Zombie_Attack", "Zombie_Hit"]
const IDS = ["original", "r4", "r2", "r3"]
const EXPECTED_FRAMES = {"original": 412, "r2": 412, "r3": 400, "r4": 400}
const ARM_BONES = ["LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]

var lab: Node3D
var profiles: Dictionary = {}
var checks: Array[Dictionary] = []
var models: Dictionary = {}
var animation_checks: Dictionary = {}
var gameplay_checks: Dictionary = {}
var contact_checks: Dictionary = {}
var source_hashes: Dictionary = {}
var output_path = "res://tests/revision_selection_validation.json"
var attack_events: Array[Dictionary] = []
var captured_zombie: Node3D
var total_animation_frames = 0
var total_bone_samples = 0
var total_contact_ticks = 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
	call_deferred("run")


func _ticks(count: int) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame


func _check(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"name": label, "passed": passed, "details": details})
	if not passed:
		print("REVISION_SELECTOR_CHECK_FAILED ", JSON.stringify(checks.back()))


func _remember(path: String) -> void:
	source_hashes[path.trim_prefix("res://")] = FileAccess.get_sha256(path)


func _clip_key(player: AnimationPlayer, clip: String) -> String:
	for key in player.get_animation_list():
		if String(key).get_file() == clip:
			return String(key)
	return ""


func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _transform(value: Transform3D) -> Array:
	return [value.basis.x.x, value.basis.x.y, value.basis.x.z,
		value.basis.y.x, value.basis.y.y, value.basis.y.z,
		value.basis.z.x, value.basis.z.y, value.basis.z.z,
		value.origin.x, value.origin.y, value.origin.z]


func _all_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		output.append(node)
	for child in node.get_children():
		_all_meshes(child, output)


func _imported_md5(model_path: String) -> String:
	var config = ConfigFile.new()
	if config.load(model_path + ".import") != OK:
		return ""
	var scene_path = String(config.get_value("remap", "path", ""))
	var hash_path = scene_path.get_basename() + ".md5"
	if not FileAccess.file_exists(hash_path):
		return ""
	for line in FileAccess.get_file_as_string(hash_path).split("\n"):
		if line.begins_with("source_md5="):
			return line.get_slice('"', 1)
	return ""


func _profile_id() -> String:
	return String(lab.call("get_selected_revision"))


func _fresh(id: String) -> Node3D:
	if _profile_id() == id:
		lab.call("_spawn_subject")
	else:
		lab.call("select_revision", id)
	var zombie: Node3D = lab.get("subject")
	lab.set("behavior_on", false)
	zombie.call("set_behavior", false)
	lab.call("_select_clip", 0)
	await _ticks(2)
	return zombie


func _model_check(id: String) -> void:
	var profile: Dictionary = profiles[id]
	var zombie: Node3D = lab.get("subject")
	var model: Node3D = zombie.get("model")
	var skeleton: Skeleton3D = zombie.get("skeleton")
	var player: AnimationPlayer = zombie.get("animation_player")
	var scene: PackedScene = zombie.get("model_scene")
	var actual_hash = FileAccess.get_sha256(String(profile.model_path))
	var actual_md5 = FileAccess.get_md5(String(profile.model_path))
	var imported_md5 = _imported_md5(String(profile.model_path))
	var mesh_nodes: Array[MeshInstance3D] = []
	_all_meshes(model, mesh_nodes)
	var triangle_count = 0
	var inverse_bind_rows: Array = []
	for mesh_node in mesh_nodes:
		for surface in range(mesh_node.mesh.get_surface_count()):
			var arrays = mesh_node.mesh.surface_get_arrays(surface)
			var indices = arrays[Mesh.ARRAY_INDEX]
			triangle_count += int(indices.size() / 3) if indices != null and indices.size() > 0 else int(arrays[Mesh.ARRAY_VERTEX].size() / 3)
		if mesh_node.skin != null:
			for bind in range(mesh_node.skin.get_bind_count()):
				inverse_bind_rows.append([String(mesh_node.name), String(mesh_node.skin.get_bind_name(bind)),
					mesh_node.skin.get_bind_bone(bind), _transform(mesh_node.skin.get_bind_pose(bind))])
	var rest_rows: Array = []
	for index in range(skeleton.get_bone_count()):
		rest_rows.append([String(skeleton.get_bone_name(index)), skeleton.get_bone_parent(index),
			_transform(skeleton.get_bone_rest(index))])
	var arm_lengths: Dictionary = {}
	for side in ["Left", "Right"]:
		var shoulder = skeleton.get_bone_global_rest(skeleton.find_bone(side + "Arm")).origin
		var elbow = skeleton.get_bone_global_rest(skeleton.find_bone(side + "ForeArm")).origin
		var wrist = skeleton.get_bone_global_rest(skeleton.find_bone(side + "Hand")).origin
		arm_lengths[side] = {"upper_arm_m": shoulder.distance_to(elbow), "forearm_m": elbow.distance_to(wrist)}
	var lengths: Dictionary = {}
	for clip in CLIPS:
		var key = _clip_key(player, clip)
		lengths[clip] = player.get_animation(key).length if not key.is_empty() else -1.0
	var cap_pairs: Dictionary = zombie.get("caps")
	var complete_pairs = 0
	for pair in cap_pairs.values():
		if pair.has("body") and pair.has("detached") and is_instance_valid(pair.body) and is_instance_valid(pair.detached):
			complete_pairs += 1
	var record = {
		"revision_id": id, "selected_revision": _profile_id(),
		"controller_revision_id": zombie.get("revision_id"), "controller_model_path": zombie.get("model_path"),
		"packed_scene_resource_path": scene.resource_path if scene != null else "",
		"instantiated_scene_file_path": model.scene_file_path,
		"actual_glb_sha256": actual_hash, "expected_glb_sha256": profile.model_sha256,
		"source_md5": actual_md5, "imported_source_md5": imported_md5,
		"import_settings_sha256": FileAccess.get_sha256(String(profile.model_path) + ".import"),
		"meshes": mesh_nodes.size(), "triangles_including_hidden_caps": triangle_count,
		"bones": skeleton.get_bone_count(), "damage_regions": (zombie.get("hit_areas") as Dictionary).size(),
		"visible_part_regions": (zombie.get("part_meshes") as Dictionary).size(),
		"paired_caps": complete_pairs, "clip_lengths_seconds": lengths, "arm_rest_lengths": arm_lengths,
		"inverse_bind_sha256": JSON.stringify(inverse_bind_rows).sha256_text(),
		"bone_rest_sha256": JSON.stringify(rest_rows).sha256_text(),
		"attack_strike_seconds": zombie.get("attack_strike_seconds"),
		"walk_reference_speed_mps": zombie.get("walk_reference_speed"), "walk_speed_mps": zombie.get("walk_speed")
	}
	models[id] = record
	_check(id + ": exact distinct GLB is the instantiated model", _profile_id() == id
		and String(zombie.get("revision_id")) == id and String(zombie.get("model_path")) == String(profile.model_path)
		and scene != null and scene.resource_path == String(profile.model_path)
		and model.scene_file_path == String(profile.model_path) and actual_hash == String(profile.model_sha256), record)
	_check(id + ": import cache belongs to the exact source bytes", not imported_md5.is_empty() and actual_md5 == imported_md5,
		{"source_md5": actual_md5, "imported_source_md5": imported_md5})
	_check(id + ": complete mesh, rig, hit regions and sever caps", triangle_count == int(profile.triangles_including_caps)
		and triangle_count < 15000 and skeleton.get_bone_count() == 59 and (zombie.get("hit_areas") as Dictionary).size() == 14
		and (zombie.get("part_meshes") as Dictionary).size() == 14 and cap_pairs.size() == 13 and complete_pairs == 13,
		{"triangles": triangle_count, "bones": skeleton.get_bone_count(), "caps": complete_pairs})
	var timing_matches = true
	for clip in CLIPS:
		timing_matches = timing_matches and absf(float(lengths[clip]) - float(profile.clip_lengths_seconds[clip])) < 0.00001
	_check(id + ": profile timing config matches its imported clips", timing_matches
		and absf(float(zombie.get("attack_strike_seconds")) - float(profile.attack_strike_seconds)) < 0.000001
		and absf(float(zombie.get("walk_reference_speed")) - float(profile.walk_reference_speed_mps)) < 0.000001
		and absf(float(zombie.get("walk_speed")) - float(profile.walk_speed_mps)) < 0.000001,
		{"actual_clip_lengths": lengths, "expected_clip_lengths": profile.clip_lengths_seconds})


func _all_animation_frames(id: String) -> void:
	var zombie: Node3D = lab.get("subject")
	var skeleton: Skeleton3D = zombie.get("skeleton")
	var player: AnimationPlayer = zombie.get("animation_player")
	var finite = true
	var invalid: Array = []
	var frame_count = 0
	var bone_count = 0
	var clips: Dictionary = {}
	var comparison_poses: Dictionary = {}
	var all_hash = HashingContext.new()
	all_hash.start(HashingContext.HASH_SHA256)
	for clip_index in range(CLIPS.size()):
		var clip = String(CLIPS[clip_index])
		lab.call("_select_clip", clip_index)
		lab.call("_set_animation_paused", true)
		var length = player.get_animation(player.assigned_animation).length
		var last_frame = roundi(length * 60.0)
		var clip_hash = HashingContext.new()
		clip_hash.start(HashingContext.HASH_SHA256)
		var sampled_frames = 0
		for frame in range(last_frame + 1):
			lab.call("_seek_animation_frame", frame)
			skeleton.force_update_all_bone_transforms()
			var transforms = PackedFloat32Array()
			for bone in range(skeleton.get_bone_count()):
				var pose = skeleton.get_bone_global_pose(bone)
				if not pose.is_finite():
					finite = false
					if invalid.size() < 20:
						invalid.append({"clip": clip, "frame": frame, "bone": skeleton.get_bone_name(bone)})
				transforms.append_array(PackedFloat32Array(_transform(pose)))
				bone_count += 1
			var bytes = transforms.to_byte_array()
			clip_hash.update(bytes)
			all_hash.update(bytes)
			if frame in [12, 30, 42, 60, 84]:
				var pose_rows: Dictionary = {}
				for name in ARM_BONES:
					pose_rows[name] = _transform(skeleton.get_bone_global_pose(skeleton.find_bone(name)))
				comparison_poses[clip + "/" + str(frame)] = pose_rows
			frame_count += 1
			sampled_frames += 1
		clips[clip] = {"first_frame": 0, "last_frame": last_frame, "sampled_integer_frames": sampled_frames,
			"all_59_bone_global_matrices_sha256": clip_hash.finish().hex_encode()}
	total_animation_frames += frame_count
	total_bone_samples += bone_count
	animation_checks[id] = {"passed": finite and frame_count == int(EXPECTED_FRAMES[id]), "all_finite": finite,
		"frames": frame_count, "bone_matrix_samples": bone_count, "clips": clips,
		"actual_arm_pose_samples": comparison_poses, "all_frame_bone_matrices_sha256": all_hash.finish().hex_encode(), "invalid": invalid}
	_check(id + ": every integer animation pose evaluates all 59 bones", finite and frame_count == int(EXPECTED_FRAMES[id])
		and bone_count == frame_count * 59, {"frames": frame_count, "bone_matrix_samples": bone_count, "invalid": invalid})


func _different_models_check() -> void:
	var unique_hashes: Dictionary = {}
	var unique_mesh_sizes: Dictionary = {}
	for id in IDS:
		unique_hashes[models[id].actual_glb_sha256] = true
		unique_mesh_sizes[models[id].triangles_including_hidden_caps] = true
	_check("four revisions keep four distinct full assets", unique_hashes.size() == 4 and unique_mesh_sizes.size() == 4,
		{"distinct_glb_sha256_count": unique_hashes.size(), "distinct_triangle_count": unique_mesh_sizes.size()})
	var comparisons: Array = []
	var moved_samples = 0
	for pose_key in ["Zombie_Idle/60", "Zombie_Walk/30", "Zombie_Attack/42", "Zombie_Hit/12"]:
		var maximum = 0.0
		for bone in ARM_BONES:
			var a: Array = animation_checks.original.actual_arm_pose_samples[pose_key][bone]
			var b: Array = animation_checks.r4.actual_arm_pose_samples[pose_key][bone]
			var distance = Vector3(float(a[9]), float(a[10]), float(a[11])).distance_to(Vector3(float(b[9]), float(b[10]), float(b[11])))
			maximum = maxf(maximum, distance)
		if maximum > 0.01:
			moved_samples += 1
		comparisons.append({"pose": pose_key, "maximum_arm_joint_position_difference_m": maximum})
	_check("Original and R4 visibly different poses are not the same cached animation", moved_samples == 4, {"poses": comparisons})
	var length_changes: Dictionary = {}
	var corrected = true
	for side in ["Left", "Right"]:
		var before: Dictionary = models.original.arm_rest_lengths[side]
		var after: Dictionary = models.r4.arm_rest_lengths[side]
		length_changes[side] = {"original": before, "r4": after}
		corrected = corrected and float(after.upper_arm_m) > float(before.upper_arm_m) + 0.02 \
			and float(after.forearm_m) < float(before.forearm_m) - 0.02
	_check("R4 loads its corrected arm rest matrices and inverse bind data", corrected
		and models.original.bone_rest_sha256 != models.r4.bone_rest_sha256
		and models.original.inverse_bind_sha256 != models.r4.inverse_bind_sha256, length_changes)


func _paused_and_replay_selection() -> void:
	await _fresh("original")
	lab.call("_set_inspecting", true)
	lab.set("inspect_yaw", 0.64)
	lab.set("inspect_pitch", -0.18)
	lab.set("inspect_distance", 3.1)
	lab.call("_select_clip", 1)
	lab.call("_set_animation_paused", true)
	lab.call("_seek_animation_frame", 100)
	lab.call("select_revision", "r4")
	var player: AnimationPlayer = lab.get("subject").get("animation_player")
	_check("paused Original walk frame 100 clamps to R4 frame 84", _profile_id() == "r4" and bool(lab.get("animation_paused"))
		and int(lab.get("inspection_frame")) == 84 and String(player.assigned_animation).get_file() == "Zombie_Walk"
		and (absf(player.current_animation_position - 1.4) < 0.00001 or absf(player.current_animation_position) < 0.00001)
		and not player.is_playing(),
		{"frame": lab.get("inspection_frame"), "clip_time_seconds": player.current_animation_position,
			"loop_endpoint_note": "Godot may wrap a looping clip's duplicated last pose to time zero. The inspector's clamped authored frame must still be 84."})
	_check("revision comparison retains orbit camera settings", bool(lab.get("inspecting"))
		and absf(float(lab.get("inspect_yaw")) - 0.64) < 0.000001
		and absf(float(lab.get("inspect_pitch")) + 0.18) < 0.000001
		and absf(float(lab.get("inspect_distance")) - 3.1) < 0.000001)
	lab.call("select_revision", "original")
	_check("switch back preserves shared paused walk frame 84", bool(lab.get("animation_paused"))
		and int(lab.get("inspection_frame")) == 84)
	lab.call("_seek_animation_frame", 51)
	lab.call("select_revision", "r4")
	_check("an in-range paused frame is preserved exactly", bool(lab.get("animation_paused")) and int(lab.get("inspection_frame")) == 51)
	lab.call("_step_animation", 1)
	_check("one-frame step still works after switching", int(lab.get("inspection_frame")) == 52)
	lab.call("_select_clip", 2)
	lab.call("_seek_animation_frame", 95)
	lab.call("select_revision", "original")
	player = lab.get("subject").get("animation_player")
	_check("paused R4 attack frame 95 clamps to Original frame 84", bool(lab.get("animation_paused"))
		and int(lab.get("inspection_frame")) == 84 and String(player.assigned_animation).get_file() == "Zombie_Attack"
		and absf(player.current_animation_position - 1.4) < 0.00001)
	lab.call("_set_animation_paused", false)
	player.advance(0.5)
	lab.call("select_revision", "r4")
	player = lab.get("subject").get("animation_player")
	player.advance(0.0)
	_check("playing comparison starts selected clip at zero", not bool(lab.get("animation_paused"))
		and player.is_playing() and String(player.assigned_animation).get_file() == "Zombie_Attack"
		and absf(player.current_animation_position) < 0.000001, {"clip_time_seconds": player.current_animation_position})
	await _ticks(24)
	_check("selected continuous clip advances normally", player.current_animation_position > 0.075)
	var before_id = lab.get("subject").get_instance_id()
	var reset = InputEventKey.new()
	reset.physical_keycode = KEY_R
	reset.pressed = true
	lab.call("_unhandled_input", reset)
	await _ticks(2)
	_check("R reset retains selected R4 and creates a fresh subject", _profile_id() == "r4"
		and lab.get("subject").get_instance_id() != before_id and bool(lab.get("subject").get("alive"))
		and String(lab.get("subject").get("model_path")) == String(profiles.r4.model_path))
	before_id = lab.get("subject").get_instance_id()
	lab.call("select_revision", "not_a_revision")
	_check("invalid revision preserves current selection and subject", _profile_id() == "r4"
		and lab.get("subject").get_instance_id() == before_id)


func _attack_callback(damage: float) -> void:
	var player: AnimationPlayer = captured_zombie.get("animation_player")
	attack_events.append({"physics_frame": Engine.get_physics_frames(),
		"clip_time_seconds": player.current_animation_position, "attack_timer_seconds": captured_zombie.get("_attack_timer"), "damage": damage})


func _gameplay_profile(id: String) -> void:
	var zombie = await _fresh(id)
	var profile: Dictionary = profiles[id]
	var target = Node3D.new()
	target.name = "RevisionTestAttackTarget"
	lab.add_child(target)
	target.global_position = zombie.global_position + Vector3(0, 0, 0.9)
	zombie.set("target", target)
	attack_events.clear()
	captured_zombie = zombie
	zombie.connect("attack_landed", _attack_callback)
	var start = Engine.get_physics_frames()
	var attack_length = float(profile.clip_lengths_seconds.Zombie_Attack)
	var strike = float(profile.attack_strike_seconds)
	var time_limit = ceili((attack_length * 3.0 + 0.25) * Engine.physics_ticks_per_second)
	var loop_resets: Array = []
	var previous_timer = 0.0
	zombie.call("set_behavior", true)
	var player: AnimationPlayer = zombie.get("animation_player")
	for tick in range(time_limit):
		await _ticks(1)
		var timer = float(zombie.get("_attack_timer"))
		if previous_timer > attack_length - 0.05 and timer < previous_timer:
			loop_resets.append({"physics_frame": Engine.get_physics_frames(), "clip_time_seconds": player.current_animation_position})
		previous_timer = timer
		if attack_events.size() >= 3:
			break
	var tolerance = 2.0 / Engine.physics_ticks_per_second
	var timings: Array = []
	var timing_passed = attack_events.size() == 3
	for index in range(attack_events.size()):
		var event: Dictionary = attack_events[index]
		var observed_delay = float(int(event.physics_frame) - start) / Engine.physics_ticks_per_second
		var expected_delay = strike + attack_length * index
		var interval = observed_delay if index == 0 else float(int(event.physics_frame) - int(attack_events[index - 1].physics_frame)) / Engine.physics_ticks_per_second
		var interval_expected = strike if index == 0 else attack_length
		var passed = absf(interval - interval_expected) <= tolerance + 0.000001 \
			and absf(float(event.clip_time_seconds) - strike) <= tolerance + 0.000001 and float(event.damage) > 0.0
		timing_passed = timing_passed and passed
		timings.append({"cycle": index + 1, "passed": passed, "delay_from_start_seconds": observed_delay,
			"ideal_delay_from_start_seconds": expected_delay, "interval_seconds": interval,
			"expected_interval_seconds": interval_expected, "clip_time_at_signal_seconds": event.clip_time_seconds,
			"attack_timer_at_signal_seconds": event.attack_timer_seconds, "tolerance_seconds": tolerance})
	_check(id + ": three real AI strikes follow this revision's contact time", timing_passed, {"cycles": timings})
	var resets_passed = loop_resets.size() >= 2
	for reset in loop_resets:
		resets_passed = resets_passed and float(reset.clip_time_seconds) <= tolerance + 0.000001
	_check(id + ": repeated AI attacks visibly rewind their clip", resets_passed, {"loop_resets": loop_resets})
	zombie.call("set_behavior", false)
	var manual: Array = []
	for entry in ["playing_near_end", "paused_midclip", "playing_midclip"]:
		zombie.call("play_clip", "Zombie_Attack")
		player.seek(attack_length - 1.0 / 60.0 if entry == "playing_near_end" else 0.3, true)
		if entry == "paused_midclip":
			player.pause()
		zombie.call("play_clip", "Zombie_Attack")
		player.advance(0.0)
		var zero = player.current_animation_position
		await _ticks(12)
		manual.append({"entry": entry, "after_replay_seconds": zero, "after_12_physics_ticks_seconds": player.current_animation_position,
			"passed": absf(zero) < 0.000001 and player.current_animation_position > 0.025 and player.is_playing()})
	var manual_passed = true
	for entry in manual:
		manual_passed = manual_passed and bool(entry.passed)
	_check(id + ": public manual attack replays restart from playing and paused states", manual_passed, {"cases": manual})
	var hits: Array = []
	for index in range(3):
		zombie.call("receive_hit", "torso", 0.1)
		player.advance(0.0)
		var zero = player.current_animation_position
		await _ticks(24)
		hits.append({"cycle": index + 1, "zero_seconds": zero, "later_seconds": player.current_animation_position,
			"passed": absf(zero) < 0.000001 and String(player.assigned_animation).get_file() == "Zombie_Hit" and player.current_animation_position > 0.075})
	var hits_passed = true
	for hit in hits:
		hits_passed = hits_passed and bool(hit.passed)
	_check(id + ": repeated actual damage restarts hit reactions", hits_passed and bool(zombie.get("alive")), {"hits": hits})
	gameplay_checks[id] = {"attack_timing": timings, "loop_resets": loop_resets, "manual_replay": manual, "hit_reactions": hits}
	target.queue_free()
	await _ticks(2)


func _nearest_parent(zombie: Node3D, body: PhysicalBone3D) -> PhysicalBone3D:
	var skeleton: Skeleton3D = zombie.get("skeleton")
	var bones: Dictionary = zombie.get("physical_bones")
	var index = skeleton.get_bone_parent(body.get_bone_id())
	while index >= 0:
		var name = String(skeleton.get_bone_name(index))
		if bones.has(name):
			return bones[name]
		index = skeleton.get_bone_parent(index)
	return null


func _collision_shape(body: PhysicsBody3D) -> CollisionShape3D:
	for child in body.get_children():
		if child is CollisionShape3D:
			return child
	return null


func _shape_center_local(body: PhysicsBody3D) -> Vector3:
	var shape = _collision_shape(body)
	return shape.transform * shape.shape.get_debug_mesh().get_aabb().get_center()


func _shape_center_world(body: PhysicsBody3D) -> Vector3:
	var transform: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	return transform * _shape_center_local(body)


func _collect_instance_ids(node: Node, ids: Array[int]) -> void:
	ids.append(node.get_instance_id())
	for child in node.get_children():
		_collect_instance_ids(child, ids)


func _contact_profile(id: String, next_id: String) -> void:
	var zombie = await _fresh(id)
	lab.call("_set_animation_paused", true)
	lab.call("_seek_animation_frame", 0)
	zombie.call("die", Vector3(0.4, 0, -0.8))
	await _ticks(2)
	var bodies: Array = (zombie.get("physical_bones") as Dictionary).values()
	var invalid_policy: Array = []
	var exempt_pairs = 0
	var allowed_pairs = 0
	for index in range(bodies.size()):
		var body: PhysicalBone3D = bodies[index]
		PhysicsServer3D.body_set_max_contacts_reported(body.get_rid(), 32)
		if body.collision_layer != 8 or (body.collision_mask & 8) == 0:
			invalid_policy.append({"body": body.name, "layer": body.collision_layer, "mask": body.collision_mask})
		for second in range(index + 1, bodies.size()):
			var other: PhysicalBone3D = bodies[second]
			var adjacent = _nearest_parent(zombie, body) == other or _nearest_parent(zombie, other) == body
			var exempt_a = body.get_collision_exceptions().has(other)
			var exempt_b = other.get_collision_exceptions().has(body)
			if exempt_a:
				exempt_pairs += 1
			if not adjacent and not exempt_a and not exempt_b:
				allowed_pairs += 1
			if exempt_a != adjacent or exempt_b != adjacent:
				invalid_policy.append({"a": body.name, "b": other.name, "adjacent": adjacent, "exempt_a": exempt_a, "exempt_b": exempt_b})
	_check(id + ": only direct native joint neighbors are exempt from self collision", invalid_policy.is_empty()
		and exempt_pairs == bodies.size() - 1 and allowed_pairs > 70,
		{"invalid": invalid_policy, "exempt_direct_pairs": exempt_pairs, "allowed_nonadjacent_pairs": allowed_pairs})
	var contacts = 0
	var maximum_impulse = 0.0
	var pairs: Dictionary = {}
	var finite = true
	var ticks_count = 3 * Engine.physics_ticks_per_second
	for _frame in range(ticks_count):
		await _ticks(1)
		for body: PhysicalBone3D in bodies:
			finite = finite and body.global_transform.is_finite() and body.linear_velocity.is_finite() and body.angular_velocity.is_finite()
			var state = PhysicsServer3D.body_get_direct_state(body.get_rid())
			if state == null:
				continue
			for index in range(state.get_contact_count()):
				var other = state.get_contact_collider_object(index)
				if not other is PhysicalBone3D or not bodies.has(other):
					continue
				if _nearest_parent(zombie, body) == other or _nearest_parent(zombie, other) == body:
					continue
				var impulse = state.get_contact_impulse(index).length()
				contacts += 1
				maximum_impulse = maxf(maximum_impulse, impulse)
				var names = [String(body.name), String(other.name)]
				names.sort()
				var key = " / ".join(names)
				pairs[key] = maxf(float(pairs.get(key, 0.0)), impulse)
	total_contact_ticks += ticks_count
	_check(id + ": native nonadjacent ragdoll bodies exchange real solver impulses", contacts > 0 and maximum_impulse > 0.001 and finite,
		{"physics_steps": ticks_count, "contact_records": contacts, "maximum_impulse_ns": maximum_impulse, "pairs": pairs, "all_finite": finite})
	zombie.call("sever_limb", "upper_arm_r", Vector3.ZERO)
	await _ticks(2)
	var debris: Array = zombie.get("detached_parts")
	var arm: RigidBody3D = debris[0]
	var arm_segments: Array = arm.get_meta("segment_bodies")
	var baked = true
	var detached_mesh_count = 0
	for body: RigidBody3D in arm_segments:
		for child in body.get_children():
			if child is MeshInstance3D:
				detached_mesh_count += 1
				baked = baked and child.skin == null and child.skeleton.is_empty() and child.mesh != null
	var missing: Dictionary = zombie.get("missing")
	var caps: Dictionary = zombie.get("caps")
	_check(id + ": severed upper arm is a baked articulated three-part chain", arm_segments.size() == 3 and baked
		and detached_mesh_count >= 3 and bool(missing.upper_arm_r) and bool(missing.forearm_r) and bool(missing.hand_r)
		and caps.upper_arm_r.body.visible,
		{"segments": arm_segments.size(), "baked_meshes": detached_mesh_count, "baked_without_skin": baked})
	zombie.call("sever_limb", "head", Vector3.ZERO)
	await _ticks(2)
	debris = zombie.get("detached_parts")
	var head: RigidBody3D = debris.back()
	var torso: PhysicalBone3D = (zombie.get("physical_bones") as Dictionary)["Spine2"]
	head.contact_monitor = true
	head.max_contacts_reported = 32
	var start_center = _shape_center_world(torso) + Vector3(0, 0.65, 0)
	head.global_transform = Transform3D(Basis.IDENTITY, start_center - _shape_center_local(head))
	head.linear_velocity = Vector3(0, -0.1, 0)
	head.angular_velocity = Vector3.ZERO
	head.sleeping = false
	bodies = (zombie.get("physical_bones") as Dictionary).values()
	var head_contacts = 0
	var head_impulse = 0.0
	var head_pairs: Dictionary = {}
	var monitor_seen = false
	for _frame in range(ticks_count):
		await _ticks(1)
		for other in head.get_colliding_bodies():
			monitor_seen = monitor_seen or bodies.has(other)
		var state = PhysicsServer3D.body_get_direct_state(head.get_rid())
		if state == null:
			continue
		for index in range(state.get_contact_count()):
			var other = state.get_contact_collider_object(index)
			if not other is PhysicalBone3D or not bodies.has(other):
				continue
			var impulse = state.get_contact_impulse(index).length()
			head_contacts += 1
			head_impulse = maxf(head_impulse, impulse)
			head_pairs[String(other.name)] = maxf(float(head_pairs.get(String(other.name), 0.0)), impulse)
	total_contact_ticks += ticks_count
	_check(id + ": actual detached head collides with its own remaining corpse", head_contacts > 0 and head_impulse > 0.001
		and monitor_seen and head.global_transform.is_finite() and head.linear_velocity.is_finite()
		and (head.collision_mask & 8) != 0 and not head.get_collision_exceptions().has(torso),
		{"physics_steps": ticks_count, "contacts": head_contacts, "maximum_impulse_ns": head_impulse,
			"contacted_bones": head_pairs, "contact_monitor_saw_own_corpse": monitor_seen})
	contact_checks[id] = {"native_ragdoll_contact_steps": ticks_count, "native_nonadjacent_contacts": contacts,
		"native_maximum_impulse_ns": maximum_impulse, "native_pairs": pairs, "all_native_bodies_finite": finite,
		"detached_head_contact_steps": ticks_count, "detached_head_contacts": head_contacts,
		"detached_head_maximum_impulse_ns": head_impulse, "detached_head_pairs": head_pairs,
		"measurement": "Native PhysicsDirectBodyState3D contact collider objects and contact impulses. Head is dropped from 0.65 m above its own settled corpse; native corpse joints remain unchanged."}
	var old_ids: Array[int] = []
	_collect_instance_ids(zombie, old_ids)
	for root_part in debris:
		_collect_instance_ids(root_part, old_ids)
	lab.call("_burst", Vector3(0, 1, 0), Vector3.UP, true, 3)
	for effect in lab.get("effects"):
		old_ids.append(effect.node.get_instance_id())
	lab.call("select_revision", next_id)
	await _ticks(4)
	var survivors: Array = []
	for instance_id in old_ids:
		if is_instance_id_valid(instance_id):
			survivors.append(instance_id)
	_check(id + ": revision switch removes old corpse, detached chains and impact debris", survivors.is_empty()
		and (lab.get("effects") as Array).is_empty() and _profile_id() == next_id,
		{"old_object_count": old_ids.size(), "surviving_old_instance_ids": survivors, "next_revision": _profile_id()})


func _input_selection() -> void:
	var hotkeys = {"original": KEY_F1, "r4": KEY_F4, "r2": KEY_F2, "r3": KEY_F3}
	for id in IDS:
		var event = InputEventKey.new()
		event.physical_keycode = hotkeys[id]
		event.keycode = hotkeys[id]
		event.pressed = true
		Input.parse_input_event(event)
		await _ticks(2)
		var passed = _profile_id() == id and String(lab.get("subject").get("revision_id")) == id
		event = InputEventKey.new()
		event.physical_keycode = hotkeys[id]
		event.keycode = hotkeys[id]
		event.pressed = false
		Input.parse_input_event(event)
		await _ticks(1)
		_check(id + ": actual input dispatch of revision function key selects its full model", passed,
			{"physical_keycode": hotkeys[id], "selected_revision": _profile_id()})
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _ticks(2)
	for id in IDS:
		var button = lab.find_child("Revision_" + id, true, false) as Button
		if button == null:
			_check(id + ": real selector button exists", false)
			continue
		if _profile_id() == id:
			lab.call("select_revision", "r4" if id != "r4" else "original")
		var prior_subject_id = lab.get("subject").get_instance_id()
		var at = button.get_global_rect().get_center()
		var motion = InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		root.push_input(motion, true)
		await _ticks(1)
		var click = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.button_mask = MOUSE_BUTTON_MASK_LEFT
		click.pressed = true
		click.position = at
		click.global_position = at
		root.push_input(click, true)
		await _ticks(1)
		click = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = false
		click.position = at
		click.global_position = at
		root.push_input(click, true)
		await _ticks(2)
		var label = lab.find_child("ActiveRevision", true, false) as Label
		var file_label = lab.find_child("ActiveRevisionFile", true, false) as Label
		var profile: Dictionary = profiles[id]
		var label_ok = label != null and file_label != null and label.text == String(profile.label).to_upper() \
			and file_label.text == "ASSET  " + String(profile.model_path).get_file()
		var title_ok = lab.get_window().title.contains(String(profile.label)) and lab.get_window().title.contains(String(profile.model_path).get_file())
		_check(id + ": pointer press and release on real GUI button updates model and file labels", _profile_id() == id
			and button.button_pressed and String(lab.get("subject").get("revision_id")) == id and label_ok and title_ok
			and lab.get("subject").get_instance_id() != prior_subject_id and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
			{"button_name": button.name, "pointer_position": [at.x, at.y], "selected_revision": _profile_id(),
				"revision_label": label.text if label != null else "", "file_label": file_label.text if file_label != null else "",
				"window_title": lab.get_window().title, "mouse_stays_available_for_gui": Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
				"viewport_input_route": "Window.push_input(pointer event, in_local_coords=true)",
				"actual_subject_instance_changed": lab.get("subject").get_instance_id() != prior_subject_id})


func _new_lab() -> Node3D:
	var scene = load("res://main.tscn") as PackedScene
	var instance = scene.instantiate() as Node3D
	root.add_child(instance)
	instance.set_process(false)
	instance.set_physics_process(false)
	instance.call("_set_inspecting", true)
	Engine.max_fps = 0
	await _ticks(2)
	return instance


func _finish() -> void:
	var changed: Array = []
	for path in source_hashes:
		if FileAccess.get_sha256("res://" + path) != String(source_hashes[path]):
			changed.append(path)
	_check("all model, controller, main, manifest and test sources remain stable during the run", changed.is_empty(), {"changed_files": changed})
	var failed = 0
	for check in checks:
		if not bool(check.passed):
			failed += 1
	var report = {
		"passed": failed == 0, "checks": checks.size(), "failed": failed,
		"godot_version": Engine.get_version_info(), "physics_ticks_per_second": Engine.physics_ticks_per_second,
		"source_sha256_at_start": source_hashes, "files_changed_during_test": changed,
		"default_revision": "original", "available_revision_ids": IDS,
		"models": models, "all_integer_animation_frames": animation_checks,
		"total_animation_frames": total_animation_frames, "total_bone_matrix_samples": total_bone_samples,
		"native_gameplay": gameplay_checks, "actual_contact_response": contact_checks,
		"total_contact_physics_steps": total_contact_ticks, "results": checks,
		"scope": "Integration of preserved full GLBs with revision selection. Every imported integer animation pose is evaluated for finite matrices; this is not a replacement for each revision's prior visual mesh/fabric review. Ragdoll/contact checks sample native behavior across all four profiles; they do not repeat the earlier exhaustive R4 overlap audit."
	}
	var file = FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write revision integration report: " + output_path)
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("REVISION_SELECTION_RESULT ", JSON.stringify({"passed": failed == 0, "checks": checks.size(), "failed": failed,
		"animation_frames": total_animation_frames, "bone_samples": total_bone_samples, "contact_steps": total_contact_ticks, "report": output_path}))
	quit(0 if failed == 0 else 1)


func run() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not manifest is Dictionary:
		_check("revision catalog exists and parses", false)
		_finish()
		return
	for row in manifest.revisions:
		profiles[String(row.id)] = row
	for path in [MANIFEST, "res://main.gd", "res://main.tscn", "res://scripts/zombie.gd", "res://scenes/Zombie.tscn",
		"res://project.godot", "res://tests/revision_selection_check.gd"]:
		_remember(path)
	for row in profiles.values():
		_remember(String(row.model_path))
		_remember(String(row.model_path) + ".import")
	_check("catalog keeps Original as default with R4 explicitly latest", String(manifest.default_revision) == "original"
		and String(manifest.latest_revision) == "r4" and profiles.size() == 4)
	_check("native physics runs at the required 240 Hz", Engine.physics_ticks_per_second == 240)
	lab = await _new_lab()
	if not lab.has_method("select_revision") or not lab.has_method("get_selected_revision"):
		_check("main exposes revision selector API", false)
		_finish()
		return
	_check("fresh application starts with Original / Main", _profile_id() == "original"
		and String(lab.get("subject").get("model_path")) == String(profiles.original.model_path))
	for id in IDS:
		await _fresh(id)
		_model_check(id)
		_all_animation_frames(id)
		print("REVISION_SELECTION_POSES_COMPLETE ", id, " ", animation_checks[id].frames)
	_different_models_check()
	await _paused_and_replay_selection()
	await _input_selection()
	for id in IDS:
		await _gameplay_profile(id)
	for index in range(IDS.size()):
		await _contact_profile(IDS[index], IDS[(index + 1) % IDS.size()])
		print("REVISION_SELECTION_CONTACTS_COMPLETE ", IDS[index])
	lab.queue_free()
	await _ticks(4)
	lab = await _new_lab()
	_check("a new application scene defaults to Original after optional revision use", _profile_id() == "original"
		and String(lab.get("subject").get("model_path")) == String(profiles.original.model_path))
	lab.queue_free()
	await _ticks(4)
	_finish()

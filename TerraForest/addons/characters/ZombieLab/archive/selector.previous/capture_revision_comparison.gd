extends SceneTree
## Native revision selector comparison, CC0-1.0. Uses the real main scene and UI.
## Stills: godot --path . --script res://tools/capture_revision_comparison.gd -- --output=/absolute/folder
## Movie: add --fixed-fps 30 --write-movie /absolute/Comparison.avi before --script,
## and --movie after --. No authored model, rig, animation, light or fabric is changed.

const VIEWS = ["front", "right", "back", "left"]
const YAW = [0.0, -PI * 0.5, PI, PI * 0.5]
const REVISION_KEYS = {"original": KEY_F1, "r4": KEY_F4}
const CLIP_KEYS = {"Zombie_Walk": KEY_2, "Zombie_Attack": KEY_3}
const CAMERA_DISTANCE = 3.3
const CAMERA_PITCH = 0.08
const TRACKED_BONES = ["Hips", "Spine2", "Head", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]

var demo
var output = "/tmp/zombie_revision_comparison"
var movie_mode = false
var source_hashes: Dictionary = {}
var stills: Array = []
var chapters: Array = []
var motion_samples: Array = []
var first_physics_tick = 0
var first_render_frame = 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument == "--movie":
			movie_mode = true
	call_deferred("_run")


func _source_paths() -> Array[String]:
	var paths: Array[String] = ["project.godot", "main.gd", "main.tscn", "scenes/Zombie.tscn", "scripts/zombie.gd", "assets/zombie.revisions.json", "tools/capture_revision_comparison.gd"]
	for model in ["Zombie.glb", "Zombie.r2.glb", "Zombie.r3.glb", "Zombie.r4.glb"]:
		paths.append("assets/" + model)
		paths.append("assets/" + model + ".import")
	return paths


func _press(key: int) -> void:
	var down = InputEventKey.new()
	down.physical_keycode = key
	down.keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	var up = InputEventKey.new()
	up.physical_keycode = key
	up.keycode = key
	up.pressed = false
	Input.parse_input_event(up)
	# Synthetic key events otherwise remain queued until the next engine loop.
	# The inspector must finish handling the requested clip before an exact seek.
	Input.flush_buffered_events()


func _camera(angle: float) -> void:
	demo.inspect_yaw = angle
	demo.inspect_pitch = CAMERA_PITCH
	demo.inspect_distance = CAMERA_DISTANCE
	demo._update_inspect_camera()


func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _transform(value: Transform3D) -> Array:
	return [_vector(value.basis.x), _vector(value.basis.y), _vector(value.basis.z), _vector(value.origin)]


func _snapshot() -> Dictionary:
	var subject = demo.subject
	var animation: AnimationPlayer = subject.animation_player
	var profile: Dictionary = demo.revision_profiles[demo.get_selected_revision()]
	var bones: Dictionary = {}
	for name in TRACKED_BONES:
		var index = subject.skeleton.find_bone(name)
		if index >= 0:
			bones[name] = _transform(subject.skeleton.global_transform * subject.skeleton.get_bone_global_pose(index))
	return {
		"revision": demo.get_selected_revision(),
		"visible_revision_label": demo.revision_label.text,
		"visible_asset_label": demo.revision_file_label.text,
		"window_title": root.title,
		"loaded_model_scene_path": subject.model_scene.resource_path,
		"runtime_model_path": subject.model_path,
		"model_sha256": FileAccess.get_sha256(subject.model_path),
		"profile_model_sha256": profile.model_sha256,
		"clip": String(animation.assigned_animation).get_file(),
		"animation_position_seconds": animation.current_animation_position,
		"inspection_frame": demo.inspection_frame,
		"animation_paused": demo.animation_paused,
		"behavior_enabled": subject.behavior_enabled,
		"subject_transform": _transform(subject.global_transform),
		"camera_transform": _transform(demo.inspect_camera.global_transform),
		"camera_fov_degrees": demo.inspect_camera.fov,
		"camera_distance_m": demo.inspect_distance,
		"camera_pitch_radians": demo.inspect_pitch,
		"camera_yaw_radians": demo.inspect_yaw,
		"bone_world_poses": bones,
		"physics_tick": Engine.get_physics_frames(),
		"render_frame": Engine.get_frames_drawn()
	}


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	for path in _source_paths():
		source_hashes[path] = FileAccess.get_sha256("res://" + path)
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	current_scene = demo
	_press(KEY_ESCAPE)
	_press(KEY_TAB)
	_camera(0.0)
	for tick in range(48):
		await physics_frame
	if not demo.initialized or not demo.subject.initialized or not demo.inspecting:
		push_error("Native comparison did not initialize the inspector.")
		quit(4)
		return
	first_physics_tick = Engine.get_physics_frames()
	first_render_frame = Engine.get_frames_drawn()
	if movie_mode:
		await _movie()
	else:
		await _stills()
	var changed: Array[String] = []
	var final_hashes: Dictionary = {}
	for path in source_hashes:
		final_hashes[path] = FileAccess.get_sha256("res://" + path)
		if source_hashes[path] != final_hashes[path]:
			changed.append(path)
	var passed = changed.is_empty()
	if not movie_mode:
		passed = passed and stills.size() == 16
		for row in stills:
			passed = passed and row.save_error == OK and row.model_sha256 == row.profile_model_sha256
			passed = passed and row.animation_paused and absf(row.animation_position_seconds - float(row.requested_frame) / 60.0) < 0.00001
	var report = {
		"passed": passed,
		"mode": "normal_speed_movie" if movie_mode else "exact_pose_stills",
		"engine": Engine.get_version_info().string,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"render_resolution_pixels": [root.size.x, root.size.y],
		"first_physics_tick": first_physics_tick,
		"last_physics_tick": Engine.get_physics_frames(),
		"first_render_frame": first_render_frame,
		"last_render_frame": Engine.get_frames_drawn(),
		"source_sha256_at_start": source_hashes,
		"source_sha256_at_end": final_hashes,
		"files_changed_during_capture": changed,
		"input_method": "Input.parse_input_event uses the actual F1/F4 revision, 2/3 clip, Esc, Tab and P handlers; exact still poses use the inspector seek method.",
		"scene_policy": "Complete preserved GLBs in the shared main scene. Original lighting, courtyard, GUI and controller are retained; stationary manual-clip inspection.",
		"camera_policy": "3.3 m distance and 0.08 rad pitch; four cardinal still views; fixed 0.12 rad front-oblique movie view for both revisions.",
		"stills": stills,
		"chapters": chapters,
		"samples": motion_samples
	}
	var destination = output.path_join("movie_manifest.json" if movie_mode else "stills_manifest.json")
	var file = FileAccess.open(destination, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[RevisionComparison] ", "movie" if movie_mode else "stills", " complete; passed=", passed, " manifest=", destination)
	quit(0 if passed else 5)


func _stills() -> void:
	for revision in ["original", "r4"]:
		_press(REVISION_KEYS[revision])
		if demo.get_selected_revision() != revision:
			push_error("Revision hotkey did not select " + revision)
			return
		for clip in ["Zombie_Attack", "Zombie_Walk"]:
			_press(CLIP_KEYS[clip])
			if not demo.animation_paused:
				_press(KEY_P)
			var frame = 42 if clip == "Zombie_Attack" else 36
			demo._seek_animation_frame(frame)
			for view in range(4):
				_camera(YAW[view])
				var assigned = String(demo.subject.animation_player.assigned_animation).get_file()
				if assigned != clip or not demo.animation_paused or absf(demo.subject.animation_player.current_animation_position - float(frame) / 60.0) > 0.00001:
					push_error("The live inspector did not reach the requested paused clip/frame; no image will be saved.")
					return
				demo._set_message("%s · %s · FRAME %03d AT 60 Hz · %s" % [demo.revision_profiles[demo.get_selected_revision()].label, assigned.trim_prefix("Zombie_").to_upper(), demo.inspection_frame, VIEWS[view].to_upper()], 30.0)
				demo._update_ui()
				await process_frame
				await RenderingServer.frame_post_draw
				assigned = String(demo.subject.animation_player.assigned_animation).get_file()
				if assigned != clip or not demo.animation_paused or absf(demo.subject.animation_player.current_animation_position - float(frame) / 60.0) > 0.00001:
					push_error("The live inspector changed pose before rendering; no image will be saved.")
					return
				var filename = "%s_%s_f%03d_%s.png" % [revision, clip.trim_prefix("Zombie_").to_lower(), frame, VIEWS[view]]
				var error = root.get_texture().get_image().save_png(output.path_join(filename))
				var record = _snapshot()
				record.merge({"file": filename, "requested_frame": frame, "view": VIEWS[view], "save_error": error, "sha256": FileAccess.get_sha256(output.path_join(filename))})
				stills.append(record)
				print("[RevisionComparison] ", filename, " | ", record.loaded_model_scene_path, " | ", record.animation_position_seconds)


func _motion_sample(chapter: String) -> Dictionary:
	return {"chapter": chapter, "revision": demo.get_selected_revision(), "physics_tick": Engine.get_physics_frames(), "render_frame": Engine.get_frames_drawn(), "clip": String(demo.subject.animation_player.assigned_animation).get_file(), "clip_position_seconds": demo.subject.animation_player.current_animation_position, "root_position": _vector(demo.subject.global_position)}


func _hold(seconds: float, chapter: String) -> void:
	var state = _snapshot()
	state.merge({"chapter": chapter, "duration_seconds": seconds})
	chapters.append(state)
	motion_samples.append(_motion_sample(chapter))
	for tick in range(roundi(seconds * Engine.physics_ticks_per_second)):
		await physics_frame
		motion_samples.append(_motion_sample(chapter))


func _movie() -> void:
	_camera(0.12)
	_press(KEY_F1)
	demo._set_message("ORIGINAL / MAIN · startup default · F4 switches to the optional latest model", 1.0)
	await _hold(0.6, "Original introduction")
	for revision in ["original", "r4"]:
		_press(REVISION_KEYS[revision])
		_camera(0.12)
		if demo.animation_paused:
			_press(KEY_P)
		_press(KEY_2)
		var walk_cycles = 2 if revision == "original" else 3
		var walk_length = demo.subject.animation_player.get_animation(demo.subject.animation_player.assigned_animation).length
		demo._set_message("%s · WALK · %d CYCLES · NORMAL SPEED" % [demo.revision_profiles[revision].label.to_upper(), walk_cycles], walk_length * walk_cycles + 0.5)
		await _hold(walk_length * walk_cycles, revision + " walk")
		for cycle in range(3):
			_press(KEY_3)
			var attack_length = demo.subject.animation_player.get_animation(demo.subject.animation_player.assigned_animation).length
			demo._set_message("%s · ATTACK %d / 3 · NORMAL SPEED" % [demo.revision_profiles[revision].label.to_upper(), cycle + 1], attack_length + 0.5)
			await _hold(attack_length, revision + " attack " + str(cycle + 1))
	demo._set_message("F1  Original / Main · F4  R4 / Latest · the filename above shows the loaded model", 1.0)
	await _hold(0.6, "Comparison complete")

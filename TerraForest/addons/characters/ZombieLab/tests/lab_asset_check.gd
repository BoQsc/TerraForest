extends SceneTree
## Native model identity, revision controls, imported clips and frame inspector.
## Run after normal project import. All changes are transient lab interactions.

var lab
var checks: Array[Dictionary] = []
var models: Dictionary = {}
var source_hashes: Dictionary = {}
var output = "res://validation/lab.assets.json"


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	call_deferred("run")


func _check(name: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"name": name, "passed": passed, "details": details})
	if not passed:
		print("LAB_ASSET_FAILED ", JSON.stringify(checks.back()))


func _ticks(count: int) -> void:
	for tick in range(count):
		await physics_frame
		await process_frame


func _press(key: int) -> void:
	var event = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	var release = InputEventKey.new()
	release.keycode = key
	release.physical_keycode = key
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()


func _mouse_click(control: Control) -> void:
	var center = control.get_global_rect().get_center()
	var motion = InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = center
		event.global_position = center
		event.pressed = pressed
		root.push_input(event, true)


func _import_md5(path: String) -> String:
	var settings = ConfigFile.new()
	if settings.load(path + ".import") != OK:
		return ""
	var compiled = String(settings.get_value("remap", "path", ""))
	var md5 = compiled.get_basename() + ".md5"
	if not FileAccess.file_exists(md5):
		return ""
	for line in FileAccess.get_file_as_string(md5).split("\n"):
		if line.begins_with("source_md5="):
			return line.get_slice('"', 1)
	return ""


func _model_check(id: String) -> void:
	var zombie = lab.subject
	var profile: Dictionary = lab.revision_profiles[id]
	var meshes: Array = []
	_meshes(zombie.model, meshes)
	var triangles = 0
	for node in meshes:
		for surface in range(node.mesh.get_surface_count()):
			var arrays = node.mesh.surface_get_arrays(surface)
			var indices = arrays[Mesh.ARRAY_INDEX]
			triangles += int(indices.size() / 3) if indices != null and indices.size() > 0 else int(arrays[Mesh.ARRAY_VERTEX].size() / 3)
	var caps = 0
	for pair in zombie.caps.values():
		if pair.has("body") and pair.has("detached"):
			caps += 1
	var clips: Dictionary = {}
	for key in zombie.animation_player.get_animation_list():
		var name = String(key).get_file()
		if name.begins_with("Zombie_"):
			clips[name] = zombie.animation_player.get_animation(key).length
	var r4 = id == "r4"
	var row = {"model_path": zombie.model_path, "instantiated_scene": zombie.model.scene_file_path,
		"actual_sha256": FileAccess.get_sha256(zombie.model_path), "expected_sha256": profile.model_sha256,
		"source_md5": FileAccess.get_md5(zombie.model_path), "cache_source_md5": _import_md5(zombie.model_path),
		"triangles_including_caps": triangles, "bones": zombie.skeleton.get_bone_count(),
		"regions": zombie.hit_areas.size(), "cap_pairs": caps, "clips": clips,
		"r4_actions_enabled": zombie.get_behavior_snapshot().get("r4_actions_enabled", false) if zombie.has_method("get_behavior_snapshot") else false}
	models[id] = row
	_check(id + ": expanded behavior is enabled only for R4", bool(row.r4_actions_enabled) == r4)
	_check(id + ": displayed and loaded model matches exact catalog bytes", zombie.model_path == profile.model_path
		and zombie.model.scene_file_path == profile.model_path and row.actual_sha256 == profile.model_sha256
		and lab.revision_file_label.text.contains(String(profile.model_path).get_file()), row)
	_check(id + ": import cache belongs to the source GLB", row.source_md5 == row.cache_source_md5 and not String(row.cache_source_md5).is_empty())
	_check(id + ": full rig / damage regions / sever cap budget", triangles == int(profile.triangles_including_caps)
		and triangles < 15000 and row.bones == 59 and row.regions == 14 and caps == 13, row)
	var required: Dictionary = profile.clip_lengths_seconds
	var timing = true
	for clip in required:
		timing = timing and clips.has(clip) and absf(float(clips.get(clip, -1)) - float(required[clip])) < .00001
	_check(id + ": complete animation set with matching inspector timing", timing and clips.size() == (15 if r4 else 4), {"clips": clips})
	_check(id + ": action dropdown reflects this complete model", lab.action_picker.item_count == clips.size(), {"items": lab.action_picker.item_count, "clips": clips.size()})


func _meshes(node: Node, result: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		result.append(node)
	for child in node.get_children():
		_meshes(child, result)


func _frame_check(clip: String, frame: int) -> void:
	lab.select_action(clip)
	lab._set_animation_paused(true)
	lab._seek_animation_frame(frame)
	await _ticks(2)
	var player: AnimationPlayer = lab.subject.animation_player
	_check("Inspector exact frozen pose: " + clip + " f" + str(frame), lab.animation_paused
		and String(player.assigned_animation).get_file() == clip
		and absf(player.current_animation_position - float(frame) / 60.0) < .00001,
		{"requested_frame": frame, "actual_seconds": player.current_animation_position, "assigned_clip": player.assigned_animation})


func run() -> void:
	root.size = Vector2i(1280, 800)
	for path in ["main.gd", "scripts/zombie.gd", "scripts/zombie_demo.gd", "scripts/zombie_demo_target.gd", "assets/zombie.revisions.json", "assets/Zombie.r4.behavior.json", "assets/Zombie.glb", "assets/Zombie.r2.glb", "assets/Zombie.r4.glb", "assets/Zombie.glb.import", "assets/Zombie.r2.glb.import", "assets/Zombie.r4.glb.import"]:
		source_hashes[path] = FileAccess.get_sha256("res://" + path)
	lab = load("res://main.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	await _ticks(3)
	_press(KEY_ESCAPE)
	_check("F1 Original remains startup default", lab.get_selected_revision() == "original")
	_check("Active revision controls are exactly F1/F2/F4", lab.revision_buttons.has("original")
		and lab.revision_buttons.has("r2") and lab.revision_buttons.has("r4") and not lab.revision_buttons.has("r3"))
	_model_check("original")
	for entry in [{"id": "r2", "key": KEY_F2}, {"id": "r4", "key": KEY_F4}]:
		_press(entry.key)
		await _ticks(2)
		_check("Actual hotkey selects " + entry.id, lab.get_selected_revision() == entry.id)
		_model_check(entry.id)
	_press(KEY_F3)
	await _ticks(1)
	_check("F3 cannot activate deprecated R3", lab.get_selected_revision() == "r4")
	lab.select_revision("r3")
	_check("Deprecated R3 is also rejected by selection API", lab.get_selected_revision() == "r4")
	for entry in [{"clip":"Zombie_Attack_Bite","frame":36}, {"clip":"Zombie_Attack_Left","frame":32},
		{"clip":"Zombie_Attack_Right","frame":36}, {"clip":"Zombie_Attack_Both","frame":42},
		{"clip":"Zombie_Crawl","frame":96}, {"clip":"Zombie_Crawl_Idle","frame":120},
		{"clip":"Zombie_Crawl_Bite","frame":30}, {"clip":"Zombie_Crawl_Hit","frame":30},
		{"clip":"Zombie_To_Crawl","frame":48}, {"clip":"Zombie_Jump","frame":33},
		{"clip":"Zombie_Climb_Ladder","frame":120}]:
		await _frame_check(entry.clip, entry.frame)
	_press(KEY_PERIOD)
	_check("Frame step remains clamped at endpoint", lab.inspection_frame == 120)
	_press(KEY_COMMA)
	_check("Frame step retreats exactly one frame", lab.inspection_frame == 119)
	_press(KEY_F1)
	await _ticks(2)
	_check("Switching from R4 extras restores a supported F1 clip", lab.get_selected_revision() == "original"
		and String(lab.subject.animation_player.assigned_animation).get_file() in ["Zombie_Idle", "Zombie_Walk", "Zombie_Attack", "Zombie_Hit"])
	_mouse_click(lab.revision_buttons.r4)
	await _ticks(2)
	_check("Actual GUI mouse hit selects F4", lab.get_selected_revision() == "r4")
	_mouse_click(lab.demo_run_button)
	await _ticks(3)
	var demo: Dictionary = lab.get_demo_snapshot()
	_check("Actual GUI demonstration button starts live R4 controller", demo.get("active", false)
		and lab.get_selected_revision() == "r4", demo)
	lab.stop_demo()
	await _ticks(2)
	_check("Stop demonstration restores manual control", not lab.get_demo_snapshot().get("active", true)
		and not lab.subject.behavior_enabled)
	_press(KEY_R)
	await _ticks(2)
	_check("Reset preserves chosen revision and restores all limbs", lab.get_selected_revision() == "r4"
		and lab.subject.alive and lab.subject.missing.values().all(func(value): return not value))
	var changed: Array[String] = []
	for path in source_hashes:
		if source_hashes[path] != FileAccess.get_sha256("res://" + path):
			changed.append(path)
	_check("Verified code and contract stayed unchanged during run", changed.is_empty(), {"changed": changed})
	var passed = checks.all(func(row): return row.passed)
	var file = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"checks":checks,"models":models,"source_sha256":source_hashes,
		"engine":Engine.get_version_info().string,"input_method":"Actual key events and Window.push_input GUI pointer hit-testing", "window_pixels":[root.size.x,root.size.y]}, "\t"))
	print("LAB_ASSETS_COMPLETE ", checks.size(), " checks; passed=", passed, " report=", output)
	quit(0 if passed else 4)

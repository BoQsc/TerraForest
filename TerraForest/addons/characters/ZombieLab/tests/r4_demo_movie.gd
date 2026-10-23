extends SceneTree
## A native, real-time recording of the actual lab UI and controller.
## Invoke with --fixed-fps 30 --write-movie <output.avi>; no simulation retiming.

const MOVIE_FPS = 30.0
const SOURCE_PATHS = [
	"main.gd", "main.tscn", "project.godot", "scripts/zombie.gd",
	"scripts/zombie_demo.gd", "scripts/zombie_demo_target.gd",
	"assets/zombie.revisions.json", "assets/Zombie.r4.behavior.json",
	"assets/Zombie.glb", "assets/Zombie.r2.glb", "assets/Zombie.r4.glb",
	"tests/r4_demo_movie.gd"
]

var lab
var manifest_path = "res://validation/r4.demo.movie.json"
var source_hashes: Dictionary = {}
var frame_number = 0
var start_button_frame = -1
var stop_button_frame = -1
var stage_records: Array = []
var contact_records: Array = []
var movie_camera = false
var completion_frame = -1
var completed_summary: Dictionary = {}
var recording_verified = false


func _initialize() -> void:
	process_frame.connect(_on_process_frame)
	call_deferred("_run")


func _on_process_frame() -> void:
	frame_number += 1
	if movie_camera and is_instance_valid(lab) and is_instance_valid(lab.demonstration):
		_adjust_camera()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="):
			manifest_path = arg.trim_prefix("--manifest=")
	for path in SOURCE_PATHS:
		source_hashes[path] = FileAccess.get_sha256("res://" + path)
	lab = load("res://main.tscn").instantiate()
	root.add_child(lab)
	await _frames(4)
	Engine.max_fps = 0
	lab.demonstration.stage_changed.connect(_on_stage_changed)
	lab.demonstration.cycle_completed.connect(_on_cycle_complete)
	var initial_revision = lab.get_selected_revision()
	var initial_file = lab.revision_file_label.text
	# Leave the real F1 startup on screen, release the mouse and visibly hover
	# the actual Run button before pressing/releasing it through GUI hit testing.
	await _frames(18)
	_key(KEY_ESCAPE)
	await _frames(8)
	_pointer_motion(lab.demo_run_button)
	await _frames(12)
	_pointer_button(lab.demo_run_button, true)
	await _frames(4)
	start_button_frame = frame_number
	_pointer_button(lab.demo_run_button, false)
	movie_camera = true
	if not lab.get_demo_snapshot().get("active", false):
		_save_manifest(false, initial_revision, initial_file, "Actual Run button did not start the demonstration")
		quit(2)
		return
	lab.subject.attack_contact.connect(_on_contact)
	var frame_limit = frame_number + roundi(MOVIE_FPS * 90.0)
	while lab.demonstration.active and not lab.demonstration.complete and frame_number < frame_limit:
		await process_frame
	var success = lab.demonstration.complete
	if success:
		completion_frame = frame_number
		await _frames(30)
		_pointer_motion(lab.demo_stop_button)
		await _frames(5)
		_pointer_button(lab.demo_stop_button, true)
		await _frames(3)
		stop_button_frame = frame_number
		_pointer_button(lab.demo_stop_button, false)
		await _frames(35)
	_save_manifest(success, initial_revision, initial_file, "" if success else String(lab.get_demo_snapshot().get("note", "Incomplete demonstration")))
	print("[R4 Demo Movie] complete=", success, " | verified=", recording_verified, " | frames=", frame_number, " | manifest=", manifest_path)
	quit(0 if recording_verified else 2)


func _adjust_camera() -> void:
	var stage = String(lab.demonstration.stage)
	var phase = float(lab.demonstration.stage_time)
	var yaw = 0.88
	var pitch = 0.12
	var distance = 3.55
	match stage:
		"approach":
			yaw = 0.78
			distance = 4.70
			pitch = 0.09
		"jump":
			# The open side keeps both feet and the obstacle clear of the platform.
			yaw = -0.60
			distance = 3.20
			pitch = 0.14
		"ladder":
			yaw = -0.80
			distance = 3.50
			pitch = 0.12
		"one_leg", "both_legs", "cycle_complete", "stopped":
			yaw = 1.08
			distance = 3.70
			pitch = 0.22
	lab.inspect_yaw = yaw + sin(phase * 0.55) * 0.025
	lab.inspect_pitch = pitch
	lab.inspect_distance = distance
	lab._update_inspect_camera()


func _on_stage_changed(stage: String) -> void:
	stage_records.append({"stage": stage, "movie_frame": frame_number, "movie_seconds": float(frame_number) / MOVIE_FPS, "demo_elapsed_seconds": lab.demonstration.elapsed, "root_position": _v3(lab.subject.global_position)})


func _on_contact(action: String, damage: float, point: Vector3) -> void:
	var state: Dictionary = lab.subject.get_behavior_snapshot()
	contact_records.append({"action": action, "damage": damage, "movie_frame": frame_number, "movie_seconds": float(frame_number) / MOVIE_FPS, "demo_elapsed_seconds": lab.demonstration.elapsed, "clip": state.clip, "animation_time": state.animation_time, "action_time": state.action_time, "surface_gap_m": state.last_contact.get("surface_distance", 0.0), "visible_target_shapes": state.last_contact.get("visible_target_shapes", false), "world_point": _v3(point), "root_position": _v3(lab.subject.global_position)})


func _on_cycle_complete(summary: Dictionary) -> void:
	completed_summary = summary.duplicate(true)


func _save_manifest(success: bool, initial_revision: String, initial_file: String, error: String) -> void:
	var changed: Array[String] = []
	for path in source_hashes:
		if source_hashes[path] != FileAccess.get_sha256("res://" + path):
			changed.append(path)
	var import_sources: Dictionary = {}
	for path in ["assets/Zombie.glb", "assets/Zombie.r2.glb", "assets/Zombie.r4.glb"]:
		var settings = ConfigFile.new()
		if settings.load("res://" + path + ".import") == OK:
			var compiled = String(settings.get_value("remap", "path", ""))
			var md5_path = compiled.get_basename() + ".md5"
			var source_md5 = ""
			if FileAccess.file_exists(md5_path):
				for line in FileAccess.get_file_as_string(md5_path).split("\n"):
					if line.begins_with("source_md5="):
						source_md5 = line.trim_prefix("source_md5=").trim_prefix("\"").trim_suffix("\"")
			import_sources[path] = {"compiled_resource": compiled, "compiled_source_md5": source_md5, "current_file_md5": FileAccess.get_md5("res://" + path), "match": source_md5 == FileAccess.get_md5("res://" + path)}
	var stopped_by_button = stop_button_frame >= 0 and not bool(lab.get_demo_snapshot().get("active", true))
	var imports_match = import_sources.size() == 3 and import_sources.values().all(func(row): return bool(row.get("match", false)))
	recording_verified = success and initial_revision == "original" and stopped_by_button and changed.is_empty() and imports_match and is_equal_approx(Engine.time_scale, 1.0)
	var result = {
		"schema_version": 1, "completed": success, "verified": recording_verified, "error": error,
		"recording": "Native Godot MovieWriter; actual controller and GUI events",
		"fps": MOVIE_FPS, "physics_hz": Engine.physics_ticks_per_second,
		"time_scale": Engine.time_scale, "retimed": false,
		"observed_process_frames": frame_number, "first_revision": initial_revision,
		"initial_asset_label": initial_file, "active_asset_label": lab.revision_file_label.text,
		"actual_gui_run_button": true, "run_button_release_frame": start_button_frame,
		"actual_gui_stop_button": stopped_by_button, "stop_button_release_frame": stop_button_frame,
		"cycle_completed_frame": completion_frame, "stages": stage_records,
		"contacts": contact_records, "cycle_summary": completed_summary,
		"source_sha256": source_hashes, "changed_during_recording": changed,
		"import_sources": import_sources, "engine": Engine.get_version_info().string,
		"camera": "Three-quarter orbit with distinct standing, jump, ladder and prone framing; character physics unchanged",
		"window_pixels": [root.size.x, root.size.y], "final_demo": lab.get_demo_snapshot()
	}
	var file = FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _pointer_motion(control: Control) -> void:
	var center = control.get_global_rect().get_center()
	var event = InputEventMouseMotion.new()
	event.position = center
	event.global_position = center
	root.push_input(event, true)


func _pointer_button(control: Control, pressed: bool) -> void:
	var center = control.get_global_rect().get_center()
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = center
	event.global_position = center
	event.pressed = pressed
	root.push_input(event, true)


func _v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

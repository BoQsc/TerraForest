extends SceneTree
## Captures actual live-controller interactions, freezing each outcome for four views.

var output_directory = "res://preview/live.demo"
var captures: Array = []
var captured: Dictionary = {}
var replace_tags: Array[String] = []
var previous_report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_directory = arg.trim_prefix("--output=")
		elif arg.begins_with("--replace-tags="):
			replace_tags.assign(arg.trim_prefix("--replace-tags=").split(",", false))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	if not replace_tags.is_empty() and FileAccess.file_exists(output_directory.path_join("capture.manifest.json")):
		previous_report = JSON.parse_string(FileAccess.get_file_as_string(output_directory.path_join("capture.manifest.json")))
	var lab = load("res://main.tscn").instantiate()
	root.add_child(lab)
	for index in range(4):
		await process_frame
	Engine.max_fps = 0
	if not lab.start_demo():
		printerr("Cannot start the R4 demonstration")
		quit(2)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var observed_contacts = 0
	var ticks = 0
	while lab.demonstration.active and not lab.demonstration.complete and ticks < 240 * 80:
		await physics_frame
		ticks += 1
		var stage = lab.demonstration.stage
		var snapshot: Dictionary = lab.subject.get_behavior_snapshot()
		var tag = ""
		if lab.demonstration.contact_count > observed_contacts:
			observed_contacts = lab.demonstration.contact_count
			tag = stage + ".contact"
		elif stage == "jump" and String(snapshot.active_action) == "jump" and float(snapshot.action_time) >= 32.5 / 60.0:
			tag = "jump.apex"
		elif stage == "ladder" and String(snapshot.traversal_state) == "ladder_climb" and float(snapshot.position.y) >= 0.44:
			tag = "ladder.mid"
		elif stage == "one_leg" and String(snapshot.active_action) == "to_crawl" and float(snapshot.action_time) >= 0.40:
			tag = "one_leg.drop"
		elif stage == "one_leg" and String(snapshot.state) == "crawl" and lab.demonstration.stage_distance >= 0.35:
			tag = "one_leg.crawl"
		elif stage == "both_legs" and String(snapshot.state) == "crawl" and lab.demonstration.stage_distance >= 0.35:
			tag = "both_legs.crawl"
		if not tag.is_empty() and not captured.has(tag) and (replace_tags.is_empty() or tag in replace_tags):
			captured[tag] = true
			await _capture_views(lab, tag, snapshot)
	for earlier in previous_report.get("captures", []):
		if not String(earlier.tag) in replace_tags:
			if not earlier.has("capture_harness_sha256"):
				earlier["capture_harness_sha256"] = previous_report.get("source_sha256", {}).get("tests/r4_demo_capture.gd", "")
			captures.append(earlier)
	var report = {"captures": captures, "demo": lab.get_demo_snapshot(), "cycle_summary": lab.demonstration.completed_cycles[0] if not lab.demonstration.completed_cycles.is_empty() else {}, "actual_live_controller": true, "views_frozen_at_same_simulation_pose": true, "completed_draws_after_pose": 2, "replaced_camera_tags": replace_tags, "asset_sha256": FileAccess.get_sha256("res://assets/Zombie.r4.glb"), "source_sha256": {"scripts/zombie_demo.gd": FileAccess.get_sha256("res://scripts/zombie_demo.gd"), "scripts/zombie_demo_target.gd": FileAccess.get_sha256("res://scripts/zombie_demo_target.gd"), "tests/r4_demo_capture.gd": FileAccess.get_sha256("res://tests/r4_demo_capture.gd")}}
	var file = FileAccess.open(output_directory.path_join("capture.manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[R4 Live Capture] ", captures.size(), " screenshots | complete=", lab.demonstration.complete)
	lab.queue_free()
	await process_frame
	quit(0 if bool(report.demo.complete) else 2)


func _capture_views(lab, tag: String, snapshot: Dictionary) -> void:
	paused = true
	var yaw = lab.inspect_yaw
	var pitch = lab.inspect_pitch
	var distance = lab.inspect_distance
	for view in [{"name": "front", "yaw": 0.55}, {"name": "right", "yaw": PI * 0.5}, {"name": "back", "yaw": PI + 0.55}, {"name": "left", "yaw": -PI * 0.5}]:
		lab.inspect_yaw = float(view.yaw)
		lab.inspect_pitch = 0.14
		lab.inspect_distance = 3.20
		if tag == "jump.apex" and view.name == "front":
			lab.inspect_yaw = -0.60 # Look from the open side, clear of the ladder.
		elif tag == "jump.apex" and view.name == "back":
			lab.inspect_yaw = PI + 0.90
			lab.inspect_distance = 2.40 # Keep the rear camera inside the room wall.
		lab._update_inspect_camera()
		lab._update_ui()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var path = output_directory.path_join(tag + "." + String(view.name) + ".png")
		root.get_texture().get_image().save_png(path)
		captures.append({"tag": tag, "view": view.name, "path": path, "runtime_snapshot": snapshot.duplicate(true), "demo_snapshot": lab.get_demo_snapshot(), "camera": {"yaw": lab.inspect_yaw, "pitch": lab.inspect_pitch, "distance": lab.inspect_distance}, "capture_harness_sha256": FileAccess.get_sha256("res://tests/r4_demo_capture.gd")})
	lab.inspect_yaw = yaw
	lab.inspect_pitch = pitch
	lab.inspect_distance = distance
	lab._update_inspect_camera()
	paused = false

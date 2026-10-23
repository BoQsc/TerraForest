extends SceneTree
## Actual keyboard pause/step/resume and action selection during live transitions.

var checks: Array = []
var report_path = "res://validation/r4.demo.interruption.json"


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, passed: bool, details = null) -> void:
	checks.append({"check": label, "passed": passed, "details": details})
	if not passed:
		printerr("[R4 Interruption Check] FAIL: ", label, " | ", details)


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			report_path = arg.trim_prefix("--report=")
	var lab = load("res://main.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	Engine.max_fps = 0
	lab.start_demo()
	lab.demonstration._enter_stage("one_leg")
	await _ticks(80)
	_key(KEY_P)
	await process_frame
	_check("P during actual leg-loss transition stops demo and enters inspection", not lab.demonstration.active and lab.animation_paused and lab.subject.animation_player.assigned_animation == "Zombie_To_Crawl")
	lab._seek_animation_frame(24)
	await _ticks(240)
	var snapshot: Dictionary = lab.subject.get_behavior_snapshot()
	_check("paused transition holds the exact frame beyond its normal completion time", snapshot.active_action == "to_crawl" and lab.subject.animation_player.assigned_animation == "Zombie_To_Crawl" and absf(lab.subject.animation_player.current_animation_position - 0.4) < 0.00001, snapshot)
	_key(KEY_PERIOD)
	await _ticks(40)
	_check("period advances exactly one authored frame during the paused transition", lab.inspection_frame == 25 and absf(lab.subject.animation_player.current_animation_position - 25.0 / 60.0) < 0.00001)
	_key(KEY_P)
	await _ticks(160)
	snapshot = lab.subject.get_behavior_snapshot()
	_check("P resumes and naturally completes the physical prone conversion", not lab.animation_paused and snapshot.movement_mode == "crawling" and snapshot.active_action.is_empty(), snapshot)
	lab.restart_demo()
	lab.demonstration._enter_stage("one_leg")
	await _ticks(60)
	lab.select_action("Zombie_Jump")
	await _ticks(16)
	lab._update_ui()
	_check("incompatible action selects and labels the available prone fallback", not lab.demonstration.active and lab.subject.animation_player.assigned_animation == "Zombie_Crawl_Idle" and lab.action_names[lab.action_picker.selected] == "Zombie_Crawl_Idle" and lab.current_clip == "CRAWL IDLE")
	lab.restart_demo()
	lab.demonstration._enter_stage("bite")
	var wait_ticks = 0
	while wait_ticks < 800:
		await physics_frame
		wait_ticks += 1
		snapshot = lab.subject.get_behavior_snapshot()
		if snapshot.active_action == "bite" and float(snapshot.action_time) > 0.30:
			break
	var live_frame = roundi(lab.subject.animation_player.current_animation_position * 60.0)
	_key(KEY_P)
	await _ticks(100)
	_check("P preserves the live attack clip and frame before stopping behavior", not lab.demonstration.active and lab.animation_paused and lab.subject.animation_player.assigned_animation == "Zombie_Attack_Bite" and lab.inspection_frame == live_frame and absf(lab.subject.animation_player.current_animation_position - float(live_frame) / 60.0) < 0.00001, {"saved_frame": live_frame, "frame": lab.inspection_frame, "clip": lab.subject.animation_player.assigned_animation})
	lab.restart_demo()
	lab.demonstration._enter_stage("ladder")
	await _ticks(460)
	_check("stop test begins on the real elevated ladder", lab.subject.global_position.y > 0.25 and String(lab.subject.get_behavior_snapshot().traversal_state) == "ladder_climb", lab.subject.get_behavior_snapshot())
	lab.stop_demo()
	await _ticks(240)
	snapshot = lab.subject.get_behavior_snapshot()
	_check("Stop during a climb restores grounded physics and available inspection", not lab.demonstration.active and not lab.animation_paused and snapshot.traversal_state == "none" and lab.subject.motion_mode == CharacterBody3D.MOTION_MODE_GROUNDED and lab.subject.global_position.y > -0.05 and lab.subject.target == lab.player, snapshot)
	_check("Restart after an interrupted climb restores fresh limbs and active pursuit", lab.restart_demo() and lab.demonstration.active and not lab.subject.missing.get("thigh_l", true) and not lab.subject.missing.get("thigh_r", true) and lab.subject.behavior_enabled)
	lab.stop_demo()
	var failures = checks.filter(func(row): return not row.passed).size()
	var result = {"passed": failures == 0, "check_count": checks.size(), "checks": checks, "actual_keyboard_events": true, "controller_sha256": FileAccess.get_sha256("res://scripts/zombie.gd"), "main_sha256": FileAccess.get_sha256("res://main.gd"), "asset_sha256": FileAccess.get_sha256("res://assets/Zombie.r4.glb")}
	var file = FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("[R4 Interruption Check] ", checks.size() - failures, "/", checks.size(), " passed | ", report_path)
	quit(0 if failures == 0 else 2)


func _ticks(count: int) -> void:
	for index in range(count):
		await physics_frame


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()

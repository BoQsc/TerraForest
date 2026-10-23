extends SceneTree
## Run the actual lab and wait for contacts/traversal/crawl outcomes.

var checks: Array = []
var report_path = "res://validation/r4.demo.json"


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, passed: bool, details = null) -> void:
	checks.append({"check": label, "passed": passed, "details": details})
	if not passed:
		printerr("[R4 Demo Check] FAIL: ", label, " | ", details)


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			report_path = arg.trim_prefix("--report=")
	var lab = load("res://main.tscn").instantiate()
	root.add_child(lab)
	for index in range(4):
		await process_frame
	Engine.max_fps = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_check("startup keeps Original", lab.get_selected_revision() == "original")
	_check("F1 F2 F4 available; F3 archived", lab.revision_buttons.has("original") and lab.revision_buttons.has("r2") and lab.revision_buttons.has("r4") and not lab.revision_buttons.has("r3"))
	lab.select_revision("r3")
	_check("deprecated R3 cannot replace current subject", lab.get_selected_revision() == "original")
	_check("Run demonstration starts R4", lab.start_demo() and lab.get_selected_revision() == "r4")
	_check("R4 action inspector includes bite crawl jump ladder", lab.action_names.has("Zombie_Attack_Bite") and lab.action_names.has("Zombie_Crawl") and lab.action_names.has("Zombie_Jump") and lab.action_names.has("Zombie_Climb_Ladder"))
	_check("R4 behavior expansion enabled", bool(lab.subject.get_behavior_snapshot().get("r4_actions_enabled", false)), lab.subject.get_behavior_snapshot())
	var previous_stage = ""
	var ticks = 0
	while lab.demonstration.active and not lab.demonstration.complete and ticks < 240 * 110:
		await physics_frame
		ticks += 1
		var stage = lab.demonstration.stage
		if stage != previous_stage:
			print("[R4 Demo Check] Stage: ", stage, " | ", lab.subject.get_behavior_snapshot())
			previous_stage = stage
	var demo: Dictionary = lab.get_demo_snapshot()
	_check("all demo stations complete from controller outcomes", bool(demo.complete), demo)
	var summary: Dictionary = lab.demonstration.completed_cycles[0] if not lab.demonstration.completed_cycles.is_empty() else {}
	var actions: Dictionary = {}
	for contact in summary.get("contacts", []):
		actions[String(contact.action)] = true
	_check("bite left right both contacts demonstrated", actions.has("bite") and actions.has("left") and actions.has("right") and actions.has("both"), actions)
	_check("at least two crawl bite contacts", lab.demonstration.contact_events.filter(func(row): return String(row.action) == "crawl_bite").size() >= 2, lab.demonstration.contact_events)
	_check("target health changes only through confirmed contacts", int(lab.demonstration.target.contacts) == int(demo.contacts) and int(demo.contacts) >= 6 and float(demo.target_health) < 100.0)
	_check("every contact uses the actual visible padding", lab.demonstration.contact_events.size() >= 6 and lab.demonstration.contact_events.all(func(row): return row.visible_target_shapes and float(row.surface_gap_m) <= 0.055), lab.demonstration.contact_events)
	_check("short jump raises the physical root", float(summary.get("jump_peak_y", 0.0)) > 0.12 and float(summary.get("jump_peak_y", 1.0)) < 0.34, summary.get("jump_peak_y"))
	var jump_end: Array = summary.get("jump_end", [0, 0, 0])
	_check("short jump passes the low obstacle", float(jump_end[2]) > -3.10, jump_end)
	var ladder_end: Array = summary.get("ladder_end", [0, 0, 0])
	_check("ladder exits onto elevated platform", float(ladder_end[1]) > 0.87 and float(ladder_end[0]) > 3.65, ladder_end)
	_check("both leg loss keeps zombie alive and crawling", lab.subject.alive and lab.subject.missing.get("thigh_l", false) and lab.subject.missing.get("thigh_r", false) and String(lab.subject.get_behavior_snapshot().get("movement_mode", "")) == "crawling")
	lab.stop_demo()
	_check("Stop returns usable orbit inspection", not lab.demonstration.active and lab.inspecting and not lab.animation_paused and not lab.subject.behavior_enabled and lab.subject.target == lab.player)
	_check("Restart launches a fresh R4 cycle", lab.restart_demo() and lab.demonstration.active and lab.subject.alive and not lab.subject.missing.get("thigh_l", true) and not lab.subject.missing.get("thigh_r", true))
	lab.stop_demo()
	lab.select_revision("r2")
	_check("F2 remains available after demo", lab.selected_revision == "r2" and lab.action_names.size() == 4 and not lab.demonstration.active)
	var failures = checks.filter(func(row): return not row.passed).size()
	var result = {"schema_version": 1, "checks": checks, "passed": failures == 0, "failures": failures, "check_count": checks.size(), "physics_ticks_observed": ticks, "physics_hz": Engine.physics_ticks_per_second, "demo_summary": summary, "final_demo_snapshot": demo, "source_sha256": {"assets/Zombie.r4.glb": FileAccess.get_sha256("res://assets/Zombie.r4.glb"), "scripts/zombie.gd": FileAccess.get_sha256("res://scripts/zombie.gd"), "main.gd": FileAccess.get_sha256("res://main.gd"), "scripts/zombie_demo.gd": FileAccess.get_sha256("res://scripts/zombie_demo.gd"), "scripts/zombie_demo_target.gd": FileAccess.get_sha256("res://scripts/zombie_demo_target.gd")}}
	var file = FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	print("[R4 Demo Check] ", checks.size() - failures, "/", checks.size(), " passed | ", report_path)
	lab.queue_free()
	await process_frame
	quit(0 if failures == 0 else 2)

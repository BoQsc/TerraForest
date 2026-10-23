extends SceneTree

var checks: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _check(name: String, passed: bool, details = null) -> void:
	checks.append({"check": name, "passed": passed, "details": details})
	if not passed:
		printerr("[R4 Inspection Check] FAIL: ", name, " | ", details)


func _run() -> void:
	var lab = load("res://main.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	Engine.max_fps = 0
	lab.select_revision("r4")
	for name in ["Zombie_Crawl_Idle", "Zombie_Climb_Ladder"]:
		lab.select_action(name)
		var player: AnimationPlayer = lab.subject.animation_player
		var clip = player.get_animation(player.assigned_animation)
		var original_loop = clip.loop_mode
		_check(name + " is originally looping", original_loop == Animation.LOOP_LINEAR)
		lab._seek_animation_frame(120)
		for tick in range(8):
			await physics_frame
		_check(name + " holds exact endpoint after8ticks", lab.animation_paused and lab.inspection_frame == 120 and is_equal_approx(player.current_animation_position, 2.0), {"position": player.current_animation_position, "frame": lab.inspection_frame, "loop": clip.loop_mode})
		_check(name + " remains nonlooping while paused", clip.loop_mode == Animation.LOOP_NONE)
		lab._set_animation_paused(false)
		for tick in range(8):
			await physics_frame
		_check(name + " restores loop and resumes from start", clip.loop_mode == original_loop and player.is_playing() and player.current_animation_position > 0.0 and player.current_animation_position < 0.1, player.current_animation_position)
	lab.select_action("Zombie_Crawl_Idle")
	var old = lab.subject.animation_player.get_animation(lab.subject.animation_player.assigned_animation)
	lab._seek_animation_frame(120)
	lab.select_action("Zombie_Climb_Ladder")
	_check("switching a paused action restores old loop metadata", old.loop_mode == Animation.LOOP_LINEAR)
	lab._seek_animation_frame(120)
	lab.select_revision("original")
	_check("revision switch preserves paused inspection", lab.selected_revision == "original" and lab.animation_paused and lab.inspection_frame == 120)
	var failures = checks.filter(func(row): return not row.passed).size()
	var file = FileAccess.open("res://validation/r4.inspection.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures == 0, "checks": checks, "check_count": checks.size(), "asset_sha256": FileAccess.get_sha256("res://assets/Zombie.r4.glb"), "main_sha256": FileAccess.get_sha256("res://main.gd"), "controller_sha256": FileAccess.get_sha256("res://scripts/zombie.gd")}, "\t"))
	file.close()
	print("[R4 Inspection Check] ", checks.size() - failures, "/", checks.size(), " passed")
	lab.queue_free()
	await process_frame
	quit(0 if failures == 0 else 2)

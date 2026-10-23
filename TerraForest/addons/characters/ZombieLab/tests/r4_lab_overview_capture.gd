extends SceneTree
## Two native overview screenshots: untouched F1 startup and final R4 contact pose.

var output_directory = "res://preview"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_directory = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	var lab = load("res://main.tscn").instantiate()
	root.add_child(lab)
	for index in range(4):
		await process_frame
	Engine.max_fps = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lab._update_ui()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_directory.path_join("ui.original.png"))
	var startup_asset = lab.revision_file_label.text
	lab.select_revision("r4")
	lab.select_action("Zombie_Attack_Both")
	lab._seek_animation_frame(42)
	lab._set_inspecting(true)
	lab.inspect_yaw = 0.70
	lab.inspect_pitch = 0.10
	lab.inspect_distance = 3.25
	lab._set_message("R4 · Both hands attack · paused contact frame 042", 10.0)
	lab._update_inspect_camera()
	lab._update_ui()
	for index in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_directory.path_join("lab.r4.png"))
	var position = lab.subject.animation_player.current_animation_position
	var verified = lab.selected_revision == "r4" and lab.animation_paused and lab.inspection_frame == 42 and absf(position - 42.0 / 60.0) < 0.00001 and lab.action_names.size() == 15
	var report = {
		"verified": verified, "native_lab_screenshots": true, "completed_draws_after_pose": 2,
		"startup_asset_label": startup_asset,
		"active_asset_label": lab.revision_file_label.text,
		"animation": lab.subject.animation_player.assigned_animation,
		"frame": lab.inspection_frame, "animation_time": position,
		"camera": {"yaw": lab.inspect_yaw, "pitch": lab.inspect_pitch, "distance": lab.inspect_distance},
		"source_sha256": {
			"main.gd": FileAccess.get_sha256("res://main.gd"),
			"assets/Zombie.glb": FileAccess.get_sha256("res://assets/Zombie.glb"),
			"assets/Zombie.r4.glb": FileAccess.get_sha256("res://assets/Zombie.r4.glb"),
			"assets/Zombie.r4.behavior.json": FileAccess.get_sha256("res://assets/Zombie.r4.behavior.json")
		}
	}
	var file = FileAccess.open(output_directory.path_join("lab.overview.manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[R4 Lab Overview] verified=", verified, " | ", output_directory)
	quit(0 if verified else 2)

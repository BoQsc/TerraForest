extends SceneTree
const Policy = preload("res://addons/presentation/fullscreen_policy.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	Policy.apply(root)
	await process_frame
	await process_frame
	# Exercise recovery after an external/test override, without a per-frame setter.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Policy.restore_vsync()
	await process_frame
	await RenderingServer.frame_post_draw
	var state: Dictionary = Policy.measurement(root)
	state["vsync_mode"] = DisplayServer.window_get_vsync_mode()
	state["renderer"] = RenderingServer.get_current_rendering_method()
	state["adapter"] = RenderingServer.get_video_adapter_name()
	state["refresh_hz"] = DisplayServer.screen_get_refresh_rate()
	state["scanout_verified"] = false
	var captured: Vector2i = root.get_texture().get_image().get_size()
	state["captured_size"] = [captured.x, captured.y]
	state["pass"] = state["fair_graphical_sample"] and captured == Policy.RESOLUTION and state["vsync_mode"] == DisplayServer.VSYNC_ENABLED and state["window_mode"] == DisplayServer.WINDOW_MODE_FULLSCREEN
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/presentation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(state, "  "))
	file.close()
	print("PASS " if state["pass"] else "FAIL ", "1920x1080 fullscreen render and captured output: ", state)
	quit(0 if state["pass"] else 1)

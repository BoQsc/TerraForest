extends "res://tests/runtime_behavior_check.gd"
## Native rendered side view of a live R4 ladder climb and ragdoll release.
## Use --write-movie /absolute/path/ladder.avi --fixed-fps 60 (no --headless).

var frame_label: Label
var movie_frames := 0
var collapse_active := false
var collapse_seconds := 0.0
var collapse_tick := 0
var maximum_hand_angular := 0.0
var maximum_hand_speed := 0.0
var peak: Dictionary = {}
var hand_samples: Array[Dictionary] = []
var capture_directory := "res://preview/ladder.collapse"
var camera_position := Vector3(3.1, 1.70, 4.4)
var camera_target := Vector3(0.10, 1.05, -0.35)
var camera_fov := 35.0
var view_name := "grip"


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-directory="):
			capture_directory = argument.trim_prefix("--capture-directory=")
		elif argument == "--view=collapse":
			view_name = "collapse"
			camera_position = Vector3(-3.2, 2.15, -4.2)
			camera_target = Vector3(0.10, 0.95, -0.70)
			camera_fov = 44.0
	call_deferred("run")


func _physics_process(delta: float) -> bool:
	if not collapse_active or not is_instance_valid(zombie):
		return false
	collapse_seconds += delta
	collapse_tick += 1
	var bones: Dictionary = zombie.get("physical_bones")
	for key in ["LeftHand", "RightHand"]:
		if not bones.has(key):
			continue
		var body: PhysicalBone3D = bones[key]
		if not body.is_simulating_physics():
			continue
		var angular := body.angular_velocity.length()
		var speed := body.linear_velocity.length()
		var sample := {"tick": collapse_tick, "seconds_after_release": collapse_seconds, "hand": key, "angular_speed_radps": angular, "speed_mps": speed, "position": [body.global_position.x, body.global_position.y, body.global_position.z]}
		var camera := root.get_camera_3d()
		if camera != null:
			var pixel := camera.unproject_position(body.global_position)
			sample["screen_pixel"] = [pixel.x, pixel.y]
		hand_samples.append(sample)
		maximum_hand_speed = maxf(maximum_hand_speed, speed)
		if angular > maximum_hand_angular:
			maximum_hand_angular = angular
			peak = sample
	return false


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.80
	return material


func _show_boxes(node: Node, material: Material) -> void:
	for child in node.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			var visual := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = (child.shape as BoxShape3D).size
			visual.mesh = box
			visual.transform = child.transform
			visual.material_override = material
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			node.add_child(visual)
		elif not child is MeshInstance3D:
			_show_boxes(child, material)


func _stage() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.028, 0.041, 0.051)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.65, 0.73, 0.81)
	settings.ambient_light_energy = 0.6
	environment.environment = settings
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-43, -27, 0)
	light.light_energy = 1.9
	light.shadow_enabled = true
	world.add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(2.0, 3.0, -2.0)
	fill.omni_range = 8.0
	fill.light_color = Color(0.76, 0.89, 1.0)
	fill.light_energy = 0.65
	world.add_child(fill)
	var camera := Camera3D.new()
	camera.position = camera_position
	camera.fov = camera_fov
	world.add_child(camera)
	camera.look_at(camera_target, Vector3.UP)
	camera.current = true
	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	var title := Label.new()
	title.position = Vector2(28, 22)
	title.text = "R4  /  LADDER RELEASE  /  " + view_name.to_upper() + " VIEW\nNative physics · palm + finger collision shapes"
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color(0.84, 0.94, 0.95))
	canvas.add_child(title)
	frame_label = Label.new()
	frame_label.position = Vector2(28, 720)
	frame_label.add_theme_font_size_override("font_size", 19)
	canvas.add_child(frame_label)


func _frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	movie_frames += 1
	frame_label.text = "Frame %03d   %s" % [movie_frames, "Release +%.3f s" % collapse_seconds if collapse_active else "Climbing toward the next rung"]


func run() -> void:
	_record_version_inputs()
	if checks.any(func(check): return not bool(check.passed)):
		print("LADDER_CAPTURE_FAILED: native import cache does not match the current source")
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	world = Node3D.new()
	root.add_child(world)
	var floor := _box(world, Vector3(0, -0.10, 0), Vector3(40, 0.20, 40))
	_show_boxes(floor, _material(Color(0.095, 0.12, 0.13)))
	_stage()
	await _spawn("r4", Vector3(0, 0.025, -0.4))
	target.position = Vector3(8, 0, 8)
	var ladder := _make_ladder()
	_show_boxes(fixtures, _material(Color(0.27, 0.32, 0.34)))
	await _frame()
	var accepted := bool(zombie.call("request_climb", ladder))
	if not accepted:
		print("LADDER_CAPTURE_FAILED ", _snapshot())
		quit(1)
		return
	var guard := 0
	while guard < 180:
		await _frame()
		guard += 1
		if String(_snapshot().traversal_state) == "ladder_climb" and (zombie.get("animation_player") as AnimationPlayer).current_animation_position >= 0.88:
			break
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_directory))
	root.get_texture().get_image().save_png(capture_directory.path_join("before.release.png"))
	var source_pose := _snapshot()
	zombie.call("die", Vector3(0.4, 0.0, -0.8))
	collapse_active = true
	for frame in 210:
		await _frame()
		if frame < 90 or frame in [119, 179, 209]:
			root.get_texture().get_image().save_png(capture_directory.path_join("release.%03d.png" % frame))
	_check_version_inputs()
	var inputs_valid := checks.all(func(check): return bool(check.passed))
	var report := {"inputs_valid": inputs_valid, "version_inputs": version_inputs, "input_checks": checks, "source_pose": source_pose, "movie_frames_after_setup": movie_frames, "maximum_hand_angular_speed_radps": maximum_hand_angular, "maximum_hand_speed_mps": maximum_hand_speed, "peak": peak, "physics_samples": hand_samples, "source_glb_sha256": FileAccess.get_sha256("res://assets/Zombie.r4.glb"), "controller_sha256": FileAccess.get_sha256("res://scripts/zombie.gd"), "camera": {"name": view_name, "position": [camera_position.x, camera_position.y, camera_position.z], "target": [camera_target.x, camera_target.y, camera_target.z], "fov": camera_fov}, "note": "Native renderer and native physics. Inspect the video/stills separately from numeric peak thresholds."}
	var file := FileAccess.open(capture_directory.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("LADDER_CAPTURE_COMPLETE ", JSON.stringify({"path": capture_directory, "peak": peak}))
	quit(0 if inputs_valid else 1)

extends SceneTree
## Native Godot capture: every integer animation frame, four simultaneous views.
## The complete shipped R4 model is instantiated through its actual controller.
## No material, shape key, rig, mesh or animation is rewritten by this script.

const VIEW_NAMES = ["FRONT", "RIGHT", "BACK", "LEFT"]
const VIEW_DIRECTIONS = [Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)]
const PANEL = Vector2i(384, 448)
const ATLAS_ROWS = 6
var output = "/tmp/zombie_r4_behavior_frames"
var manifest_name = "frame.manifest.json"
var requested_clips: Array[String] = []
var frame_step = 1
var subject
var stage: Node3D
var views: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var labels: Array[Label] = []
var frames: Array[Dictionary] = []
var atlases: Array[Dictionary] = []
var source_hashes: Dictionary = {}
var report: Dictionary = {}
var record_singles = true
var detail_mode = "body"
var import_identity: Dictionary = {}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--manifest-name="):
			manifest_name = argument.trim_prefix("--manifest-name=").get_file()
		elif argument.begins_with("--clips="):
			for clip in argument.trim_prefix("--clips=").split(","):
				requested_clips.append(clip)
		elif argument.begins_with("--step="):
			frame_step = maxi(1, int(argument.trim_prefix("--step=")))
		elif argument == "--no-singles":
			record_singles = false
		elif argument.begins_with("--detail="):
			detail_mode = argument.trim_prefix("--detail=")
	call_deferred("run")


func _material(color: Color) -> StandardMaterial3D:
	var result = StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.9
	return result


func _build_stage() -> void:
	stage = Node3D.new()
	stage.name = "BehaviorFrameReview"
	root.add_child(stage)
	current_scene = stage
	var world = World3D.new()
	for index in range(4):
		var viewport = SubViewport.new()
		viewport.name = VIEW_NAMES[index]
		viewport.size = PANEL
		viewport.world_3d = world
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.msaa_3d = Viewport.MSAA_2X
		stage.add_child(viewport)
		views.append(viewport)
		var camera = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 2.55
		camera.near = .03
		viewport.add_child(camera)
		camera.current = true
		cameras.append(camera)
		var canvas = CanvasLayer.new()
		viewport.add_child(canvas)
		var label = Label.new()
		label.position = Vector2(10, 8)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(0.91, .95, 1.0))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, .9))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		canvas.add_child(label)
		labels.append(label)
	var world_root = Node3D.new()
	views[0].add_child(world_root)
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("111c28")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b6c4d4")
	env.ambient_light_energy = .8
	environment.environment = env
	world_root.add_child(environment)
	var key = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -25, 0)
	key.light_energy = 1.45
	world_root.add_child(key)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 145, 0)
	fill.light_energy = .75
	fill.light_color = Color("b8cfff")
	world_root.add_child(fill)
	var floor_mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	floor_mesh.material_override = _material(Color("23313c"))
	floor_mesh.position.y = -.01
	world_root.add_child(floor_mesh)
	subject = load("res://scripts/zombie.gd").new()
	subject.model_path = "res://assets/Zombie.r4.glb"
	subject.model_scene = load(subject.model_path)
	subject.revision_id = "r4"
	subject.behavior_enabled = false
	world_root.add_child(subject)
	subject.set_behavior(false)
	subject.set_physics_process(false)
	subject.set_process(false)
	for index in range(4):
		var center = Vector3(0, 1.1, .0)
		cameras[index].global_position = center + VIEW_DIRECTIONS[index] * 3.5 + Vector3(0, .13, 0)
		cameras[index].look_at(center, Vector3.UP)


func _clip_key(clip: String) -> String:
	for key in subject.animation_player.get_animation_list():
		if String(key).get_file() == clip:
			return String(key)
	return ""


func _inspect_import_identity() -> Dictionary:
	var path = "res://assets/Zombie.r4.glb"
	var settings = ConfigFile.new()
	var imported_source_md5 = ""
	var compiled = ""
	if settings.load(path + ".import") == OK:
		compiled = String(settings.get_value("remap", "path", ""))
		var metadata = compiled.get_basename() + ".md5"
		if FileAccess.file_exists(metadata):
			for line in FileAccess.get_file_as_string(metadata).split("\n"):
				if line.begins_with("source_md5="):
					imported_source_md5 = line.get_slice('"', 1)
	var source_md5 = FileAccess.get_md5(path)
	return {"source_md5": source_md5, "compiled_source_md5": imported_source_md5,
		"compiled_path": compiled, "compiled_sha256": FileAccess.get_sha256(compiled) if not compiled.is_empty() else "",
		"passed": not imported_source_md5.is_empty() and source_md5 == imported_source_md5}


func _pose_facts(clip: String, frame: int) -> Dictionary:
	var finite = true
	var arm_lengths: Dictionary = {}
	var transforms = PackedFloat32Array()
	var skeleton: Skeleton3D = subject.skeleton
	for index in range(skeleton.get_bone_count()):
		var pose = skeleton.get_bone_global_pose(index)
		finite = finite and pose.is_finite()
		for column in [pose.basis.x, pose.basis.y, pose.basis.z, pose.origin]:
			transforms.append_array(PackedFloat32Array([column.x, column.y, column.z]))
	for side in ["Left", "Right"]:
		var a = skeleton.get_bone_global_pose(skeleton.find_bone(side + "Arm")).origin
		var b = skeleton.get_bone_global_pose(skeleton.find_bone(side + "ForeArm")).origin
		var c = skeleton.get_bone_global_pose(skeleton.find_bone(side + "Hand")).origin
		arm_lengths[side] = [a.distance_to(b), b.distance_to(c)]
	var digest = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(transforms.to_byte_array())
	return {"clip": clip, "frame": frame, "time_seconds": float(frame) / 60.0,
		"assigned_clip": String(subject.animation_player.assigned_animation).get_file(),
		"actual_time_seconds": subject.animation_player.current_animation_position,
		"bones": skeleton.get_bone_count(), "finite": finite, "arm_lengths_m": arm_lengths,
		"bone_pose_sha256": digest.finish().hex_encode(), "render_frame": Engine.get_frames_drawn(),
		"root_position_m": [subject.position.x, subject.position.y, subject.position.z]}


func _save_report(complete: bool) -> void:
	var changed: Array[String] = []
	for path in source_hashes:
		if FileAccess.get_sha256("res://" + path) != source_hashes[path]:
			changed.append(path)
	var passed = complete and changed.is_empty() and bool(import_identity.get("passed", false))
	for row in frames:
		passed = passed and row.finite and row.assigned_clip == row.clip
		passed = passed and bool(row.get("two_vs_three_draw_pixels_identical", false))
		passed = passed and absf(float(row.actual_time_seconds) - float(row.time_seconds)) < 0.00001
		if detail_mode == "mouth":
			passed = passed and float(row.get("mouth_camera_focus_error_m", INF)) < 0.00001
		if record_singles:
			passed = passed and row.save_error == OK and not String(row.image_sha256).is_empty()
	for atlas in atlases:
		passed = passed and atlas.save_error == OK and not String(atlas.image_sha256).is_empty()
	report.merge({"complete": complete, "passed": passed, "source_sha256": source_hashes,
		"import_identity": import_identity,
		"source_files_changed": changed, "frame_count": frames.size(), "view_pose_count": frames.size() * 4,
		"frames": frames, "atlases": atlases, "engine": Engine.get_version_info().string,
		"frame_step": frame_step, "views": VIEW_NAMES, "per_view_resolution": [PANEL.x, PANEL.y],
		"detail_mode": detail_mode,
		"ladder_presentation": "Declared 0.30m/s upward root travel is applied during ladder review; cameras follow the same root. Actual lab traversal is validated separately.",
		"method": "Native complete R4 model; exact AnimationPlayer seek; two complete renders to settle GPU skin upload; four shared-world camera views. Every clip start/end also compares a third draw pixel-for-pixel.",
		"limits": ["Image generation is evidence capture. Human/model visual inspection is recorded separately; generation alone is not a visual pass.",
			"Independent animation presentation uses neutral review lighting. Gameplay is also checked separately in the actual lab."]}, true)
	var file = FileAccess.open(output.path_join(manifest_name), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))


func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	DirAccess.make_dir_recursive_absolute(output.path_join("atlases"))
	for path in ["assets/Zombie.r4.glb", "assets/Zombie.r4.glb.import", "assets/Zombie.r4.behavior.json", "scripts/zombie.gd", "tools/capture_behavior_frames.gd"]:
		source_hashes[path] = FileAccess.get_sha256("res://" + path)
	import_identity = _inspect_import_identity()
	if not bool(import_identity.passed):
		push_error("The compiled R4 import does not match the current GLB. Import the final project before capture.")
		_save_report(false)
		quit(3)
		return
	_build_stage()
	await process_frame
	await process_frame
	var clips: Array[String] = []
	for key in subject.animation_player.get_animation_list():
		var clip = String(key).get_file()
		if clip.begins_with("Zombie_") and (requested_clips.is_empty() or clip in requested_clips):
			clips.append(clip)
	clips.sort()
	for clip in clips:
		var key = _clip_key(clip)
		var animation: Animation = subject.animation_player.get_animation(key)
		var last = roundi(animation.length * 60.0)
		subject.play_clip(clip)
		subject.animation_player.pause()
		var original_loop = animation.loop_mode
		animation.loop_mode = Animation.LOOP_NONE
		for view in range(4):
			var center = Vector3(0, 1.1, 0)
			cameras[view].size = 2.55
			if "Crawl" in clip:
				center = Vector3(0, .80, -.30)
				cameras[view].size = 2.85
			cameras[view].global_position = center + VIEW_DIRECTIONS[view] * 3.5 + Vector3(0, .13, 0)
			cameras[view].look_at(center, Vector3.UP)
		var image_atlas: Image
		var atlas_start = 0
		var rows_in_atlas = 0
		var sampled: Array[int] = []
		for index in range(0, last + 1, frame_step):
			sampled.append(index)
		if sampled.back() != last:
			sampled.append(last)
		for frame in sampled:
			if rows_in_atlas == 0:
				image_atlas = Image.create(PANEL.x * 4, PANEL.y * ATLAS_ROWS, false, Image.FORMAT_RGB8)
				image_atlas.fill(Color("111c28"))
				atlas_start = frame
			subject.position = Vector3.ZERO
			if clip == "Zombie_Climb_Ladder":
				subject.position.y = .30 * float(frame) / 60.0
			subject.animation_player.seek(float(frame) / 60.0, true)
			subject.skeleton.force_update_all_bone_transforms()
			# Let the sought skeleton settle before following its head with the close-up camera.
			await process_frame
			for view in range(4):
				var center = Vector3(0, 1.1, 0) + subject.position
				cameras[view].size = 2.55
				if "Crawl" in clip:
					center = Vector3(0, .80, -.30) + subject.position
					cameras[view].size = 2.85
				if detail_mode == "mouth":
					var head: Transform3D = subject.skeleton.global_transform * subject.skeleton.get_bone_global_pose(subject.skeleton.find_bone("Head"))
					center = head * Vector3(0, .10, 0)
					cameras[view].size = .56
				cameras[view].global_position = center + VIEW_DIRECTIONS[view] * 3.5 + Vector3(0, .10 if detail_mode == "body" else .025, 0)
				cameras[view].look_at(center, Vector3.UP)
				labels[view].text = "%s  ·  F%03d / %03d\n%s  ·  R4  ·  60 Hz" % [clip.trim_prefix("Zombie_"), frame, last, VIEW_NAMES[view]]
			# Skin uploads settle one render after the skeleton; hold the same exact pose for two complete draws.
			await RenderingServer.frame_post_draw
			await process_frame
			await RenderingServer.frame_post_draw
			var strip = Image.create(PANEL.x * 4, PANEL.y, false, Image.FORMAT_RGB8)
			for view in range(4):
				var image = views[view].get_texture().get_image()
				image.convert(Image.FORMAT_RGB8)
				strip.blit_rect(image, Rect2i(Vector2i.ZERO, PANEL), Vector2i(PANEL.x * view, 0))
			var settle_verified = frame == 0 or frame == last
			var settle_stable = true
			if settle_verified:
				await process_frame
				await RenderingServer.frame_post_draw
				var confirm_strip = Image.create(PANEL.x * 4, PANEL.y, false, Image.FORMAT_RGB8)
				for view in range(4):
					var confirm_image = views[view].get_texture().get_image()
					confirm_image.convert(Image.FORMAT_RGB8)
					confirm_strip.blit_rect(confirm_image, Rect2i(Vector2i.ZERO, PANEL), Vector2i(PANEL.x * view, 0))
				settle_stable = strip.get_data() == confirm_strip.get_data()
			image_atlas.blit_rect(strip, Rect2i(0, 0, PANEL.x * 4, PANEL.y), Vector2i(0, rows_in_atlas * PANEL.y))
			var facts = _pose_facts(clip, frame)
			facts["two_draw_settle_verified"] = settle_verified
			facts["two_vs_three_draw_pixels_identical"] = settle_stable
			if detail_mode == "mouth":
				var final_head = subject.skeleton.global_transform * subject.skeleton.get_bone_global_pose(subject.skeleton.find_bone("Head"))
				var final_center = final_head * Vector3(0, .10, 0)
				var focus_error = 0.0
				for view in range(4):
					var used_center = cameras[view].global_position - VIEW_DIRECTIONS[view] * 3.5 - Vector3(0, .025, 0)
					focus_error = maxf(focus_error, used_center.distance_to(final_center))
				facts["mouth_camera_focus_error_m"] = focus_error
			if record_singles:
				var filename = "frames/%s.%03d.png" % [clip, frame]
				facts["file"] = filename
				facts["save_error"] = strip.save_png(output.path_join(filename))
				facts["image_sha256"] = FileAccess.get_sha256(output.path_join(filename))
			frames.append(facts)
			rows_in_atlas += 1
			if rows_in_atlas == ATLAS_ROWS or frame == last:
				if rows_in_atlas != ATLAS_ROWS:
					image_atlas = image_atlas.get_region(Rect2i(0, 0, PANEL.x * 4, PANEL.y * rows_in_atlas))
				var filename = "atlases/%s.%03d-%03d.png" % [clip, atlas_start, frame]
				var error = image_atlas.save_png(output.path_join(filename))
				atlases.append({"file": filename, "clip": clip, "first_frame": atlas_start, "last_frame": frame,
					"rows": rows_in_atlas, "save_error": error, "image_sha256": FileAccess.get_sha256(output.path_join(filename))})
				rows_in_atlas = 0
		animation.loop_mode = original_loop
		_save_report(false)
		print("R4_FRAME_CAPTURE ", clip, " frames=", sampled.size(), " total=", frames.size())
	_save_report(true)
	print("R4_FRAME_CAPTURE_COMPLETE ", output, " frames=", frames.size(), " passed=", report.passed)
	quit(0 if report.passed else 3)

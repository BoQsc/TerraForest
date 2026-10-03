# SPDX-License-Identifier: 0BSD
extends Node3D
const Presentation = preload("res://addons/presentation/fullscreen_policy.gd")
const Stream = preload("res://addons/volumetric_terrain/terrain_world.gd")
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Bench = preload("res://demo/benchmark.gd")
const Assets = preload("res://addons/volumetric_terrain/runtime_assets.gd")
var terrain = Stream.new()
var player := CharacterBody3D.new()
var camera := Camera3D.new()
var sun := DirectionalLight3D.new()
var hud := Label.new()
var status := Label.new()
var help := Label.new()
var pointer := MeshInstance3D.new()
var tool: int = 3
var radius: float = 4.0
var material_id: int = 1
var fly: bool = false
var waiting_spawn: bool = true
var needs_floor_spawn: bool = true
var spawn_token: int = 0
var pending_spawn := Vector3(960, 0, 1310)
var spawn_override_y: float = -1.0
var site: int = 0
var biome_site: int = 0
var yaw: float = 0.0
var pitch: float = -0.10
var cooldown: float = 0.0
var held_previous: bool = false
var last_capture_signature: Dictionary = {}
var duplicate_surface_samples: int = 0
var terrain_pick_serial: int=100000000
var terrain_pick_request: Dictionary={}
var terrain_pick_cache: Dictionary={}

func _terrain_pick_received(reply: Dictionary) -> void:
	if terrain_pick_request.is_empty() or reply.get("token",-1)!=terrain_pick_request.token: return
	var request:=terrain_pick_request
	terrain_pick_request={}
	terrain_pick_cache={}
	if reply.get("status","")!="hit" or not reply.has("normal"): return
	var normal: Vector3=reply.normal
	if normal.length_squared()<0.5: return
	terrain_pick_cache={"from":request["from"],"to":request["to"],"revision":reply.revision,"epoch":reply.epoch,"position":reply.position,"normal":normal}

func _terrain_pick(from: Vector3, to: Vector3) -> Dictionary:
	if terrain.pending_edit: return {}
	if not terrain_pick_cache.is_empty():
		if terrain_pick_cache.revision==terrain.native_revision and terrain_pick_cache.epoch==terrain.epoch and terrain_pick_cache["from"].is_equal_approx(from) and terrain_pick_cache["to"].is_equal_approx(to):
			# A canonical hit is not permission to edit invisible terrain. Keep
			# loading until a current visible owner can publish this operation.
			var position: Vector3=terrain_pick_cache.position
			terrain.set_interaction_target(position)
			for size: int in [16,32,64,128,256]:
				var key:=Vector3i(floori(position.x/size)*size,floori(position.z/size)*size,size)
				if terrain.tiles.has(key) and terrain.tiles[key].get("active",false) and not terrain.tiles[key].dirty:
					return {"position":position,"normal":terrain_pick_cache.normal}
			return {}
		terrain_pick_cache={}
	if terrain_pick_request.is_empty():
		terrain_pick_serial+=1
		if terrain.request_density_ray(from,to,terrain_pick_serial,256):
			terrain_pick_request={"token":terrain_pick_serial,"from":from,"to":to}
	return {}

func _same_pending_surface(center: Vector3, shape: int, add: bool) -> bool:
	# The picking collider remains the published surface until atomic commit.
	# Do not enqueue an identical stamp against it repeatedly while it is stale.
	if last_capture_signature.is_empty() or not terrain.pending_edit:
		return false
	return int(last_capture_signature["revision"]) == terrain.published_revision and int(last_capture_signature["shape"]) == shape and bool(last_capture_signature["add"]) == add and int(last_capture_signature["material"]) == material_id and is_equal_approx(float(last_capture_signature["radius"]), radius) and center.distance_to(last_capture_signature["center"]) < 0.001

func _record_capture(center: Vector3, shape: int, add: bool) -> void:
	last_capture_signature = {"revision": terrain.published_revision, "center": center,
		"shape": shape, "add": add, "radius": radius, "material": material_id}

var last_brush := Vector3.ZERO
var last_brush_add: bool = false
var stroke_valid: bool = false
var hud_timer: float = 0.0
var reset_deadline: int = 0
var frame_samples: Array[float] = []
var move_input := Vector3.ZERO
var benchmark: Node = null
var shutdown_requested: bool = false
var max_fps: int = 60
var latest_hit: Dictionary = {}
var placement_rejections: int = 0
var placement_message_us: int = 0
var terrain_material := ShaderMaterial.new()
var start_ms: int = 0
var benchmark_enabled: bool = false
var temporary_world: bool = false
var gpu_timing_enabled: bool = false
var frame_debug: bool = false
const ControllerState = preload("res://demo/controller_state.gd")
var controls = ControllerState.new()
var movement: RefCounted
var flashlight := SpotLight3D.new()
var app_focused: bool = true
var background_fps: int = 15
var last_frame_us: int = 0
var last_physics_us: int = 0
var wall_frame_ms: float = 0.0
var worst_wall_ms: float = 0.0
var physics_cpu_ms: float = 0.0
var stop_latency_ms: float = -1.0
var stop_draw_latency_ms: float = -1.0
var motion_latency_ms: float = -1.0
var stop_draw_pending_us: int = 0
var hitch_count: int = 0
var input_vector := Vector3.ZERO
var planar_speed: float = 0.0
var debug_material: bool = false
var debug_visibility: bool = false
var visual_debug: int = 0
var fitted_surface: bool = false
var use_cached_sun: bool = true
var journal: FileAccess
var journal_timer: float = 0.0

const StrokeBuffer = preload("res://demo/brush_stroke.gd")
var stroke_buffer = StrokeBuffer.new()
var loading_layer := CanvasLayer.new()
var loading_label := Label.new()
var loading_progress := ProgressBar.new()
var loading_active: bool = true
var loading_reason: String = "Preparing world"
var loading_started_us: int = 0
var loading_ready_frames: int = 0
var travel_blocked_s: float = 0.0
var structure_motion_blocked: bool = false

func _additional_motion_ready(_delta: float) -> bool:
	return true
var record_interaction: bool = false
var journal_failure_reported: bool = false

func _ready() -> void:
	if not ClassDB.class_exists("NativePlayerMovement"):
		GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	if not ClassDB.class_exists("NativePlayerMovement"):
		push_error("Native player movement unavailable")
		get_tree().quit(2)
		return
	movement=ClassDB.instantiate("NativePlayerMovement")
	Presentation.apply(get_window())
	start_ms = Time.get_ticks_msec()
	get_tree().auto_accept_quit = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--world-slot="):
			terrain.save_slot=arg.get_slice("=",1)
		if arg.begins_with("--world-generator="):
			terrain.backend.world_generator=int(arg.get_slice("=",1))
		if arg.begins_with("--world-seed="):
			terrain.backend.world_seed=int(arg.get_slice("=",1))
		if arg == "--nearby-first":
			terrain.nearby_first = true
		if arg == "--smooth-surface":
			fitted_surface = true
		if arg == "--benchmark" or arg == "--soak":
			benchmark_enabled = true
		if arg in ["--temporary", "--benchmark", "--soak", "--snapshot-readonly"]:
			temporary_world = true
		if arg == "--record-interaction":
			record_interaction = true
		if arg.begins_with("--max-fps="):
			max_fps = maxi(0, int(arg.get_slice("=", 1)))
	DisplayServer.window_set_title("Terrain Rewrite 0.4.6-r4")
	Input.use_accumulated_input = false
	Engine.physics_jitter_fix = 0.0
	# Keep normal physics catch-up capacity; all ticks read CURRENT key state.
	process_physics_priority = -100
	RenderingServer.frame_post_draw.connect(_frame_drawn)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://reports"))
	# Optional diagnostics, not unconditional disk I/O during gameplay.
	if record_interaction:
		journal = FileAccess.open("user://reports/interaction_%d_%d.csv" % [OS.get_process_id(), int(Time.get_unix_time_from_system())], FileAccess.WRITE)
	if journal != null and journal.is_open():
		journal.store_line("time_us,wall_frame_ms,physics_cpu_ms,desired_x,desired_z,planar_speed,release_to_physics_ms,release_to_draw_callback_ms,edit_queue_ms,edit_worker_ms,edit_total_build_ms,publish_unit_ms,publish_frame_ms,edit_to_publish_ms,edit_to_draw_callback_ms,queued,staging,hitches,staging_wait_ms,mesh_upload_ms,collision_piece_ms,retire_ms,receive_ms,schedule_ms,commit_ms,geometry_tiles,lighting_tiles,active_worker")
	Engine.max_fps = max_fps
	_setup_scene()
	_setup_hud()
	_setup_loading()
	_begin_loading("Loading saved world and preparing terrain")
	var prepared_material: ShaderMaterial = Assets.make_terrain_material()
	if prepared_material == null:
		_message("Terrain assets could not be loaded. Read the startup log in reports.")
		get_tree().quit(2)
		return
	terrain_material = prepared_material
	add_child(terrain)
	terrain.initialized.connect(_terrain_initialized)
	terrain.height_received.connect(_height_ready)
	terrain.density_ray_received.connect(_terrain_pick_received)
	terrain.message_changed.connect(_message)
	terrain.edit_published.connect(_edited)
	terrain.reload_started.connect(_loading_reload)
	var error: Error = terrain.start(terrain_material, temporary_world)
	if error != OK:
		_message("Native TerrainCore failed to load. Run run_tests.bat and read logs. Error %d" % error)
		push_error(status.text)
		terrain.latest_error = status.text
		if benchmark_enabled:
			get_tree().quit(2)
		return
	gpu_timing_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	if gpu_timing_enabled:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if loading_active else Input.MOUSE_MODE_CAPTURED
	if benchmark_enabled:
		benchmark = Bench.new()
		benchmark.host = self
		add_child(benchmark)

func _setup_scene() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.29, 0.45, 0.65)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.72, 0.81)
	environment.ambient_light_energy = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = false
	world_environment.environment = environment
	add_child(world_environment)
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 256.0
	# Restore useful depth separation on broad smooth terrain. 0.02/0.25
	# is a likely source of the reported contour/moire-like shadow acne.
	sun.shadow_bias = 0.10
	sun.shadow_normal_bias = 2.0
	add_child(sun)
	player.name = "Player"
	player.collision_layer = 2
	player.collision_mask = 1
	player.floor_snap_length = 0.35
	player.floor_max_angle = deg_to_rad(48.0)
	player.floor_constant_speed = true
	player.safe_margin = 0.01
	player.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var shape := CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.9
	player.add_child(collider)
	camera.position.y = 1.68
	camera.fov = 75.0
	camera.near = 0.08
	camera.far = 3300.0
	camera.current = true
	player.add_child(camera)
	flashlight.name = "Flashlight"
	flashlight.visible = false
	flashlight.light_energy = 2.8
	flashlight.light_color = Color(1.0, 0.94, 0.84)
	flashlight.spot_range = 36.0
	flashlight.spot_angle = 42.0
	flashlight.spot_angle_attenuation = 0.65
	flashlight.shadow_enabled = true
	# R4: the sun had been repaired, but this spotlight still used tiny biases.
	# Restore documented Light3D defaults; do NOT disable roof shadowing.
	flashlight.shadow_bias = 0.1
	flashlight.shadow_normal_bias = 2.0
	flashlight.position = Vector3(0.12, -0.12, -0.16)
	camera.add_child(flashlight)
	add_child(player)
	player.position = Vector3(960, 90, 1310)
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.012
	pointer.mesh = box
	pointer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var preview := StandardMaterial3D.new()
	preview.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview.albedo_color = Color(0.3, 0.85, 0.65, 0.16)
	pointer.material_override = preview
	pointer.visible = false
	add_child(pointer)

func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	for label: Label in [hud, status, help]:
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		canvas.add_child(label)
	hud.position = Vector2(14, 10)
	status.position = Vector2(14, 362)
	status.text = "Loading native mesher and cached LODs..."
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_left = 14
	help.offset_top = -62
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "WASD move | mouse look | Shift sprint | Space jump | G fly | LMB dig / RMB build | 1 cube / 2 grid box / 3 sphere / 4 box | wheel radius | Q/E material\nF2 sites | F3 construction | F4 biomes | F5 save | F9 load | F11 fullscreen | F6 LOD colors | F7 shadows / Ctrl+F7 cavity sun | F8 flashlight | F10 diagnostics | Esc mouse | Ctrl+R twice reset"
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 25)
	canvas.add_child(crosshair)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(7, 16)

func _setup_loading() -> void:
	loading_layer.layer = 50
	add_child(loading_layer)
	var background := ColorRect.new()
	background.color = Color(0.035, 0.045, 0.06, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_layer.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := VBoxContainer.new()
	panel.position = Vector2(100, 180)
	panel.custom_minimum_size = Vector2(900, 220)
	loading_layer.add_child(panel)
	loading_label.add_theme_font_size_override("font_size", 23)
	loading_label.text = "Loading terrain..."
	panel.add_child(loading_label)
	loading_progress.custom_minimum_size = Vector2(900, 20)
	loading_progress.show_percentage = false
	panel.add_child(loading_progress)
	var explanation := Label.new()
	explanation.text = "Waiting for complete map coverage and nearby collision.\nThe game is not accepting movement yet; no input is being queued.\nLarge saved worlds take longer. No world data is erased."
	if terrain.nearby_first:
		explanation.text = "Nearby-first: load a safe inner region, then stream distant terrain.\nThe initial view is explicitly limited to 320 m until outer coverage is ready.\nThe game is not accepting movement yet; no input is being queued."
	panel.add_child(explanation)
	var quit_button := Button.new()
	quit_button.text = "Save and quit"
	quit_button.pressed.connect(func() -> void: _notification(NOTIFICATION_WM_CLOSE_REQUEST))
	panel.add_child(quit_button)

func _loading_reload() -> void:
	_begin_loading("Reloading world")

func _begin_loading(reason: String) -> void:
	loading_active = true
	loading_reason = reason
	loading_started_us = Time.get_ticks_usec()
	loading_ready_frames = 0
	terrain.initial_loading = true
	loading_layer.visible = true
	stroke_buffer.clear()
	_clear_motion()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _update_loading() -> void:
	if not loading_active:
		return
	var state: Dictionary = terrain.loading_state(player.position, fly)
	loading_label.text = loading_reason + "\n"
	loading_label.text += "World overview: %d/%d regions | Local collision: %d/%d\n" % [state["roots"], state["root_total"], state["local"], state["local_total"]]
	if terrain.nearby_first:
		loading_label.text += "Nearby-first: explicit 320 m view until outer coverage is ready\n"
	loading_label.text += "Worker: %s | queued %d | elapsed %.1f s" % [state["worker"], state["queued"], float(Time.get_ticks_usec() - loading_started_us) / 1000000.0]
	loading_progress.max_value = maxf(1.0, float(state["root_total"] + state["local_total"]))
	loading_progress.value = float(state["roots"] + state["local"])
	if terrain.latest_error != "":
		loading_label.text = "Loading failed\n" + terrain.latest_error + "\nRead the startup log in reports."
		return
	if bool(state["ready"]) and not waiting_spawn:
		loading_ready_frames += 1
	else:
		loading_ready_frames = 0
	if loading_ready_frames < 3:
		return
	loading_layer.visible = false
	loading_active = false
	terrain.initial_loading = false
	travel_blocked_s = 0.0
	_clear_motion()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_message("Ready: nearby coverage/collision active; distant terrain still streaming" if terrain.nearby_first and terrain.root_coverage < terrain.roots.size() else "Ready: map coverage and local collision are active")
	if "--human-playtest" in OS.get_cmdline_user_args():
		DisplayServer.window_set_title("TerraForest — Human playtest (temporary world)")
		print("HUMAN_PLAYTEST_READY ", JSON.stringify({"presentation":Presentation.measurement(get_window()),"vsync":DisplayServer.window_get_vsync_mode(),"fps_cap":Engine.max_fps,"temporary":temporary_world,"snapshot_terrain":terrain.backend.snapshot_terrain}))

func _consume_stroke() -> void:
	if loading_active or shutdown_requested or terrain.pending_edit or not terrain.world_ready:
		return
	var group: Array[Dictionary] = stroke_buffer.pop_batch()
	if group.is_empty():
		return
	var commands: Array[PackedByteArray] = []
	var members: Array[Dictionary] = []
	var lo: Vector3 = Vector3.INF
	var hi: Vector3 = -Vector3.INF
	for work: Dictionary in group:
		var sample: Dictionary = work["sample"]
		# Revalidate at submission: the player may have moved since capture.
		if bool(sample["cube"]):
			if int(sample["material"]) != 0 and _brush_overlaps_player(Vector3(sample["cell"]) + Vector3.ONE * 0.5, 0.87):
				_reject_placement("Queued cube cancelled: player moved into its placement")
				continue
		elif bool(sample["add"]):
			var a: Vector3 = sample["a"]
			var b: Vector3 = sample["b"]
			var span: Vector3 = b - a
			var t: float = clampf((player.position + Vector3.UP * 0.9 - a).dot(span) / maxf(span.length_squared(), 0.000001), 0.0, 1.0)
			var r: float = float(sample["radius"]) * (1.74 if int(sample["shape"]) == 1 else 1.0)
			if _brush_overlaps_player(a + span * t, r):
				_reject_placement("Queued fill cancelled: player moved into the brush")
				continue
		commands.push_back(work["command"])
		members.push_back({"captured_us": int(work["sample"].get("captured_us", Time.get_ticks_usec()))})
		lo = lo.min(work["lo"])
		hi = hi.max(work["hi"])
	if commands.is_empty():
		return
	if not terrain.edit(commands[0], lo, hi, int(members[0]["captured_us"]), commands, members):
		_message("Brush not submitted: " + terrain.latest_error)

func _reject_placement(reason: String) -> void:
	placement_rejections += 1
	# Do not flood the console at physics frequency during a blocked held brush.
	var now: int = Time.get_ticks_usec()
	if now - placement_message_us >= 1000000 or placement_message_us == 0:
		placement_message_us = now
		_message(reason)

func _close_journal() -> void:
	# Remove the reference FIRST. A final _process callback must not write into
	# a FileAccess object whose C FILE pointer has already been closed.
	var file: FileAccess = journal
	journal = null
	if file != null and file.is_open():
		file.flush()
		file.close()

func _message(text: String) -> void:
	status.text = text
	print("[TerrainRewrite] ", text)

func _terrain_initialized(text: String) -> void:
	_message(text)
	teleport(pending_spawn, spawn_override_y)

func teleport(point: Vector3, fixed_y: float = -1.0) -> void:
	_begin_loading("Preparing destination")
	pending_spawn = point
	spawn_override_y = fixed_y
	spawn_token += 1
	waiting_spawn = true
	player.velocity = Vector3.ZERO
	player.position = Vector3(point.x, maxf(80.0, point.y), point.z)
	terrain.focus = player.position
	terrain.schedule_timer = 0.0
	terrain.request_height(point, spawn_token)
	stroke_valid = false

func _height_ready(point: Vector3, height: float, token: int) -> void:
	if token != spawn_token:
		return
	player.position = Vector3(point.x, spawn_override_y if spawn_override_y >= 0.0 else height + 2.0, point.z)
	waiting_spawn = false
	needs_floor_spawn = spawn_override_y < 0.0

func _edited(_latency: float) -> void:
	# Construction is rejected if it intersects the player. Excavation cannot embed the player.
	# For smooth filling, also reject the entire brush against the capsule before submission.
	pass

func _input(event: InputEvent) -> void:
	if benchmark_enabled or shutdown_requested:
		return
	if loading_active:
		if event is InputEventKey and not event.pressed:
			controls.set_key(event.physical_keycode, false, Time.get_ticks_usec())
		return
	if event is InputEventMouseMotion and event.relative != Vector2.ZERO:
		terrain.note_interaction()
	if event is InputEventKey and not event.echo:
		terrain.note_interaction()
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		# Observe releases before GUI handling. A menu cannot swallow key-up.
		if not event.pressed or (app_focused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
			controls.set_key(code, event.pressed, Time.get_ticks_usec())
			if controls.direction() == Vector3.ZERO:
				player.velocity.x = 0.0
				player.velocity.z = 0.0
				if fly:
					player.velocity = Vector3.ZERO

func _clear_motion() -> void:
	controls.clear(Time.get_ticks_usec())
	player.velocity = Vector3.ZERO
	input_vector = Vector3.ZERO
	stroke_valid = false
	stroke_buffer.cancel_continuous()
	terrain.set_brush_active(false)
	terrain.set_interaction_target(Vector3.INF)
	last_capture_signature.clear()

func _frame_drawn() -> void:
	if stop_draw_pending_us > 0:
		stop_draw_latency_ms = float(Time.get_ticks_usec() - stop_draw_pending_us) / 1000.0
		stop_draw_pending_us = 0

func _unhandled_input(event: InputEvent) -> void:
	if benchmark_enabled or loading_active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0025
		pitch = clampf(pitch - event.relative.y * 0.0025, -1.53, 1.53)
		player.rotation.y = yaw
		camera.rotation.x = pitch
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			radius = minf(64.0, radius * 1.25)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			radius = maxf(1.0, radius / 1.25)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				_clear_motion()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
			KEY_1: tool = 1
			KEY_2: tool = 2
			KEY_3: tool = 3
			KEY_4: tool = 4
			KEY_G:
				fly = not fly
				player.velocity = Vector3.ZERO
			KEY_Q: material_id = 1 + posmod(material_id - 2, 3)
			KEY_E: material_id = 1 + material_id % 3
			KEY_F:
				radius = 4.0 if radius < 4 else (16.0 if radius < 16 else (64.0 if radius < 64 else 1.0))
			KEY_F11:
				Presentation.apply(get_window())
			KEY_F2: next_site()
			KEY_F3: build_proof()
			KEY_F4: next_biome()
			KEY_F5: terrain.save_world()
			KEY_F9: terrain.reload_world(false)
			KEY_F6:
				frame_debug = not frame_debug
				terrain_material.set_shader_parameter("show_lod", frame_debug)
			KEY_F7:
				if event.ctrl_pressed:
					use_cached_sun = not use_cached_sun
					terrain_material.set_shader_parameter("cached_sun_enabled", use_cached_sun)
				else:
					sun.shadow_enabled = not sun.shadow_enabled
				_message("Engine shadows %s | cached cavity sun %s" % [str(sun.shadow_enabled), str(use_cached_sun)])
			KEY_F8: flashlight.visible = not flashlight.visible
			KEY_F10:
				visual_debug = (visual_debug + 1) % 7
				terrain_material.set_shader_parameter("debug_view", visual_debug)
				_message(["Normal lighting", "Base biomes", "Snow coverage", "Unlit albedo", "Cached sky visibility", "Cached sun visibility", "Surface normals"][visual_debug])
			KEY_R:
				if event.ctrl_pressed:
					if Time.get_ticks_msec() < reset_deadline:
						terrain.reload_world(true)
					else:
						reset_deadline = Time.get_ticks_msec() + 3000
						_message("Press Ctrl+R again within three seconds to erase this world state")

func next_site() -> void:
	site = (site + 1) % 5
	var sites: Array[Vector3] = [Vector3(960, 0, 1310), Vector3(1050, 0, 1218), Vector3(985, 42, 985), Vector3(1484, 0, 1433), Vector3(2300, 1600, 2500)]
	var text: Array[String] = ["Mountain approach", "Cave entrance", "Underground chamber", "Construction yard (F3 builds)", "Whole-world overview"]
	fly = site == 4
	flashlight.visible = site == 2
	pitch = -0.65 if site == 4 else -0.08
	yaw = 0.7144 if site == 4 else 0.0
	player.rotation.y = yaw
	camera.rotation.x = pitch
	camera.far = 6000.0 if site == 4 else 3300.0
	camera.near = 1.0 if site == 4 else 0.08
	teleport(sites[site], sites[site].y if site == 2 or site == 4 else -1.0)
	_message(text[site])

func next_biome() -> void:
	biome_site = (biome_site + 1) % 4
	var sites: Array[Vector3] = [Vector3(800, 0, 1350), Vector3(440, 0, 460), Vector3(1500, 0, 1500), Vector3(1580, 0, 480)]
	teleport(sites[biome_site])
	_message(["Grassland", "Rock/gravel", "Sand/desert", "Snow/alpine"][biome_site])

func build_proof() -> void:
	if terrain.edit(Codec.command(8), Vector3(1467, 0, 1435), Vector3(1502, 256, 1470)):
		_message("Building the exact-cube proof shell; old collision remains until mesh publication")

func _player_water_depth() -> float:
	return 0.0

func _physics_process(delta: float) -> void:
	var physics_begin: int = Time.get_ticks_usec()
	Input.flush_buffered_events()
	if shutdown_requested:
		return
	terrain.focus = player.position
	terrain.require_collision = not fly
	terrain.travel_velocity = Vector3.ZERO
	if benchmark_enabled:
		return
	if waiting_spawn or not terrain.world_ready or loading_active:
		return
	if needs_floor_spawn and terrain.player_region_ready(player.position):
		var top := Vector3(player.position.x, 290, player.position.z)
		var bottom := Vector3(player.position.x, 1, player.position.z)
		var spawn_query := PhysicsRayQueryParameters3D.create(top, bottom, 1)
		var floor_hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(spawn_query)
		if not floor_hit.is_empty():
			player.position.y = floor_hit["position"].y + 0.08
			needs_floor_spawn = false
	var input: Vector3 = controls.direction() if app_focused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Vector3.ZERO
	input_vector = input
	var speed: float = 9.9 if controls.sprint() else 5.5
	var direction: Vector3 = player.basis * input
	if not fly: terrain.travel_velocity=direction*speed
	var before_motion: Vector3 = player.position
	structure_motion_blocked = false
	if fly:
		direction = camera.global_basis * input
		var vertical: float=controls.vertical() if app_focused and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED else 0.0
		player.velocity = Vector3.ZERO
		player.position += movement.flight_displacement(direction,vertical,delta,controls.sprint())
	else:
		var ahead: Vector3 = player.position + direction * maxf(2.0, speed * delta)
		if not terrain.player_region_ready(player.position) or not terrain.player_region_ready(ahead):
			player.velocity = Vector3.ZERO
			if direction != Vector3.ZERO:
				travel_blocked_s += delta
				if travel_blocked_s >= 0.15:
					_begin_loading("Preparing terrain collision ahead")
			direction = Vector3.ZERO
		else:
			travel_blocked_s = 0.0
			var water_depth: float=_player_water_depth()
			if water_depth>0.0:
				var vertical: float=controls.vertical() if app_focused and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED else 0.0
				player.velocity=movement.swimming_velocity(direction,player.velocity,vertical,water_depth,delta,controls.sprint())
			else:
				player.velocity=movement.walking_velocity(direction,player.velocity,delta,controls.sprint(),player.is_on_floor(),controls.held.has(KEY_SPACE))
			structure_motion_blocked = not _additional_motion_ready(delta)
			if structure_motion_blocked:
				player.velocity = Vector3.ZERO
			else:
				if water_depth>0.0: player.move_and_slide()
				else: movement.move_grounded(player,delta)
	var displacement: Vector3 = player.position - before_motion
	planar_speed = Vector2(displacement.x, displacement.z).length() / maxf(delta, 0.000001)
	if input != Vector3.ZERO and planar_speed > 0.01 and controls.last_press_us > 0:
		motion_latency_ms = float(Time.get_ticks_usec() - controls.last_press_us) / 1000.0
		controls.last_press_us = 0
	if controls.release_pending and input == Vector3.ZERO and planar_speed < 0.01:
		stop_latency_ms = float(Time.get_ticks_usec() - controls.last_release_us) / 1000.0
		stop_draw_pending_us = controls.last_release_us
		controls.release_pending = false
	player.position.x = clampf(player.position.x, -1500.0 if fly else 2.0, 3500.0 if fly else 1998.0)
	player.position.z = clampf(player.position.z, -1500.0 if fly else 2.0, 3500.0 if fly else 1998.0)
	player.position.y = clampf(player.position.y, 1.1, 3000.0 if fly else 600.0)
	_update_edit(delta)
	physics_cpu_ms = float(Time.get_ticks_usec() - physics_begin) / 1000.0

func _update_edit(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	var captured: bool = app_focused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if input_vector != Vector3.ZERO or (captured and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))):
		terrain.note_interaction()
	var mining: bool = captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var building: bool = captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	terrain.set_brush_active(mining or building)
	var continuous: bool = held_previous
	held_previous = mining or building
	if not mining and not building:
		stroke_valid = false
		stroke_buffer.cancel_continuous()
		last_capture_signature.clear()
	_consume_stroke()
	pointer.visible = false
	latest_hit.clear()
	if not captured:
		terrain.set_interaction_target(Vector3.INF)
		return
	var start: Vector3 = camera.global_position
	var end: Vector3 = start - camera.global_basis.z * 120.0
	var query := PhysicsRayQueryParameters3D.create(start, end, 1)
	query.hit_back_faces = false
	latest_hit = get_world_3d().direct_space_state.intersect_ray(query)
	# Terrain targeting must not wait for a streamed physics collider. Existing
	# physics hits still win, so loaded structures/objects retain their ordering.
	if latest_hit.is_empty() and terrain.backend.region_terrain:
		latest_hit=_terrain_pick(start,end)
	if latest_hit.is_empty():
		return
	var hit: Vector3 = latest_hit["position"]
	terrain.set_interaction_target(hit)
	var normal: Vector3 = latest_hit["normal"]
	var add: bool = building and not mining
	if tool == 1:
		var cell: Vector3 = (hit + normal * (0.015 if add else -0.015)).floor()
		pointer.position = cell + Vector3.ONE * 0.5
		pointer.scale = Vector3.ONE
		pointer.visible = true
		if (mining or building) and cooldown <= 0.0:
			if add and _brush_overlaps_player(cell + Vector3.ONE * 0.5, 0.86):
				_reject_placement("Placement intersects the player capsule")
				return
			if stroke_buffer.push_cube(Vector3i(cell), material_id if add else 0):
				cooldown = 0.08
				_consume_stroke()
	else:
		var center: Vector3 = hit + normal * radius * (0.32 if add else -0.55)
		var shape: int = 0 if tool == 3 else 1
		if tool == 2:
			center = center.snapped(Vector3.ONE)
		if (mining or building) and cooldown <= 0.0:
			if add and _brush_overlaps_player(center, radius * (1.74 if shape == 1 else 1.0)):
				_reject_placement("Filling here would embed the player; move away first")
				return
			if _same_pending_surface(center, shape, add):
				duplicate_surface_samples += 1
				return
			var a: Vector3 = center
			if shape == 0 and stroke_valid and last_brush_add == add and last_brush.distance_to(center) < radius * 2.0:
				a = last_brush
			if stroke_buffer.push_sweep(a, center, radius, shape, add, material_id, continuous):
				_record_capture(center, shape, add)
				last_brush = center
				last_brush_add = add
				stroke_valid = true
				cooldown = 0.05
				_consume_stroke()

func _brush_overlaps_player(center: Vector3, r: float) -> bool:
	var nearest := Vector3(player.position.x, clampf(center.y, player.position.y + 0.34, player.position.y + 1.46), player.position.z)
	return center.distance_to(nearest) < r + 0.4

func _process(delta: float) -> void:
	if shutdown_requested:
		return
	_update_loading()
	if terrain.nearby_first:
		camera.far = 3300.0 if terrain.root_coverage == terrain.roots.size() else 320.0
	_consume_stroke()
	# Engine delta is a simulation time step, NOT a wall-clock latency measurement.
	var now: int = Time.get_ticks_usec()
	if last_frame_us != 0:
		wall_frame_ms = float(now - last_frame_us) / 1000.0
		frame_samples.push_back(wall_frame_ms)
		worst_wall_ms = maxf(worst_wall_ms, wall_frame_ms)
		if wall_frame_ms > 50.0:
			hitch_count += 1
	last_frame_us = now
	journal_timer += delta
	if journal != null and not journal.is_open():
		journal = null
		if not journal_failure_reported:
			journal_failure_reported = true
			push_warning("Interaction journal closed; recording disabled. World saving is separate.")
	if journal != null and journal.is_open() and journal_timer >= 0.10:
		journal_timer = 0.0
		journal.store_line("%d,%.3f,%.3f,%.2f,%.2f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%d,%d" % [now, wall_frame_ms, physics_cpu_ms, input_vector.x, input_vector.z, planar_speed, stop_latency_ms, stop_draw_latency_ms, terrain.last_queue_ms, terrain.last_edit_ms, terrain.last_total_build_ms, terrain.last_publish_ms, terrain.last_publish_frame_ms, terrain.last_latency_ms, terrain.last_draw_latency_ms, terrain.backend.queued(), terrain.staging.size(), hitch_count] + ",%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%d,%s" % [terrain.last_prepare_latency_ms, terrain.last_mesh_upload_ms, terrain.last_collision_piece_ms, terrain.last_retire_ms, terrain.last_receive_ms, terrain.last_schedule_ms, terrain.last_commit_ms, terrain.last_density_tiles, terrain.last_relight_tiles, terrain.backend.status()])
		if journal.get_error() != OK:
			push_warning("Interaction journal write failed; recording disabled, world unchanged.")
			_close_journal()
	if frame_samples.size() > 300:
		frame_samples.pop_front()
	hud_timer -= delta
	if hud_timer > 0.0:
		return
	hud_timer = 0.25
	var viewport_rid: RID = get_viewport().get_viewport_rid()
	var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid) if gpu_timing_enabled else -1.0
	var cpu: float = RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) if gpu_timing_enabled else -1.0
	var size: Vector2 = get_viewport().get_visible_rect().size
	var samples: Array[float] = frame_samples.duplicate()
	samples.sort()
	var p95: float = samples[mini(samples.size() - 1, int(samples.size() * 0.95))] if not samples.is_empty() else 0.0
	var render_method: String = RenderingServer.get_current_rendering_method()
	hud.text = "Terrain Rewrite 0.4.6-r4 | 2000 x 2000 x 256 | cached raster surfaces, not field rays\n"
	hud.text += "%dx%d native viewport | %d FPS | wall frame p95 %.2f ms | viewport GPU %s / render CPU %s | %s\n" % [int(size.x), int(size.y), Engine.get_frames_per_second(), p95, ("%.2f ms" % gpu) if gpu > 0 else "n/a", ("%.2f ms" % cpu) if cpu > 0 else "n/a", render_method]
	hud.text += "LOD patches 16 / 32 / 64 / 128 / 256: %s | active %d triangles | cache %.1f MiB\n" % [terrain.lod_counts(), terrain.total_triangles, float(terrain.cache_bytes) / 1048576.0]
	hud.text += "SDF pages %d / 16384 | exact cubes %d | state-changing edits %d | queued %d | editing %s\n" % [terrain.sdf_pages, terrain.blocks, terrain.total_edits, terrain.backend.queued(), str(terrain.pending_edit)]
	hud.text += "Last completed: worker edit %.3f ms | patch build %.3f ms | main publish %.3f ms | edit-to-publish %.1f ms\n" % [terrain.last_edit_ms, terrain.last_mesh_ms, terrain.last_publish_ms, terrain.last_latency_ms]
	hud.text += "Physical step %.2f ms | key-up -> stop %.2f ms / draw callback %.2f ms | wall max %.1f ms | >50ms frames %d\n" % [physics_cpu_ms, stop_latency_ms, stop_draw_latency_ms, worst_wall_ms, hitch_count]
	hud.text += "Edit queue %.1f / all builds %.1f / publish frame %.1f ms | draw callback %.1f ms | input (%.0f,%.0f) speed %.2f | torch %s\n" % [terrain.last_queue_ms, terrain.last_total_build_ms, terrain.last_publish_frame_ms, terrain.last_draw_latency_ms, input_vector.x, input_vector.z, planar_speed, "ON" if flashlight.visible else "OFF"]
	hud.text += "Rebuild %d geometry / %d light-only | staging wait %.1f ms | upload %.2f / collision %.2f / retire %.2f ms\n" % [terrain.last_density_tiles, terrain.last_relight_tiles, terrain.last_prepare_latency_ms, terrain.last_mesh_upload_ms, terrain.last_collision_piece_ms, terrain.last_retire_ms]
	hud.text += "Slowest measured main stage: %s %.1f ms (not a GPU measurement)\n" % [terrain.slowest_stage, terrain.slowest_stage_ms]
	if terrain.pending_edit:
		hud.text += "LIVE edit pending %.1f ms | worker %s (previous completed timing above)\n" % [float(Time.get_ticks_usec() - terrain.edit_started_us) / 1000.0, terrain.backend.status()]
	hud.text += "Brush capture %d/%d | coalesced %d | backpressure %d | distant lighting pending %d\n" % [stroke_buffer.samples.size(), StrokeBuffer.LIMIT, stroke_buffer.coalesced, stroke_buffer.backpressure, terrain.lighting_dirty.size()]
	hud.text += "Derived disk cache %s | duplicate pending-surface samples avoided %d\n" % [str(terrain.derived_metrics), duplicate_surface_samples]
	hud.text += "Surface: %s | captured wait %.1f ms | light uploads %d (%.2f ms) | unresolved rays %d\n" % ["Fitted (experimental)" if fitted_surface else "Character", terrain.last_capture_wait_ms, terrain.lighting_attribute_updates, terrain.last_light_upload_ms, terrain.unresolved_light_rays]
	hud.text += "V-Sync requested %s | cap %d | collision pieces reused %d / built %d | match/build %.3f ms\n" % ["ON" if DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_ENABLED else "NOT ENABLED", Engine.max_fps, terrain.collision_pieces_reused, terrain.collision_pieces_built, terrain.last_collision_match_ms]
	if terrain.nearby_first and terrain.root_coverage < terrain.roots.size():
		hud.text += "Nearby-first streaming: %d/%d outer regions | TEMPORARY 320 m view distance\n" % [terrain.root_coverage, terrain.roots.size()]
	hud.text += "Tool %d | radius %.1f m | %s | %s | player %.1f, %.1f, %.1f | %s" % [tool, radius, ["Stone", "Wood", "Metal"][material_id - 1], "FLY" if fly else "WALK 5.5 m/s", player.position.x, player.position.y, player.position.z, "collision ready" if terrain.player_region_ready(player.position) else "waiting for fine collision"]

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		app_focused = false
		_clear_motion()
		# Do not render 60 copies of an unfocused game window every second.
		# No resolution change or stale motion queue. Restore the requested cap on focus.
		Engine.max_fps = background_fps
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		Presentation.restore_vsync()
		app_focused = true
		Engine.max_fps = max_fps
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not shutdown_requested:
		shutdown_requested = true
		_close_journal()
		stroke_buffer.clear()
		terrain.shutdown()
		get_tree().quit()

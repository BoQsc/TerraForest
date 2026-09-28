extends Node3D
## Editor/demo glue only. Storage, geometry, scheduling and static batching are C++.
var buildings: Node3D
var camera := Camera3D.new()
var label := Label.new()
var selected_shape := 1
var selected_material := 0
var rotation_step := 0
var notice := "Baking independent building chunks…"
var elapsed := 0.0
var props: Array[Node3D] = []

func _ready() -> void:
	if not ClassDB.class_exists("NativeBlockWorld"):
		if GDExtensionManager.load_extension("res://addons/structures/structures.gdextension") != OK:
			push_error("Cannot load the native structures addon")
			get_tree().quit(2)
			return
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	DisplayServer.window_set_title("TerraForest | Block structures")
	buildings = ClassDB.instantiate("NativeBlockWorld")
	buildings.name = "IndependentStructures"
	add_child(buildings)
	buildings.create_showcase()
	buildings.configure_history(16*1024*1024,128)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-47, -28, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("5282ac")
	sky_material.sky_horizon_color = Color("d3e0e7")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.5
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var backdrop := MeshInstance3D.new()
	var ground := PlaneMesh.new()
	ground.size = Vector2(2000,2000)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("69746f")
	ground.material = ground_material
	backdrop.mesh = ground
	backdrop.position.y = -1.05
	add_child(backdrop)
	add_child(camera)
	camera.position = Vector3(58, 31, -53)
	camera.look_at(Vector3(12, 14, 6))
	camera.far = 1000
	camera.current = true
	buildings.set_focus(camera.position)
	_create_static_models()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(26, 24)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.04, 0.055, 0.9)
	style.border_color = Color("b8d788")
	style.border_width_left = 3
	style.content_margin_left = 20
	style.content_margin_right = 24
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	label.add_theme_font_size_override("font_size", 17)
	panel.add_child(label)
	_update_label()
	var help := Label.new()
	help.position = Vector2(26, 983)
	help.text = "RMB hold + mouse · Look     WASD · Fly     Q / E · Down / Up     Shift · Fast\n1–5 · Shape     T · Material     R · Rotate     LMB · Place     Shift+LMB · Remove     Ctrl+Z / Y · Undo / Redo     F5 / F9 · Save / Load     Esc · Quit"
	help.add_theme_font_size_override("font_size", 17)
	canvas.add_child(help)
	if "--capture-structures" in OS.get_cmdline_user_args():
		_capture.call_deferred()

func _create_static_models() -> void:
	# A model can be an imported Mesh resource too. These simple authored models
	# demonstrate the separate placement path without external asset dependencies.
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("24383b")
	metal.metallic = 0.65
	metal.roughness = 0.45
	var beam := BoxMesh.new()
	beam.size = Vector3.ONE
	beam.material = metal
	var transforms := PackedFloat32Array()
	# Fences: hundreds of independently placed pieces, collected in spatial MultiMeshes.
	for z in range(-8, 34):
		for y in [0.75, 1.5]:
			_append_transform(transforms, Vector3(-15, y, z), Vector3(0.12, 0.12, 1.0))
		_append_transform(transforms, Vector3(-15, 0.95, z), Vector3(0.12, 1.9, 0.12))
	for x in range(-15, 17):
		for y in [0.75, 1.5]:
			_append_transform(transforms, Vector3(x, y, 33), Vector3(1, 0.12, 0.12))
		_append_transform(transforms, Vector3(x, 0.95, 33), Vector3(0.12, 1.9, 0.12))
	# Exterior ladder, with separate rung placements sharing the same source mesh.
	for x in [31.0, 32.0]:
		_append_transform(transforms, Vector3(x, 24, 5.7), Vector3(0.10, 48, 0.10))
	for rung in range(120):
		_append_transform(transforms, Vector3(31.5, rung * 0.4 + 0.2, 5.7), Vector3(1.0, 0.075, 0.10))
	var batch: Node3D = ClassDB.instantiate("NativeStaticBatch")
	add_child(batch)
	assert(batch.configure_asset("showcase/metal_beam",beam))
	assert(batch.set_instances(beam, transforms))
	props.append(batch)

func _append_transform(buffer: PackedFloat32Array, origin: Vector3, scale: Vector3) -> void:
	buffer.append_array(PackedFloat32Array([scale.x,0,0,origin.x, 0,scale.y,0,origin.y, 0,0,scale.z,origin.z]))

func _process(delta: float) -> void:
	# This is an authoring camera, not the production player controller.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var direction := Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)), 0, float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
		var vertical := float(Input.is_physical_key_pressed(KEY_E))-float(Input.is_physical_key_pressed(KEY_Q))
		camera.position += (camera.basis * direction + Vector3.UP * vertical) * delta * (45.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 12.0)
	buildings.set_focus(camera.position)
	elapsed += delta
	if elapsed > 0.5:
		elapsed = 0
		if buildings.is_idle() and notice.begins_with("Baking"):
			notice = "Independent block buildings · shared static models"
		_update_label()

func _update_label() -> void:
	var s: Dictionary = buildings.stats()
	var shape_names := ["Cube", "Half slab", "Four-step stairs", "Slope", "Post"]
	var material_names := ["Brick", "Wood", "Concrete", "Metal"]
	label.text = "T E R R A F O R E S T  /  S T R U C T U R E S\n\nBlock construction\n%s\n\n%s cells · %s mesh chunks · %s triangles\n%s physics chunks · %s FPS\n\n%s / %s / %d°" % [notice, s.cells, s.mesh_chunks, s.triangles, s.collision_chunks, Engine.get_frames_per_second(), shape_names[selected_shape-1], material_names[selected_material], rotation_step*90]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		camera.rotation.y -= event.relative.x * 0.0025
		camera.rotation.x = clampf(camera.rotation.x-event.relative.y*0.0025, -1.5, 1.5)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_edit(event.shift_pressed)
	if event is InputEventKey and event.pressed and not event.echo:
		if (event.ctrl_pressed or event.meta_pressed) and event.physical_keycode in [KEY_Z,KEY_Y]:
			var forward: bool = event.physical_keycode==KEY_Y or event.shift_pressed
			var applied: bool = buildings.redo() if forward else buildings.undo()
			notice = ("Construction redone" if forward else "Construction undone") if applied else "No construction history available"
		elif event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_5:
			selected_shape = event.physical_keycode-KEY_1+1
		elif event.physical_keycode == KEY_T:
			selected_material = (selected_material+1)%4
		elif event.physical_keycode == KEY_R:
			rotation_step = (rotation_step+1)%4
		elif event.physical_keycode == KEY_F5:
			var file := FileAccess.open("user://structures-showcase.tfbl", FileAccess.WRITE)
			if file:
				file.store_buffer(buildings.capture_snapshot())
				notice = "Showcase blocks saved"
		elif event.physical_keycode == KEY_F9:
			var data := FileAccess.get_file_as_bytes("user://structures-showcase.tfbl") if FileAccess.file_exists("user://structures-showcase.tfbl") else PackedByteArray()
			notice = "Showcase blocks loaded" if buildings.restore_snapshot(data) else "No valid showcase save"
		elif event.physical_keycode == KEY_ESCAPE:
			get_tree().quit()
		_update_label()

func _edit(remove: bool) -> void:
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin+direction*96, 2))
	if hit.is_empty():
		notice = "Aim at a nearby baked building surface"
		return
	var inside := Vector3i((hit.position-hit.normal*0.001).floor())
	var target := inside
	if not remove:
		# Choose the dominant face axis; partial shapes still occupy a full grid cell.
		var normal: Vector3 = hit.normal
		var axis := normal.abs().max_axis_index()
		target[axis] += 1 if normal[axis] > 0 else -1
	var word := 0 if remove else selected_shape+(rotation_step<<3)+(selected_material<<5)
	if buildings.set_cells(PackedInt32Array([target.x,target.y,target.z,word])):
		notice = "Removed cell" if remove else "Placed %s" % target

func _capture() -> void:
	while not buildings.is_idle():
		await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://reports")
	get_viewport().get_texture().get_image().save_png("res://reports/block_structures.png")
	var frames := PackedFloat64Array()
	var previous := Time.get_ticks_usec()
	for sample in range(240):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frames.append((now-previous)/1000.0)
		previous = now
	frames.sort()
	var timing := {"resolution":str(get_viewport().get_texture().get_size()), "window_size":str(DisplayServer.window_get_size()), "window_mode":DisplayServer.window_get_mode(), "samples":frames.size(), "frame_interval_p50_ms":frames[120], "frame_interval_p95_ms":frames[228], "scope":"static showcase after bake; not a city or multiplayer benchmark"}
	var report := FileAccess.open("res://reports/block_structures_gpu.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(timing,"  "))
	report.close()
	print("STRUCTURES_FRAME_TIMING ",JSON.stringify(timing))
	camera.position = Vector3(15,9,-23)
	camera.look_at(Vector3(-1,6,0))
	buildings.set_focus(camera.position)
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reports/block_house.png")
	print("STRUCTURES_SHOWCASE ", JSON.stringify(buildings.stats()))
	print("STATIC_MODELS ", JSON.stringify(props[0].stats()))
	get_tree().quit()

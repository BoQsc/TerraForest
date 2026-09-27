extends "res://demo/controller.gd"
const Vegetation = preload("res://addons/vegetation/vegetation_world.gd")
const Ecosystem = preload("res://addons/world_ecosystem/world_ecosystem.gd")
const Lakes = preload("res://addons/volumetric_water/lake_world.gd")
const Persistence = preload("res://addons/world_runtime/world_persistence.gd")
const Structures = preload("res://addons/structures/structure_tools.gd")
var structures = Structures.new()
var selected_structure: int = 0
var structure_turn: int = 0
var structure_buttons: Array[Button] = []
var structure_hint := Label.new()
var persistence = Persistence.new()
var vegetation = Vegetation.new()
var ecosystem = Ecosystem.new()
var lakes = Lakes.new()
var telemetry := Label.new()
var _telemetry_time: float = 0.0
var _lake_notice: String = ""
var _lake_notice_until: int = 0

func _ready() -> void:
	if not lakes.prepare() or not persistence.register_component("volumetric_water", lakes.capture_snapshot, lakes.restore_snapshot, lakes.snapshot_validator(), lakes.empty_snapshot()) or persistence.attach(terrain) != OK:
		push_error("World persistence initialization failed")
		get_tree().quit(2)
		return
	terrain.nearby_first = true
	pending_spawn = Vector3(800, 0, 1310)
	terrain.focus = pending_spawn
	super._ready()
	structures.terrain = terrain
	DisplayServer.window_set_title("TerraForest | Living terrain")
	vegetation.name = "Vegetation"
	vegetation.camera = camera
	vegetation.sun_direction = sun.global_basis.z.normalized()
	add_child(vegetation)
	if vegetation.initialize() != OK:
		_message("Vegetation initialization failed; inspect the log")
		return
	ecosystem.name = "Ecosystem"
	ecosystem.terrain = terrain
	ecosystem.vegetation = vegetation
	ecosystem.camera = camera
	add_child(ecosystem)
	lakes.name = "Lakes"
	lakes.terrain = terrain
	add_child(lakes)
	lakes.lake_ready.connect(func(_id: int): _show_lake_notice("Lake ready · temporary world" if temporary_world else "Lake ready · F5 saves world"))
	lakes.lake_failed.connect(func(_id: int, code: int): _show_lake_notice("Lake rejected (%d): open basin or blocked seed" % code))

func _show_lake_notice(text: String) -> void:
	_lake_notice = text
	_lake_notice_until = Time.get_ticks_msec()+6000
	_message(text)

func _message(text: String) -> void:
	super._message(text)
	if text.begins_with("World saved") or text.begins_with("World loaded") or text.begins_with("Temporary") or text.begins_with("ERROR:"):
		_lake_notice = "World saved" if text.begins_with("World saved") else "World loaded"
		if text.begins_with("Temporary"):
			_lake_notice = "Temporary world · changes are not saved"
		if text.begins_with("ERROR:"):
			_lake_notice = "World operation failed · F3 for details"
		_lake_notice_until = Time.get_ticks_msec()+6000

func create_lake(point: Vector3) -> int:
	# Explicit authoring action: carve first, bake after terrain publication.
	# The next compound world snapshot includes this lake definition and terrain.
	if terrain.pending_edit or not terrain.world_ready:
		return 0
	var center: Vector3 = point.floor()
	var id: int = lakes.add_lake(center - Vector3(16,16,16), Vector3i(32,20,32), 1.0, center.y-3.0, center-Vector3(0,6,0))
	if id == 0:
		return 0
	if not terrain.sculpt_sphere(center, 12.0):
		lakes.remove_lake(id)
		return 0
	return id

func create_structure(point: Vector3, selection: int, quarter_turns: int = 0) -> bool:
	if loading_active or selection < 0 or selection >= Structures.PRESETS.size() or not point.is_finite():
		return false
	var preset = Structures.PRESETS[selection]
	var center: Vector3 = point.floor()+Vector3(0,preset.half_extents.y-0.5,0)
	if _brush_overlaps_player(center,preset.half_extents.length()):
		_reject_placement("Construction overlaps the player; aim farther away")
		return false
	return structures.place(preset,center,quarter_turns,material_id)

func _select_structure(selection: int) -> void:
	selected_structure = selection
	for i in range(structure_buttons.size()):
		structure_buttons[i].set_pressed_no_signal(i==selection)
	structure_hint.text = "%s · %d°\nT rotates · P places at the crosshair" % [Structures.PRESETS[selection].title,structure_turn*90]

func _setup_scene() -> void:
	super._setup_scene()
	player.position = Vector3(800, 100, 1310)
	for child in get_children():
		if child is WorldEnvironment:
			var environment: Environment = child.environment
			var sky := Sky.new()
			var sky_material := ProceduralSkyMaterial.new()
			sky_material.sky_top_color = Color("527b9a")
			sky_material.sky_horizon_color = Color("c4d6d8")
			sky_material.ground_bottom_color = Color("303d37")
			sky_material.ground_horizon_color = Color("c4d6d8")
			sky.sky_material = sky_material
			environment.sky = sky
			environment.background_mode = Environment.BG_SKY
			environment.ambient_light_energy = 0.35
			environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			environment.fog_enabled = true
			environment.fog_light_color = Color("a7c4cd")
			environment.fog_density = 0.00055
			environment.fog_sky_affect = 0.2

func _setup_hud() -> void:
	super._setup_hud()
	hud.hide()
	status.hide()
	help.text = "WASD  Move    Shift  Sprint    Space  Jump    G  Fly    Mouse  Look    Esc  Release\nLMB  Dig    RMB  Build    Wheel  Brush size    1–4  Tools    5–9  Shapes    P  Place    L  Lake    F5  Save    F9  Reload    F3  Diagnostics"
	help.add_theme_font_size_override("font_size", 15)
	help.add_theme_color_override("font_color", Color("e6eee9"))
	var panel := PanelContainer.new()
	panel.position = Vector2(26, 24)
	panel.custom_minimum_size = Vector2(340, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.07, 0.065, 0.88)
	style.border_color = Color("70bca0")
	style.border_width_left = 3
	style.content_margin_left = 19
	style.content_margin_right = 22
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)
	var eyebrow := Label.new()
	eyebrow.text = "T E R R A F O R E S T"
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", Color("83d6b2"))
	box.add_child(eyebrow)
	var title := Label.new()
	title.text = "Living terrain"
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	telemetry.add_theme_font_size_override("font_size", 14)
	telemetry.add_theme_color_override("font_color", Color("bbcfc6"))
	box.add_child(telemetry)
	help.get_parent().add_child(panel)
	var construction := PanelContainer.new()
	help.get_parent().add_child(construction)
	construction.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	construction.offset_left = -580
	construction.offset_right = -26
	construction.offset_top = 24
	construction.add_theme_stylebox_override("panel",style.duplicate())
	var construction_box := VBoxContainer.new()
	construction.add_child(construction_box)
	var heading := Label.new()
	heading.text = "CONSTRUCTION"
	heading.add_theme_color_override("font_color",Color("83d6b2"))
	construction_box.add_child(heading)
	var row := HBoxContainer.new()
	construction_box.add_child(row)
	for i in range(Structures.PRESETS.size()):
		var button := Button.new()
		button.text = "%d  %s" % [i+5,Structures.PRESETS[i].title]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_select_structure.bind(i))
		row.add_child(button)
		structure_buttons.append(button)
	construction_box.add_child(structure_hint)
	_select_structure(selected_structure)
	hud.position = Vector2(26, 200)
	status.position = Vector2(26, 570)

func _unhandled_input(event: InputEvent) -> void:
	if loading_active or benchmark_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_5 and event.physical_keycode <= KEY_9:
			_select_structure(event.physical_keycode-KEY_5)
			return
		if event.physical_keycode == KEY_T:
			structure_turn = (structure_turn+1)%4
			_select_structure(selected_structure)
			return
		if event.physical_keycode == KEY_P:
			var query := PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*80.0,1)
			var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty():
				_show_lake_notice("Aim at nearby terrain to place construction")
			else:
				_show_lake_notice("Placing %s" % Structures.PRESETS[selected_structure].title if create_structure(hit["position"],selected_structure,structure_turn) else "Construction unavailable here")
			return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_L:
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position-camera.global_basis.z*80.0, 1)
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			_show_lake_notice("Carving lake; waiting for terrain" if create_lake(hit["position"]) != 0 else "Lake creation unavailable")
		else:
			_show_lake_notice("Aim at nearby terrain to carve a lake")
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		hud.visible = not hud.visible
		status.visible = hud.visible
		return
	super._unhandled_input(event)

func _process(delta: float) -> void:
	super._process(delta)
	_telemetry_time += delta
	if _telemetry_time >= 0.5 and vegetation.ready_to_render:
		_telemetry_time = 0.0
		var activity: String = "Updating terrain…" if terrain.pending_edit else "Explore · Sculpt · Build"
		if Time.get_ticks_msec() < _lake_notice_until:
			activity = _lake_notice
		telemetry.text = "%d FPS  ·  %s trees  ·  %d cells\n%s" % [Engine.get_frames_per_second(), str(vegetation.renderer.roots.size()), ecosystem.resident.size(), activity]

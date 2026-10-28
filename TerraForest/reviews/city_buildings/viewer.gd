extends Node3D

const Recipe = preload("res://reviews/city_buildings/recipes.gd")
const MODES := ["Exterior", "Rear", "Ground-floor cutaway", "Inside"]
var structures: Node3D
var asset: Resource
var camera: Camera3D
var hinges: RefCounted
var ready_ok := false
var placement_results: Array[Dictionary] = []
var empty := PackedByteArray()
var original := PackedByteArray()
var selected := 0
var current_mode := 0
var cutaway_floor := 0
var title: Label
var caption: Label
var sign: Label3D
var orbit_target := Vector3.ZERO

func _ready() -> void:
	DisplayServer.window_set_title("TerraForest | City architecture proposals | not added to generation")
	structures = preload("res://addons/structures/structures_world.gd").new()
	add_child(structures)
	if not structures.prepare(): return
	preload("res://addons/structures/furniture_catalog.gd").register(structures)
	preload("res://addons/structures/storage_catalog.gd").register(structures)
	preload("res://addons/structures/door_catalog.gd").register(structures)
	preload("res://addons/structures/window_catalog.gd").register(structures)
	empty = structures.capture_storage_snapshot()
	lighting()
	camera = Camera3D.new()
	camera.near = .04
	camera.far = 250
	camera.current = true
	add_child(camera)
	sign = Label3D.new()
	sign.font_size = 64
	sign.pixel_size = .015
	sign.modulate = Color("d7e8e2")
	sign.outline_modulate = Color("142621")
	sign.outline_size = 10
	add_child(sign)
	interface()
	select_building(0)

func select_building(index: int) -> void:
	selected = index
	cutaway_floor = 0
	ready_ok = false
	structures.restore_storage_snapshot(empty)
	asset = load("res://reviews/city_buildings/baked/" + Recipe.IDS[index] + ".tres")
	if asset == null: return
	var transaction: RefCounted = ClassDB.instantiate("NativePrefabPlacement")
	var placed: Dictionary = transaction.place(structures.blocks, asset, Vector3i.ZERO, 0, structures.model_collections(), [])
	placement_results.append(placed)
	if not placed.get("ok", false): return
	var center: Vector3 = asset.get_bounds().get_center()
	structures.blocks.set_focus(center)
	structures.blocks.set_collision_radius(80)
	structures.blocks.flush_bakes()
	structures.set_model_focus(center)
	original = structures.capture_storage_snapshot()
	ready_ok = true
	select_view(0)

func lighting() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("b9cdd8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d8e3ed")
	environment.ambient_light_energy = .65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	var sky := WorldEnvironment.new()
	sky.environment = environment
	add_child(sky)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44, -30, 0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110
	add_child(sun)
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(180, .2, 180)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.position = Vector3(15, .85, 15)
	body.add_child(collider)
	add_child(body)
	var plane := PlaneMesh.new()
	plane.size = Vector2(180, 180)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("737d72")
	material.roughness = 1
	plane.material = material
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	mesh.position = Vector3(15, .95, 15)
	add_child(mesh)

func interface() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 22)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.035, .055, .065, .93)
	for edge in ["left", "right", "top", "bottom"]: style.set("content_margin_" + edge, 12)
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 23)
	title.modulate = Color("8ce8c1")
	column.add_child(title)
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 16)
	column.add_child(caption)
	var buildings := HBoxContainer.new()
	column.add_child(buildings)
	for index in Recipe.IDS.size():
		var button := Button.new()
		button.text = Recipe.TITLES[index].split(" / ")[0]
		button.tooltip_text = Recipe.TITLES[index]
		button.pressed.connect(select_building.bind(index))
		buildings.add_child(button)
	var views := HBoxContainer.new()
	column.add_child(views)
	for index in MODES.size():
		var button := Button.new()
		button.text = MODES[index]
		button.pressed.connect(select_view.bind(index))
		views.add_child(button)
	var doors := Button.new()
	var floor_button := Button.new()
	floor_button.text = "Next floor"
	floor_button.pressed.connect(next_floor)
	views.add_child(floor_button)
	doors.text = "Doors"
	doors.pressed.connect(toggle_doors)
	views.add_child(doors)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(get_tree().quit)
	views.add_child(close)
	var help := Label.new()
	help.text = "PROPOSALS / approval pending · existing houses unchanged\nRight-drag orbit · wheel zoom · arrows select building · no saves loaded"
	help.add_theme_font_size_override("font_size", 14)
	help.modulate = Color("bdcbc5")
	column.add_child(help)

func select_view(index: int) -> void:
	if not ready_ok: return
	current_mode = index
	structures.restore_storage_snapshot(original)
	hinges = ClassDB.instantiate("NativeHingedDoors")
	var bounds: AABB = asset.get_bounds()
	var center: Vector3 = bounds.get_center()
	var extent: float = maxf(bounds.size.x, bounds.size.z)
	if index == 2:
		var removed := PackedInt32Array()
		var records: PackedInt32Array = asset.get_records()
		for offset in range(0, records.size(), 4):
			if records[offset + 1] >= 4 + cutaway_floor * 4:
				removed.append_array(PackedInt32Array([records[offset], records[offset + 1], records[offset + 2], 0]))
		structures.blocks.set_cells(removed)
		for collection: Node3D in structures.model_collections().values():
			var hidden := PackedInt64Array()
			for identity in collection.get_ids():
				var pose: PackedFloat32Array = collection.get_instance(identity)
				if pose[7] >= 4 + cutaway_floor * 4: hidden.append(identity)
			collection.remove_instances(hidden)
	structures.blocks.flush_bakes()
	camera.fov = 49 if index != 3 else 80
	orbit_target = Vector3(center.x, bounds.size.y * .36, center.z)
	match index:
		0: camera.position = orbit_target + Vector3(extent * 1.08, extent * .62, extent * 1.36)
		1: camera.position = orbit_target + Vector3(-extent * 1.08, extent * .62, -extent * 1.36)
		2:
			orbit_target.y = 1.5 + cutaway_floor * 4
			camera.position = orbit_target + Vector3(extent * .52, extent * 1.32, extent * .85)
		3:
			var locations := [Vector3(12.5, 2.7, 24), Vector3(10, 2.7, 16.5), Vector3(12, 2.7, 19), Vector3(12, 2.7, 20), Vector3(12.5, 2.7, 22), Vector3(11.5, 2.7, 16.5)]
			camera.position = locations[selected] + Vector3.UP * cutaway_floor * 4
			orbit_target = camera.position + Vector3(-.4, -.2, -8)
	camera.look_at(orbit_target)
	sign.text = Recipe.TITLES[selected].to_upper() + "\nPROPOSAL R1"
	sign.position = Vector3(center.x, 3, bounds.end.z + 3)
	sign.visible = index in [0, 1]
	title.text = "TERRAFOREST / " + Recipe.TITLES[selected]
	var view_name: String = ("Floor %d cutaway" % (cutaway_floor + 1)) if index == 2 else MODES[index]
	caption.text = Recipe.DESCRIPTIONS[selected] + "\n" + view_name + " · %d individual blocks · %d attached objects" % [asset.get_cell_count(), asset.get_model_attachments().size()]

func next_floor() -> void:
	cutaway_floor = (cutaway_floor + 1) % Recipe.FLOORS[selected]
	select_view(2)

func toggle_doors() -> void:
	if not ready_ok: return
	var collection: Node3D = structures.model(preload("res://addons/structures/door_catalog.gd").KEY)
	for identity in collection.get_ids(): hinges.toggle(collection, identity, AABB())

func _unhandled_input(event: InputEvent) -> void:
	if not ready_ok: return
	if event is InputEventKey and event.pressed:
		match event.physical_keycode:
			KEY_ESCAPE: get_tree().quit()
			KEY_RIGHT: select_building((selected + 1) % Recipe.IDS.size())
			KEY_LEFT: select_building(posmod(selected - 1, Recipe.IDS.size()))
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		var offset := (camera.position - orbit_target).rotated(Vector3.UP, -event.relative.x * .006)
		var proposed := offset.rotated(camera.global_basis.x, -event.relative.y * .004)
		if absf(proposed.normalized().y) < .95: offset = proposed
		camera.position = orbit_target + offset
		camera.look_at(orbit_target)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var offset := camera.position - orbit_target
		camera.position = orbit_target + offset.normalized() * clampf(offset.length() * (.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), .6, 140)

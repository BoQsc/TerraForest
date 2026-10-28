extends Node3D

const Recipe = preload("res://reviews/modular_buildings/large_house_recipe.gd")
const VIEWS := [
	["Exterior", Vector3(27, 17, 32), Vector3(3, 6, 1)],
	["Rear", Vector3(-24, 16, -29), Vector3(2, 6, 0)],
	["Balcony", Vector3(-13, 10, 19), Vector3(-.5, 5.5, 8)],
	["Ground floor", Vector3(.7, 2.8, 5.7), Vector3(2.8, 2.6, -2)],
	["Upper floor", Vector3(.8, 6.8, 5.7), Vector3(.5, 6.7, -3)],
	["Basement", Vector3(3.9, -1.2, 5.6), Vector3(.5, -1.2, -3)],
	["Cutaway", Vector3(20, 14, 25), Vector3(0, 3, 0)],
	["Bedroom", Vector3(-1.65, 6.65, -1.2), Vector3(-3, 5.8, -4.5)]
]

var structures: Node3D
var asset: Resource
var camera: Camera3D
var hinges: RefCounted
var ready_ok := false
var placement_results: Array[Dictionary] = []
var original := PackedByteArray()
var grounds: Array[MeshInstance3D] = []
var current_view := 0
var caption: Label
var orbit_target := Vector3(3, 6, 1)

func _ready() -> void:
	DisplayServer.window_set_title("TerraForest | House C1 approved addition | existing houses unchanged")
	structures = preload("res://addons/structures/structures_world.gd").new()
	add_child(structures)
	if not structures.prepare():
		return
	preload("res://addons/structures/furniture_catalog.gd").register(structures)
	preload("res://addons/structures/storage_catalog.gd").register(structures)
	preload("res://addons/structures/door_catalog.gd").register(structures)
	preload("res://addons/structures/window_catalog.gd").register(structures)
	asset = load(Recipe.PATH)
	if asset == null:
		return
	var transaction: RefCounted = ClassDB.instantiate("NativePrefabPlacement")
	var placed: Dictionary = transaction.place(structures.blocks, asset, Vector3i.ZERO, 0, structures.model_collections(), [])
	placement_results.append(placed)
	if not placed.get("ok", false):
		return
	structures.blocks.set_focus(Vector3(3, 3, 0))
	structures.blocks.set_collision_radius(64)
	structures.blocks.flush_bakes()
	structures.set_model_focus(Vector3(3, 3, 0))
	original = structures.capture_storage_snapshot()
	hinges = ClassDB.instantiate("NativeHingedDoors")
	lighting()
	camera = Camera3D.new()
	camera.near = .04
	camera.far = 200
	camera.current = true
	add_child(camera)
	interface()
	select_view(0)
	ready_ok = true

func lighting() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("bdcfd8")
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
	sun.directional_shadow_max_distance = 80
	add_child(sun)
	ground(Vector3(-30, .98, 0), Vector2(50, 100))
	ground(Vector3(31, .98, 0), Vector2(50, 100))
	ground(Vector3(.5, .98, -28.5), Vector2(11, 43))
	ground(Vector3(.5, .98, 29), Vector2(11, 42))
	ground(Vector3(3, -3.2, 0), Vector2(100, 100), false)

func ground(position_value: Vector3, size: Vector2, surface: bool = true) -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("777e70") if surface else Color("666e70")
	material.roughness = 1
	plane.material = material
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	mesh.position = position_value
	add_child(mesh)
	if surface:
		grounds.append(mesh)

func interface() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 22)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.035, .055, .065, .92)
	for edge in ["left", "right", "top", "bottom"]:
		style.set("content_margin_" + edge, 14)
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "TERRAFOREST / HOUSE C1 / APPROVED ADDITION"
	heading.add_theme_font_size_override("font_size", 23)
	heading.modulate = Color("8ce8c1")
	column.add_child(heading)
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 17)
	column.add_child(caption)
	var toolbar := HBoxContainer.new()
	column.add_child(toolbar)
	for index in VIEWS.size():
		var button := Button.new()
		button.text = VIEWS[index][0]
		button.pressed.connect(select_view.bind(index))
		toolbar.add_child(button)
	var doors := Button.new()
	doors.text = "Doors"
	doors.pressed.connect(toggle_doors)
	toolbar.add_child(doors)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(get_tree().quit)
	toolbar.add_child(close)
	var help := Label.new()
	help.text = "Separate destructible blocks · smooth roof · open garage bay · right-drag orbit / wheel zoom\nApproved C1 design. This isolated viewer does not modify player saves."
	help.add_theme_font_size_override("font_size", 15)
	help.modulate = Color("c2cfd4")
	column.add_child(help)

func select_view(index: int) -> void:
	current_view = index
	structures.restore_storage_snapshot(original)
	hinges = ClassDB.instantiate("NativeHingedDoors")
	for mesh in grounds:
		mesh.visible = index != 6
	if index == 6:
		var removed := PackedInt32Array()
		var records: PackedInt32Array = asset.get_records()
		for offset in range(0, records.size(), 4):
			var cell := Vector3i(records[offset], records[offset + 1], records[offset + 2])
			if cell.y >= 9 or cell.z >= 7 or cell.x >= 5 or (cell.y in [0, 4] and cell.z > 0):
				removed.append_array(PackedInt32Array([cell.x, cell.y, cell.z, 0]))
		structures.blocks.set_cells(removed)
		for collection: Node3D in structures.model_collections().values():
			var hidden := PackedInt64Array()
			for identity in collection.get_ids():
				var pose: PackedFloat32Array = collection.get_instance(identity)
				var position_value := Vector3(pose[3], pose[7], pose[11])
				if position_value.z >= 7 or position_value.x >= 5 or (position_value.y >= 1 and position_value.z > 0):
					hidden.append(identity)
			collection.remove_instances(hidden)
	structures.blocks.flush_bakes()
	camera.fov = 78 if index in [3, 4, 5, 7] else 49
	camera.position = VIEWS[index][1]
	orbit_target = VIEWS[index][2]
	camera.look_at(orbit_target)
	caption.text = "%s  |  2 storeys + cellar / 7 m balcony / 5 m clear vehicle opening" % VIEWS[index][0]

func toggle_doors() -> void:
	var collection: Node3D = structures.model(preload("res://addons/structures/door_catalog.gd").KEY)
	for identity in collection.get_ids():
		hinges.toggle(collection, identity, AABB())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		get_tree().quit()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		var offset := camera.position - orbit_target
		offset = offset.rotated(Vector3.UP, -event.relative.x * .006)
		var pitch: float = -event.relative.y * .004
		var proposed := offset.rotated(camera.global_basis.x, pitch)
		if absf(proposed.normalized().y) < .95:
			offset = proposed
		camera.position = orbit_target + offset
		camera.look_at(orbit_target)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var offset := camera.position - orbit_target
		var distance := clampf(offset.length() * (.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), .5, 90)
		camera.position = orbit_target + offset.normalized() * distance

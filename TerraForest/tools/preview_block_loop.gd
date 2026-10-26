# SPDX-License-Identifier: 0BSD
extends SceneTree
## Offline shape experiment. All track/support geometry is native, unscaled cells.

const OUTPUT := "res://docs/evidence/block_loop_trial"
var blocks: Node3D
var stage: Node3D
var camera: Camera3D
var cells: Dictionary = {}
var strip_cache: Dictionary = {}
var failures: Array[String] = []
var heading: Label
var caption: Label
var results: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func require(accepted: bool, message: String) -> void:
	if not accepted:
		failures.append(message)
		push_error(message)

func put_cell(cell: Vector3i, shape: int, orientation: int, material: int) -> void:
	var word: int = blocks.encode_block(shape, orientation, material)
	require(word > 0, "Existing shape/orientation must encode")
	if cells.has(cell) and cells[cell] != word:
		var previous: Dictionary = blocks.decode_block(cells[cell])
		# The flat approach contains the little triangular seam at the bottom join.
		if shape == 9 and previous.shape == 16:
			cells[cell] = word
			return
		if shape == 16 and previous.shape == 9:
			return
		require(false, "Conflicting cells at %s: %s versus %s" % [cell, previous, blocks.decode_block(word)])
		return
	cells[cell] = word

func track_material(z: int, phase: int) -> int:
	return (0 if posmod(phase, 2) == 0 else 2) if z == 0 or z == 7 else 3

func strip_recipe(direction: Vector2i, outward: Vector2i) -> Dictionary:
	var key := "%s/%s" % [direction, outward]
	if strip_cache.has(key):
		return strip_cache[key]
	var shape := 15 if direction.x != 0 and direction.y != 0 else 9
	var target := Vector3(direction.x, direction.y, 0)
	var normal := Vector3(outward.x, outward.y, 0).normalized()
	for orientation in 24:
		var mesh: Mesh = blocks.preview_mesh(shape, orientation)
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for cell_x in range(-2, 2):
			for cell_y in range(-2, 2):
				var offset := Vector3(cell_x, cell_y, 0)
				var fits := true
				var first_found := false
				var last_found := false
				for vertex in vertices:
					var point := vertex + offset
					var distance := point.dot(normal)
					if distance < -0.00001 or distance > 0.126:
						fits = false
						break
					if point.distance_to(Vector3.ZERO) < 0.00001:
						first_found = true
					if point.distance_to(target) < 0.00001:
						last_found = true
				if fits and first_found and last_found:
					var recipe := {"shape": shape, "rotation": orientation, "offset": Vector3i(cell_x, cell_y, 0)}
					strip_cache[key] = recipe
					return recipe
	require(false, "No existing strip for %s" % key)
	return {}

func strip(first: Vector2i, last: Vector2i, outward: Vector2i) -> void:
	var delta := last - first
	var length := maxi(absi(delta.x), absi(delta.y))
	var direction := Vector2i(signi(delta.x), signi(delta.y))
	var recipe := strip_recipe(direction, outward)
	if recipe.is_empty():
		return
	for step in length:
		var point := first + direction * step
		for z in 8:
			var origin := Vector3i(point.x, point.y, z) + Vector3i(recipe.offset)
			var material := track_material(z, point.x if direction.x != 0 else point.y)
			put_cell(origin, recipe.shape, recipe.rotation, material)
			if recipe.shape == 15:
				var seam_offset := Vector3i(blocks.shape_orientation(recipe.rotation) * Vector3(0, -1, 0))
				put_cell(origin + seam_offset, 16, recipe.rotation, material)

func make_octagon() -> void:
	var points: Array[Vector2i] = [Vector2i(-5, 4), Vector2i(5, 4), Vector2i(10, 9), Vector2i(10, 19), Vector2i(5, 24), Vector2i(-5, 24), Vector2i(-10, 19), Vector2i(-10, 9)]
	var normals: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
	for side in 8:
		strip(points[side], points[(side + 1) % 8], normals[side])
	strip(Vector2i(-20, 4), Vector2i(-5, 4), Vector2i(0, -1))
	strip(Vector2i(5, 4), Vector2i(20, 4), Vector2i(0, -1))
	make_supports(4)

func make_rounded_rectangle() -> void:
	strip(Vector2i(-10, 3), Vector2i(10, 3), Vector2i(0, 1))
	strip(Vector2i(-10, 25), Vector2i(10, 25), Vector2i(0, -1))
	strip(Vector2i(-11, 4), Vector2i(-11, 24), Vector2i(1, 0))
	strip(Vector2i(11, 4), Vector2i(11, 24), Vector2i(-1, 0))
	for corner in [[Vector3i(-11, 3, 0), 10], [Vector3i(10, 3, 0), 8], [Vector3i(-11, 24, 0), 2], [Vector3i(10, 24, 0), 0]]:
		for z in 8:
			put_cell(Vector3i(corner[0]) + Vector3i(0, 0, z), 11, corner[1], track_material(z, 0))
	# Approach remains a straight deck; its upper surface is the ring's bottom.
	for x in range(-20, 20):
		for z in 8:
			var cell := Vector3i(x, 3, z)
			if not cells.has(cell):
				put_cell(cell, 9, 0, track_material(z, x))
	make_supports(3)

func make_supports(deck_height: int) -> void:
	for x in [-18, -12, -6, 0, 6, 12, 18]:
		for z in [0, 7]:
			for y in 3:
				put_cell(Vector3i(x, y, z), 7, 0, 3)
			if deck_height == 4:
				# A cube at the column head meets the upper-mounted deck at y=4.
				# One native cell owns that joint, rather than overlapping a post.
				var head := Vector3i(x, 3, z)
				var old: Dictionary = blocks.decode_block(cells[head])
				require(old.shape == 9, "Column head replaces a deck panel")
				cells[head] = blocks.encode_block(1, 0, old.material)
			for foot_x in range(x - 1, x + 2):
				put_cell(Vector3i(foot_x, -1, z), 8, 0, 2)
	for x in [-13, 12]:
		for z in [-1, 8]:
			for y in range(0, 24):
				put_cell(Vector3i(x, y, z), 1, 0, 3)
		for y in [9, 18, 23]:
			for z in 8:
				put_cell(Vector3i(x, y, z), 9, 8, 3)
		# Existing thin slope and seam cells make braces in the two side towers.
		for base_y in [0, 9]:
			for step in 8:
				var main_cell := Vector3i(x, base_y + step + 1, step)
				# The deck provides a solid junction where the lower brace crosses it.
				if not cells.has(main_cell):
					put_cell(main_cell, 15, 1, 3)
				var seam_cell := Vector3i(x, base_y + step, step)
				if not cells.has(seam_cell):
					put_cell(seam_cell, 16, 1, 3)

func publish(name: String) -> void:
	var records := PackedInt32Array()
	var counts: Dictionary = {}
	for cell: Vector3i in cells:
		var word: int = cells[cell]
		records.append_array(PackedInt32Array([cell.x, cell.y, cell.z, word]))
		var shape: int = blocks.decode_block(word).shape
		counts[str(shape)] = counts.get(str(shape), 0) + 1
	require(blocks.set_cells(records), "Native placement accepts all %s cells" % name)
	blocks.set_collision_radius(128)
	blocks.set_focus(Vector3(0, 12, 4))
	blocks.flush_bakes()
	var snapshot: PackedByteArray = blocks.capture_snapshot()
	require(not snapshot.is_empty() and blocks.validate_snapshot(snapshot), "Snapshot validates")
	require(blocks.restore_snapshot(snapshot) and blocks.capture_snapshot() == snapshot, "Snapshot restores exact native cell identities")
	blocks.flush_bakes()
	var file := FileAccess.open(OUTPUT.path_join(name + ".tfbl"), FileAccess.WRITE)
	file.store_buffer(snapshot)
	results.append({"name": name, "cells": cells.size(), "shape_counts": counts, "stats": blocks.stats(), "native_snapshot_roundtrip": true, "identity_transform": blocks.transform == Transform3D.IDENTITY})

func lighting() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("567f9c")
	sky_material.sky_horizon_color = Color("d2dbdd")
	sky_material.ground_horizon_color = Color("cbd4d5")
	sky_material.ground_bottom_color = Color("647577")
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = 1.0
	environment.ssao_intensity = 1.2
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -32, 0)
	sun.light_energy = 2.0
	sun.light_color = Color("fff1df")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110
	stage.add_child(sun)
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.position.y = -0.02
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("38473c")
	material.roughness = 1.0
	ground.material_override = material
	stage.add_child(ground)

func add_car(deck_top: float) -> void:
	var car: RigidBody3D = load("res://vehicle_demo/scenes/car.tscn").instantiate()
	car.freeze = true
	car.position = Vector3(-14, deck_top + 0.66, 4)
	car.rotation.y = PI / 2.0
	stage.add_child(car)
	car.process_mode = Node.PROCESS_MODE_DISABLED

func interface() -> void:
	var hud := CanvasLayer.new()
	root.add_child(hud)
	var top := ColorRect.new()
	top.color = Color(0.035, 0.06, 0.08, 0.9)
	top.position = Vector2(28, 25)
	top.size = Vector2(900, 104)
	hud.add_child(top)
	heading = Label.new()
	heading.position = Vector2(49, 37)
	heading.add_theme_font_size_override("font_size", 32)
	hud.add_child(heading)
	caption = Label.new()
	caption.position = Vector2(50, 84)
	caption.add_theme_font_size_override("font_size", 21)
	caption.add_theme_color_override("font_color", Color("c0d0d5"))
	hud.add_child(caption)
	var note := Label.new()
	note.text = "ACTUAL GODOT RENDER  /  EXISTING NATIVE SHAPES  /  1 m CELLS\nStatic geometry study; driving through the loop has not been tested."
	note.position = Vector2(39, 997)
	note.add_theme_font_size_override("font_size", 20)
	note.add_theme_constant_override("outline_size", 7)
	note.add_theme_color_override("font_outline_color", Color("172127"))
	hud.add_child(note)

func capture(name: String, eye: Vector3, aim: Vector3) -> void:
	camera.position = eye
	camera.look_at(aim)
	for frame in 18:
		await process_frame
	await RenderingServer.frame_post_draw
	require(root.get_texture().get_image().save_png(OUTPUT.path_join(name + ".png")) == OK, "Capture " + name)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_title("TerraForest | Existing block loop experiment")
	interface()
	for variant in 2:
		cells.clear()
		stage = Node3D.new()
		root.add_child(stage)
		blocks = ClassDB.instantiate("NativeBlockWorld")
		stage.add_child(blocks)
		blocks.set_process(false)
		lighting()
		camera = Camera3D.new()
		camera.fov = 46
		camera.far = 5000
		stage.add_child(camera)
		camera.current = true
		if variant == 0:
			make_octagon()
			publish("octagonal_loop")
			add_car(4.0)
			heading.text = "LOOP / EXISTING BLOCKS"
			caption.text = "20 m opening  /  8 m track  /  flat panels + 45-degree slopes"
			await capture("octagonal_loop", Vector3(29, 23, 40), Vector3(0, 12, 3))
			await capture("octagonal_loop_front", Vector3(7, 15, 58), Vector3(0, 13, 3))
		else:
			make_rounded_rectangle()
			publish("rounded_rectangle_loop")
			add_car(3.125)
			heading.text = "LOOP / EXISTING QUARTER ARCHES"
			caption.text = "Straight panels + 1 m radius corners  /  8 m track"
			await capture("rounded_rectangle_loop", Vector3(29, 23, 40), Vector3(0, 12, 3))
		stage.free()
		await process_frame
	var manifest := {"variants": results, "failures": failures, "engine": Engine.get_version_info(), "scope": "Static native block assembly and image capture. All track and supports use existing shape IDs, integer cell positions, grid rotations and identity world scale. Existing game materials. Ground plane and the existing vehicle are presentation/scale references. No vehicle traversal or new shape implementation."}
	FileAccess.open(OUTPUT.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "  ") + "\n")
	print("BLOCK_LOOP_PREVIEW variants=", results.size(), " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

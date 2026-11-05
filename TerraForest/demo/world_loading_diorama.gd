# SPDX-License-Identifier: 0BSD
extends Control
## Standalone world-loading mockup: a seeded planet diorama beside an editorial
## loading rail. Presentation only - sample data, mock progress, no gameplay hook.
## Run res://demo/world_loading_diorama.tscn on its own to preview it.

const SAMPLE_SEED := 8841229
const GLOBE_CENTER := Vector2(520, 552)
const RING_RADIUS := 336.0
const SEA_LEVEL := 0.07
const RAIL_LEFT := 1030.0
const RAIL_WIDTH := 806.0
const STEP_TOP := 512.0
const STEP_HEIGHT := 52.0
const MOCK_SECONDS := 16.0

const INK := Color("#f3f5ec")
const MUTED := Color("#9db0a8")
const DIM := Color("#677a73")
const MINT := Color("#7ed9b4")
const RULE := Color(1, 1, 1, 0.10)

const STEPS := [
	{"title": "World recipe", "detail": "8841229 · temperate basin", "work": "RECIPE LOCKED", "at": 0.03},
	{"title": "Carving terrain", "detail": "heightfield · 4 096 chunks", "work": "4 096 / 4 096 CHUNKS", "at": 0.26},
	{"title": "Painting biomes", "detail": "grassland · old growth · wetland", "work": "18 / 18 BIOMES", "at": 0.44},
	{"title": "Planting forest", "detail": "24 861 trees placed", "work": "24 861 / 32 000 TREES", "at": 0.68},
	{"title": "Raising landmarks", "detail": "settlements, roads, camps", "work": "3 / 7 SITES PLACED", "at": 0.86},
	{"title": "Streaming your camp", "detail": "spawn check and first frame", "work": "1 / 3 STREAMS READY", "at": 1.0},
]

var display_font: SystemFont
var body_font: SystemFont
var mono_font: SystemFont
var noise_land: FastNoiseLite
var noise_warp: FastNoiseLite
var noise_detail: FastNoiseLite
var planet_pivot: Node3D
var planet: Node3D
var stars: StarField
var ring: ProgressRing
var bar: SegmentBar
var percent_label: Label
var clock_label: Label
var stage_label: Label
var work_label: Label
var rows: Array[Dictionary] = []
var progress := 0.0
var clock := 0.0
var frozen := false


class StarField extends Control:
	var points: Array[Vector3] = []
	var clock := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 4711
		for i in 240:
			points.append(Vector3(rng.randf(), pow(rng.randf(), 1.35), rng.randf()))

	func _process(delta: float) -> void:
		clock += delta
		queue_redraw()

	func _draw() -> void:
		for point in points:
			if point.x > 0.5:
				continue
			var position := Vector2(point.x * size.x, point.y * size.y * 0.94)
			var twinkle := 0.55 + 0.45 * sin(clock * (0.5 + point.z * 0.9) + point.z * 21.0)
			var alpha := (0.08 + 0.30 * point.z) * twinkle
			alpha *= lerpf(1.0, 0.35, smoothstep(0.40, 0.5, point.x))
			draw_circle(position, 0.7 + 1.1 * point.z, Color(0.83, 0.94, 0.89, alpha))


class ProgressRing extends Control:
	var value := 0.0:
		set(new_value):
			if value != new_value:
				value = new_value
				queue_redraw()
	var radius := 372.0
	var pulse := 0.0:
		set(new_value):
			pulse = new_value
			queue_redraw()
	var accent := Color("#7ed9b4")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var center := size * 0.5
		draw_arc(center, radius, 0.0, TAU, 220, Color(1, 1, 1, 0.1), 1.0, true)
		draw_arc(center, radius - 18.0, 0.0, TAU, 200, Color(1, 1, 1, 0.05), 1.0, true)
		for i in 60:
			var angle := TAU * float(i) / 60.0 - PI * 0.5
			var major := i % 5 == 0
			var length := 9.0 if major else 4.0
			var reached := float(i) / 60.0 <= value
			var color := Color(1, 1, 1, 0.22 if major else 0.09)
			if reached:
				color = Color(accent.r, accent.g, accent.b, 0.85 if major else 0.45)
			var direction := Vector2(cos(angle), sin(angle))
			draw_line(center + direction * (radius + 12.0), center + direction * (radius + 12.0 + length), color, 1.0, true)
		var segments := 96
		var completion := smoothstep(0.9, 1.0, value)
		for i in segments:
			var t0 := float(i) / segments
			if t0 > value:
				break
			var t1 := minf(float(i + 1) / segments, value)
			var color := accent
			color.a = lerpf(lerpf(0.45, 0.95, pow(t0, 0.6)), 0.7, completion)
			draw_arc(center, radius, -PI * 0.5 + TAU * t0, -PI * 0.5 + TAU * t1, 6, color, 3.4, true)
		if value > 0.001:
			var head := -PI * 0.5 + TAU * value
			var point := center + Vector2(cos(head), sin(head)) * radius
			for i in 4:
				draw_circle(point, 4.0 + i * 4.0, Color(accent.r, accent.g, accent.b, 0.13 - i * 0.028))
			draw_circle(point, 4.0 + sin(pulse * 2.4) * 0.6, accent)
			draw_circle(point, 1.8, Color(1, 1, 1, 0.92))


class SegmentBar extends Control:
	var value := 0.0
	var clock := 0.0
	var accent := Color("#7ed9b4")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		clock += delta
		queue_redraw()

	func _draw() -> void:
		var count := 44
		var gap := 3.0
		var width := (size.x - gap * float(count - 1)) / float(count)
		for i in count:
			var t := float(i) / float(count)
			var rect := Rect2(float(i) * (width + gap), 0.0, width, size.y)
			if t <= value:
				if float(i + 1) / float(count) <= value:
					var color := accent.lerp(Color("#f2f6ea"), t * 0.55)
					color.a = 0.95
					draw_rect(rect, color)
				else:
					var partial := (value - t) * float(count)
					draw_rect(Rect2(rect.position, Vector2(rect.size.x * partial, rect.size.y)), accent)
			else:
				draw_rect(rect, Color(1, 1, 1, 0.13))
		if value > 0.01 and value < 0.995:
			var head := Vector2(value * size.x, size.y * 0.5)
			draw_circle(head, 7.0 + sin(clock * 3.0), Color(accent.r, accent.g, accent.b, 0.18))


class LeafMark extends Control:
	func _ready() -> void:
		custom_minimum_size = Vector2(26, 26)
		size = Vector2(26, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var center := size * 0.5
		var half := 13.0
		var outline := PackedVector2Array()
		for i in 21:
			var t := float(i) / 20.0
			outline.append(center + Vector2(-sin(PI * t) * half * 0.6, -half + t * half * 2.0))
		for i in range(20, -1, -1):
			var t := float(i) / 20.0
			outline.append(center + Vector2(sin(PI * t) * half * 0.6, -half + t * half * 2.0))
		draw_colored_polygon(outline, Color("#7ed9b4"))
		draw_line(center + Vector2(0, -half * 0.82), center + Vector2(0, half * 0.98), Color(0.03, 0.07, 0.06, 0.6), 1.2, true)


class StepDot extends Control:
	var state := 0:
		set(value):
			if state != value:
				state = value
				queue_redraw()
	var pulse := 0.0
	var accent := Color("#7ed9b4")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		if state == 1:
			queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		if state == 2:
			draw_circle(center, 10.0, Color(1, 1, 1, 0.05))
			draw_polyline(PackedVector2Array([
				center + Vector2(-4.2, 0.2), center + Vector2(-1.3, 3.2), center + Vector2(4.6, -3.4)
			]), Color(accent.r, accent.g, accent.b, 0.85), 1.8, true)
		elif state == 1:
			draw_circle(center, 10.0 + sin(pulse * 2.2) * 1.8, Color(accent.r, accent.g, accent.b, 0.12))
			draw_circle(center, 3.4, accent)
		else:
			draw_arc(center, 4.6, 0.0, TAU, 24, Color(1, 1, 1, 0.22), 1.3, true)


class StepRail extends Control:
	var step_height := 52.0
	var count := 6

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in count - 1:
			var top := float(i) * step_height + 35.0
			draw_line(Vector2(10, top), Vector2(10, top + step_height - 22.0), Color(1, 1, 1, 0.22), 1.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	display_font = system_font(["Bahnschrift SemiCondensed", "Bahnschrift", "Segoe UI"], 600)
	body_font = system_font(["Segoe UI", "Segoe UI Variable Text", "Arial"], 400)
	mono_font = system_font(["Consolas", "Cascadia Mono", "Courier New"], 400)
	build_background()
	build_globe()
	build_ring()
	build_vignette()
	build_rail()
	build_footer()
	apply()


func system_font(names: Array, weight: int) -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(names)
	font.font_weight = weight
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	font.hinting = TextServer.HINTING_LIGHT
	return font


func spaced(text: String) -> String:
	var out := ""
	for i in text.length():
		var character := text[i]
		out += character
		if character != " ":
			out += " "
	return out.strip_edges()


func label(text_value: String, font_size: int, color: Color, font: Font) -> Label:
	var out := Label.new()
	out.text = text_value
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	out.add_theme_font_override("font", font)
	out.add_theme_font_size_override("font_size", font_size)
	out.add_theme_color_override("font_color", color)
	out.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.42))
	out.add_theme_constant_override("shadow_offset_x", 0)
	out.add_theme_constant_override("shadow_offset_y", 2)
	return out


func gradient_texture(offsets: PackedFloat32Array, colors: PackedColorArray, radial: bool) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 512
	texture.height = 512
	if radial:
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
	else:
		texture.fill = GradientTexture2D.FILL_LINEAR
		texture.fill_from = Vector2(0.0, 0.0)
		texture.fill_to = Vector2(0.0, 1.0)
	return texture


func full_rect(texture: Texture2D) -> TextureRect:
	var out := TextureRect.new()
	out.texture = texture
	out.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	out.stretch_mode = TextureRect.STRETCH_SCALE
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	out.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return out


func build_background() -> void:
	add_child(full_rect(gradient_texture(
		PackedFloat32Array([0.0, 0.30, 0.58, 0.82, 1.0]),
		PackedColorArray([Color("#040b0a"), Color("#061310"), Color("#081a15"), Color("#0b211a"), Color("#050f0d")]),
		false
	)))
	var bloom := TextureRect.new()
	bloom.texture = gradient_texture(
		PackedFloat32Array([0.0, 0.42, 1.0]),
		PackedColorArray([Color(0.20, 0.62, 0.50, 0.34), Color(0.10, 0.34, 0.29, 0.12), Color(0.03, 0.10, 0.09, 0.0)]),
		true
	)
	bloom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bloom.stretch_mode = TextureRect.STRETCH_SCALE
	bloom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bloom.position = GLOBE_CENTER - Vector2(750, 750)
	bloom.size = Vector2(1500, 1500)
	add_child(bloom)
	stars = StarField.new()
	stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(stars)


func make_noise(seed_value: int, frequency: float, octaves: int, gain: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = gain
	noise.fractal_lacunarity = 2.05
	return noise


func build_globe() -> void:
	noise_land = make_noise(SAMPLE_SEED, 1.0, 5, 0.52)
	noise_warp = make_noise(SAMPLE_SEED + 7717, 0.72, 2, 0.5)
	noise_detail = make_noise(SAMPLE_SEED + 19283, 2.9, 4, 0.55)
	var container := SubViewportContainer.new()
	container.position = GLOBE_CENTER - Vector2(430, 430)
	container.size = Vector2(860, 860)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(860, 860)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#9ad9c6")
	environment.ambient_light_energy = 0.35
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 2.0
	world.environment = environment
	viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-26, -42, 0)
	sun.light_energy = 1.4
	sun.light_color = Color("#fff0d8")
	viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-6, 132, 0)
	fill.light_energy = 0.35
	fill.light_color = Color("#7fd3c4")
	viewport.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-12, 206, 0)
	rim.light_energy = 0.5
	rim.light_color = Color("#9fe8d0")
	viewport.add_child(rim)
	planet_pivot = Node3D.new()
	planet_pivot.rotation_degrees = Vector3(-7, 0, 15)
	viewport.add_child(planet_pivot)
	planet = Node3D.new()
	planet_pivot.add_child(planet)
	var land := MeshInstance3D.new()
	land.mesh = build_land_mesh()
	land.material_override = land_material()
	land.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.add_child(land)
	var ocean := MeshInstance3D.new()
	ocean.mesh = sphere_mesh(1.0015, 192, 96)
	ocean.material_override = ocean_material()
	planet.add_child(ocean)
	var shell := MeshInstance3D.new()
	shell.mesh = sphere_mesh(1.05, 96, 48)
	shell.material_override = atmosphere_material()
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.add_child(shell)
	scatter_trees()
	var camera := Camera3D.new()
	camera.fov = 32.0
	camera.near = 0.05
	camera.far = 40.0
	camera.look_at_from_position(Vector3(0, 0.22, 6.3), Vector3(0, 0.02, 0), Vector3.UP)
	camera.current = true
	viewport.add_child(camera)


func sphere_mesh(radius: float, radial_segments: int, rings: int) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = radial_segments
	sphere.rings = rings
	return sphere


func elevation(direction: Vector3) -> float:
	var warp := noise_warp.get_noise_3dv(direction * 0.85) * 0.32
	var continent := noise_land.get_noise_3dv(direction * 1.05 + Vector3(warp, warp * 0.7, warp * 0.35))
	var detail := noise_detail.get_noise_3dv(direction * 3.2) * 0.13
	var ridge := maxf(0.0, noise_detail.get_noise_3dv(direction * 1.85))
	return continent * 0.82 + detail + ridge * ridge * 0.5 + 0.02


func shape_elevation(direction: Vector3) -> float:
	var warp := noise_warp.get_noise_3dv(direction * 0.85) * 0.32
	var continent := noise_land.get_noise_3dv(direction * 1.05 + Vector3(warp, warp * 0.7, warp * 0.35))
	var ridge := maxf(0.0, noise_detail.get_noise_3dv(direction * 1.85))
	return continent * 0.82 + ridge * ridge * 0.38 + 0.02


func relief(gauge: float) -> float:
	if gauge <= 0.0:
		return gauge * 0.08
	return 0.055 * (1.0 - exp(-gauge / 0.3))


func land_color(gauge: float, direction: Vector3) -> Color:
	var shade := 0.95 + 0.08 * noise_warp.get_noise_3dv(direction * 5.5)
	var color: Color
	if gauge < 0.05:
		color = Color("#37603a")
	elif gauge < 0.16:
		color = Color("#2b4e30")
	elif gauge < 0.30:
		color = Color("#26452c")
	elif gauge < 0.42:
		color = Color("#33523a")
	else:
		color = Color("#3d5240")
	var canopy := 0.98 + 0.04 * noise_detail.get_noise_3dv(direction * 7.5)
	color = Color(color.r * shade * canopy, color.g * shade * canopy, color.b * shade * canopy)
	var polar := smoothstep(0.92, 1.0, absf(direction.y)) * 0.35
	color = color.lerp(Color("#d7e6e6"), polar)
	var relief_shade := hillshade(direction)
	return Color(color.r * relief_shade, color.g * relief_shade, color.b * relief_shade)


func hillshade(direction: Vector3) -> float:
	const SUN := Vector3(-0.6, 0.55, 0.58)
	var tangent := SUN - direction * SUN.dot(direction)
	if tangent.length_squared() < 0.000001:
		return 1.0
	tangent = tangent.normalized()
	var step := 0.014
	var ahead := elevation((direction + tangent * step).normalized())
	var behind := elevation((direction - tangent * step).normalized())
	return clampf(1.0 + (behind - ahead) * 2.0, 0.92, 1.06)


func build_land_mesh() -> ArrayMesh:
	var source := sphere_mesh(1.0, 240, 120).get_mesh_arrays()
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in vertices:
		var direction := vertex.normalized()
		var height := elevation(direction)
		surface.set_color(land_color(height - SEA_LEVEL, direction))
		surface.add_vertex(direction * (1.0018 + relief(shape_elevation(direction) - SEA_LEVEL)))
	for index in indices:
		surface.add_index(index)
	surface.generate_normals()
	return surface.commit()


func land_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.94
	return material


func ocean_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#1a4d55")
	material.metallic = 0.0
	material.roughness = 0.35
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


func atmosphere_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	material.albedo_color = Color(0.36, 0.80, 0.68, 0.26)
	return material


func tree_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#33553a")
	material.roughness = 0.95
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


func cone_mesh() -> CylinderMesh:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 2.0
	cone.radial_segments = 5
	cone.rings = 1
	return cone


func scatter_trees() -> void:
	const LIMIT := 2200
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = cone_mesh()
	multimesh.instance_count = LIMIT
	var rng := RandomNumberGenerator.new()
	rng.seed = SAMPLE_SEED
	var placed := 0
	var golden := PI * (3.0 - sqrt(5.0))
	for i in 9000:
		var y := 1.0 - 2.0 * (float(i) + 0.5) / 9000.0
		var radius := sqrt(maxf(0.0, 1.0 - y * y))
		var theta := golden * float(i)
		var direction := Vector3(cos(theta) * radius, y, sin(theta) * radius)
		direction = (direction + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.006).normalized()
		var gauge := shape_elevation(direction) - SEA_LEVEL
		if gauge < 0.025 or gauge > 0.3 or absf(direction.y) > 0.74:
			continue
		if noise_detail.get_noise_3dv(direction * 2.6) < -0.04:
			continue
		if placed >= LIMIT:
			break
		var scale := 0.0032 + rng.randf() * 0.003
		var origin := direction * (1.0018 + relief(gauge) + scale * 1.1)
		var basis := Basis(Quaternion(Vector3.UP, direction)).scaled(Vector3.ONE * scale)
		multimesh.set_instance_transform(placed, Transform3D(basis, origin))
		placed += 1
	multimesh.visible_instance_count = placed
	var trees := MultiMeshInstance3D.new()
	trees.multimesh = multimesh
	trees.material_override = tree_material()
	trees.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.add_child(trees)


func build_ring() -> void:
	ring = ProgressRing.new()
	ring.radius = RING_RADIUS
	ring.position = GLOBE_CENTER - Vector2(RING_RADIUS + 40.0, RING_RADIUS + 40.0)
	ring.size = Vector2(RING_RADIUS + 40.0, RING_RADIUS + 40.0) * 2.0
	add_child(ring)


func build_vignette() -> void:
	var vignette := full_rect(gradient_texture(
		PackedFloat32Array([0.0, 0.46, 1.0]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.01, 0.03, 0.03, 0.72)]),
		true
	))
	add_child(vignette)


func build_rail() -> void:
	var lock := HBoxContainer.new()
	lock.position = Vector2(RAIL_LEFT, 74)
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.add_theme_constant_override("separation", 12)
	add_child(lock)
	lock.add_child(LeafMark.new())
	var word := label(spaced("TERRAFOREST"), 14, INK, display_font)
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock.add_child(word)
	var separator_dot := label("·", 14, Color(1, 1, 1, 0.28), body_font)
	separator_dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock.add_child(separator_dot)
	var tag := label(spaced("WORLD LOADER"), 10, DIM, body_font)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock.add_child(tag)

	var kicker := label(spaced("PREPARING NEW WORLD"), 11, MINT, body_font)
	kicker.position = Vector2(RAIL_LEFT, 226)
	add_child(kicker)
	var title := label("ALDERGROVE HOLLOW", 60, INK, display_font)
	title.position = Vector2(RAIL_LEFT - 3, 252)
	add_child(title)
	var meta := label("Temperate forest basin  ·  seed 8 841 229", 15, MUTED, body_font)
	meta.position = Vector2(RAIL_LEFT, 334)
	add_child(meta)

	var facts := [["SEED", "8841229", true], ["BIOME", "Temperate forest", false], ["AREA", "64 km²", false], ["RULESET", "Survival", false]]
	for i in facts.size():
		var x := RAIL_LEFT + float(i) * 202.0
		if i > 0:
			var separator := ColorRect.new()
			separator.color = Color(1, 1, 1, 0.07)
			separator.position = Vector2(x - 26.0, 400)
			separator.size = Vector2(1, 44)
			separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(separator)
		var key := label(spaced(facts[i][0]), 9, Color(0.55, 0.63, 0.59), body_font)
		key.position = Vector2(x, 400)
		add_child(key)
		var value := label(facts[i][1], 15, INK, mono_font if facts[i][2] else body_font)
		value.position = Vector2(x, 420)
		add_child(value)

	var rule := ColorRect.new()
	rule.color = RULE
	rule.position = Vector2(RAIL_LEFT, 484)
	rule.size = Vector2(RAIL_WIDTH, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)

	var step_rail := StepRail.new()
	step_rail.step_height = STEP_HEIGHT
	step_rail.count = STEPS.size()
	step_rail.position = Vector2(RAIL_LEFT, STEP_TOP - 8)
	step_rail.size = Vector2(24, STEP_HEIGHT * float(STEPS.size()) - 2)
	add_child(step_rail)
	for i in STEPS.size():
		var y := STEP_TOP + float(i) * STEP_HEIGHT
		var dot := StepDot.new()
		dot.position = Vector2(RAIL_LEFT - 2, y + 4)
		dot.size = Vector2(24, 24)
		add_child(dot)
		var heading := label(STEPS[i].title, 16, INK, display_font)
		heading.position = Vector2(RAIL_LEFT + 40, y - 1)
		add_child(heading)
		var detail := label(STEPS[i].detail, 12, MUTED, body_font)
		detail.position = Vector2(RAIL_LEFT + 40, y + 21)
		add_child(detail)
		rows.append({"at": STEPS[i].at, "title": heading, "detail": detail, "dot": dot})

	percent_label = label("0%", 52, INK, display_font)
	percent_label.position = Vector2(RAIL_LEFT - 3, 834)
	add_child(percent_label)
	clock_label = label("", 13, MUTED, mono_font)
	clock_label.position = Vector2(RAIL_LEFT, 866)
	clock_label.size = Vector2(RAIL_WIDTH, 22)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(clock_label)

	stage_label = label("", 11, Color(0.70, 0.77, 0.73, 0.9), body_font)
	stage_label.position = Vector2(RAIL_LEFT, 906)
	add_child(stage_label)
	work_label = label("", 10, Color(0.64, 0.71, 0.67, 0.8), mono_font)
	work_label.position = Vector2(RAIL_LEFT, 906)
	work_label.size = Vector2(RAIL_WIDTH, 20)
	work_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(work_label)

	bar = SegmentBar.new()
	bar.position = Vector2(RAIL_LEFT, 934)
	bar.size = Vector2(RAIL_WIDTH, 8)
	add_child(bar)


func build_footer() -> void:
	var caption := label(spaced("TERRAFORMED FROM SEED 8841229"), 10, Color(1, 1, 1, 0.52), body_font)
	caption.position = Vector2(GLOBE_CENTER.x - 300.0, 952)
	caption.size = Vector2(600, 20)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(caption)

	var divider := ColorRect.new()
	divider.color = Color(1, 1, 1, 0.05)
	divider.position = Vector2(970, 96)
	divider.size = Vector2(1, 900)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(divider)

	var note := label("Field note — game trails north of the creek lead to the hollow.", 13, Color(0.87, 0.90, 0.84, 0.72), body_font)
	note.position = Vector2(RAIL_LEFT, 1002)
	add_child(note)

	var key := PanelContainer.new()
	var key_skin := StyleBoxFlat.new()
	key_skin.bg_color = Color(1, 1, 1, 0.06)
	key_skin.border_color = Color(1, 1, 1, 0.16)
	key_skin.set_border_width_all(1)
	key_skin.set_corner_radius_all(3)
	key_skin.set_content_margin_all(3)
	key.add_theme_stylebox_override("panel", key_skin)
	key.custom_minimum_size = Vector2(38, 22)
	key.position = Vector2(1740, 1002)
	add_child(key)
	var key_text := label("ESC", 10, MUTED, mono_font)
	key_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key.add_child(key_text)
	var cancel := label(spaced("CANCEL"), 10, DIM, body_font)
	cancel.position = Vector2(1786, 1006)
	add_child(cancel)

	var marker := label(spaced("MOCKUP · PRESENTATION PREVIEW"), 9, Color(1, 1, 1, 0.32), body_font)
	marker.position = Vector2(0, 44)
	marker.size = Vector2(1864, 18)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(marker)


func _process(delta: float) -> void:
	if not frozen:
		clock += delta
	progress = 1.0 - pow(1.0 - clampf(clock / MOCK_SECONDS, 0.0, 1.0), 1.35)
	if planet != null:
		planet.rotation.y = clock * 0.075
		planet_pivot.position.y = sin(clock * 0.55) * 0.012
	if ring != null:
		ring.pulse = clock
	apply()


func apply() -> void:
	var value := clampf(progress, 0.0, 1.0)
	var finished := value >= 0.999
	ring.value = value
	bar.value = value
	percent_label.text = "%d%%" % int(round(value * 100.0))
	var remaining := maxf(0.0, (1.0 - value) * 24.0)
	if finished:
		clock_label.text = "READY   ·   %s elapsed" % format_clock(clock)
	else:
		clock_label.text = "%d s remaining   ·   %s elapsed" % [int(ceil(remaining)), format_clock(clock)]
	var active := 0
	for i in rows.size():
		if value >= float(rows[i].at):
			active = i + 1
	active = mini(active, rows.size() - 1)
	for i in rows.size():
		var row := rows[i]
		var dot: StepDot = row.dot
		var heading: Label = row.title
		var detail: Label = row.detail
		if finished or value >= float(row.at):
			dot.state = 2
			heading.add_theme_color_override("font_color", Color(0.72, 0.78, 0.74, 0.58))
			detail.add_theme_color_override("font_color", Color(0.64, 0.71, 0.67, 0.6))
		elif i == active:
			dot.state = 1
			heading.add_theme_color_override("font_color", INK)
			detail.add_theme_color_override("font_color", MUTED)
		else:
			dot.state = 0
			heading.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
			detail.add_theme_color_override("font_color", Color(1, 1, 1, 0.26))
		dot.pulse = clock
	if finished:
		active = rows.size() - 1
		stage_label.text = spaced("WORLD READY")
		work_label.text = spaced("ENTER THE FOREST")
	else:
		stage_label.text = spaced(str(STEPS[active].title).to_upper())
		work_label.text = spaced(str(STEPS[active].work))


func format_clock(seconds: float) -> String:
	var whole := int(seconds)
	return "%02d:%02d" % [whole / 60, whole % 60]


func set_mock_time(seconds: float) -> void:
	frozen = true
	clock = seconds
	progress = 1.0 - pow(1.0 - clampf(clock / MOCK_SECONDS, 0.0, 1.0), 1.35)
	if planet != null:
		planet.rotation.y = clock * 0.075
	apply()

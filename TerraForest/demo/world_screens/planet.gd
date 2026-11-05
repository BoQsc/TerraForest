# SPDX-License-Identifier: 0BSD
extends Control
## Seeded planet portrait rendered in its own SubViewport. Shared by the world
## selection, generation and loading mockups.

var seed_value := 8841229
var radius_px := 250.0
var tree_count := 2200
var mesh_detail := 1.0
var spin := 0.0
var accent := Color("#7ed9b4")
var scan := -1.0
var show_scan := false
var show_grid := false

var _viewport: SubViewport
var _planet: Node3D
var _scan_overlay: ScanOverlay
var _noise_land: FastNoiseLite
var _noise_warp: FastNoiseLite
var _noise_detail: FastNoiseLite

const SEA_LEVEL := 0.09
const CAMERA_DISTANCE := 6.3
const FOV := 32.0


class ScanOverlay extends Control:
	var radius := 250.0
	var scan := 0.0
	var accent := Color("#7ed9b4")
	var grid := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var center := size * 0.5
		if grid:
			draw_grid(center)
		var band := center.y - radius + scan * radius * 2.0
		var glow := accent
		for offset in range(-34, 35):
			var y := band + float(offset) * 0.6
			var dy := absf(y - center.y)
			if dy >= radius:
				continue
			var half := sqrt(radius * radius - dy * dy)
			var falloff := 1.0 - absf(float(offset)) / 34.0
			glow.a = 0.24 * falloff * falloff
			draw_line(Vector2(center.x - half, y), Vector2(center.x + half, y), glow, 1.0)
		var core_dy := absf(band - center.y)
		if core_dy < radius:
			var core_half := sqrt(radius * radius - core_dy * core_dy)
			var core := accent
			core.a = 0.85
			draw_line(Vector2(center.x - core_half, band), Vector2(center.x + core_half, band), core, 1.4, true)

	func draw_grid(center: Vector2) -> void:
		var color := accent
		color.a = 0.1
		for i in range(1, 6):
			var k := PI * float(i) / 6.0
			ellipse(center, radius * sin(k), radius, color)
		for phi in [-0.7, -0.35, 0.0, 0.35, 0.7]:
			var rx := radius * cos(phi)
			ellipse(Vector2(center.x, center.y - radius * sin(phi) * 0.9), rx, rx * 0.42, color)

	func ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
		var points := PackedVector2Array()
		for i in 97:
			var t := TAU * float(i) / 96.0
			points.append(center + Vector2(cos(t) * rx, sin(t) * ry))
		draw_polyline(points, color, 1.0, true)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	build()


func viewport_side() -> float:
	return radius_px * 1.82 * 2.0


func build() -> void:
	var side := viewport_side()
	custom_minimum_size = Vector2(side, side)
	size = Vector2(side, side)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size = size
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(int(side), int(side))
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_viewport)
	_scan_overlay = ScanOverlay.new()
	_scan_overlay.radius = radius_px
	_scan_overlay.accent = accent
	_scan_overlay.grid = show_grid
	_scan_overlay.size = size
	_scan_overlay.visible = show_scan
	add_child(_scan_overlay)
	_noise_land = make_noise(seed_value, 1.0, 5, 0.52)
	_noise_warp = make_noise(seed_value + 7717, 0.72, 2, 0.5)
	_noise_detail = make_noise(seed_value + 19283, 2.9, 4, 0.55)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#9ad9c6")
	environment.ambient_light_energy = 0.24
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 2.0
	world.environment = environment
	_viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-26, -42, 0)
	sun.light_energy = 1.45
	sun.light_color = Color("#f6f8ec")
	_viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-6, 132, 0)
	fill.light_energy = 0.3
	fill.light_color = Color("#7fd3c4")
	_viewport.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-12, 206, 0)
	rim.light_energy = 0.55
	rim.light_color = Color("#9fe8d0")
	_viewport.add_child(rim)
	var pivot := Node3D.new()
	pivot.rotation_degrees = Vector3(-7, 0, 15)
	_viewport.add_child(pivot)
	_planet = Node3D.new()
	pivot.add_child(_planet)
	var land := MeshInstance3D.new()
	land.mesh = build_land_mesh()
	land.material_override = land_material()
	land.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_planet.add_child(land)
	var ocean := MeshInstance3D.new()
	ocean.mesh = sphere_mesh(1.0015, 192, 96)
	ocean.material_override = ocean_material()
	_planet.add_child(ocean)
	var shell := MeshInstance3D.new()
	shell.mesh = sphere_mesh(1.05, 96, 48)
	shell.material_override = atmosphere_material()
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_planet.add_child(shell)
	scatter_trees()
	var camera := Camera3D.new()
	camera.fov = FOV
	camera.near = 0.05
	camera.far = 40.0
	camera.look_at_from_position(Vector3(0, 0.22, CAMERA_DISTANCE), Vector3(0, 0.02, 0), Vector3.UP)
	camera.current = true
	_viewport.add_child(camera)
	_planet.rotation.y = spin
	set_scan_progress(scan)


func set_spin(radians: float) -> void:
	spin = radians
	if _planet != null:
		_planet.rotation.y = radians


func set_scan_progress(value: float) -> void:
	scan = value
	if _scan_overlay == null:
		return
	_scan_overlay.visible = show_scan and scan >= 0.0
	_scan_overlay.scan = clampf(scan, 0.0, 1.0)
	_scan_overlay.queue_redraw()


func make_noise(seed_value_: int, frequency: float, octaves: int, gain: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value_
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = gain
	noise.fractal_lacunarity = 2.05
	return noise


func sphere_mesh(radius: float, radial_segments: int, rings: int) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = maxi(16, int(float(radial_segments) * mesh_detail))
	sphere.rings = maxi(8, int(float(rings) * mesh_detail))
	return sphere


func elevation(direction: Vector3) -> float:
	var warp := _noise_warp.get_noise_3dv(direction * 0.85) * 0.32
	var continent := _noise_land.get_noise_3dv(direction * 1.05 + Vector3(warp, warp * 0.7, warp * 0.35))
	var detail := _noise_detail.get_noise_3dv(direction * 3.2) * 0.13
	var ridge := maxf(0.0, _noise_detail.get_noise_3dv(direction * 1.85))
	return continent * 0.82 + detail + ridge * ridge * 0.5 + 0.02


func shape_elevation(direction: Vector3) -> float:
	var warp := _noise_warp.get_noise_3dv(direction * 0.85) * 0.32
	var continent := _noise_land.get_noise_3dv(direction * 1.05 + Vector3(warp, warp * 0.7, warp * 0.35))
	var ridge := maxf(0.0, _noise_detail.get_noise_3dv(direction * 1.85))
	return continent * 0.82 + ridge * ridge * 0.38 + 0.02


func relief(gauge: float) -> float:
	if gauge <= 0.0:
		return gauge * 0.08
	return 0.07 * (1.0 - exp(-gauge / 0.28))


func hillshade(direction: Vector3) -> float:
	const SUN := Vector3(-0.6, 0.55, 0.58)
	var tangent := SUN - direction * SUN.dot(direction)
	if tangent.length_squared() < 0.000001:
		return 1.0
	tangent = tangent.normalized()
	var step := 0.014
	var ahead := elevation((direction + tangent * step).normalized())
	var behind := elevation((direction - tangent * step).normalized())
	return clampf(1.0 + (behind - ahead) * 2.4, 0.88, 1.12)


func land_color(gauge: float, direction: Vector3) -> Color:
	var shade := 0.95 + 0.08 * _noise_warp.get_noise_3dv(direction * 5.5)
	var meadow := Color("#3a6540")
	var forest := Color("#24512d")
	var biome := smoothstep(-0.12, 0.22, _noise_detail.get_noise_3dv(direction * 1.55))
	var color: Color = meadow.lerp(forest, biome)
	if gauge < 0.012:
		color = Color("#8c8261").lerp(color, 0.55)
	elif gauge >= 0.3 and gauge < 0.42:
		color = color.lerp(Color("#47563f"), 0.3)
	elif gauge >= 0.42:
		color = color.lerp(Color("#5c6154"), 0.35)
	var canopy := 0.97 + 0.05 * _noise_detail.get_noise_3dv(direction * 7.5)
	color = Color(color.r * shade * canopy, color.g * shade * canopy, color.b * shade * canopy)
	var polar := smoothstep(0.9, 1.0, absf(direction.y)) * 0.45
	color = color.lerp(Color("#d3e2e4"), polar)
	var relief_shade := hillshade(direction)
	return Color(color.r * relief_shade, color.g * relief_shade, color.b * relief_shade)


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
		var facing := smoothstep(0.02, 0.5, absf(direction.z))
		surface.add_vertex(direction * (1.0018 + relief(shape_elevation(direction) - SEA_LEVEL) * facing))
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
	material.albedo_color = Color(0.36, 0.80, 0.68, 0.14)
	return material


func tree_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#3a6142")
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
	var limit := maxi(0, tree_count)
	if limit == 0 or _planet == null:
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = cone_mesh()
	multimesh.instance_count = limit
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var placed := 0
	var golden := PI * (3.0 - sqrt(5.0))
	var attempts := limit * 3
	for i in attempts:
		var y := 1.0 - 2.0 * (float(i) + 0.5) / float(attempts)
		var ring := sqrt(maxf(0.0, 1.0 - y * y))
		var theta := golden * float(i)
		var direction := Vector3(cos(theta) * ring, y, sin(theta) * ring)
		direction = (direction + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.006).normalized()
		var gauge := shape_elevation(direction) - SEA_LEVEL
		if gauge < 0.025 or gauge > 0.3 or absf(direction.y) > 0.74:
			continue
		if _noise_detail.get_noise_3dv(direction * 2.6) < -0.04:
			continue
		if placed >= limit:
			break
		var scale := 0.0034 + rng.randf() * 0.0034
		var origin := direction * (1.0018 + relief(gauge) + scale * 1.1)
		var basis := Basis(Quaternion(Vector3.UP, direction)).scaled(Vector3.ONE * scale)
		multimesh.set_instance_transform(placed, Transform3D(basis, origin))
		placed += 1
	multimesh.visible_instance_count = placed
	var trees := MultiMeshInstance3D.new()
	trees.multimesh = multimesh
	trees.material_override = tree_material()
	trees.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_planet.add_child(trees)

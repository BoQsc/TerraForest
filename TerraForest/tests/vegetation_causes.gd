# SPDX-License-Identifier: 0BSD
extends "res://tests/vegetation_stability.gd"
# Diagnostic-only in-memory mesh/material/settings overrides; production source
# and player saves stay untouched. World overrides are restored before shutdown.
var direction := Vector3(0, -0.14, -1).normalized()
var image_bytes := 0
var crop := Rect2i(640, 400, 640, 240)
var diagnostic_report: Dictionary = {}
var probe_kinds := ["near", "low", "eight", "three"]
var world_only := false

func pose(frame: int) -> void:
	camera.global_position = base_eye + Vector3(frame * 0.02, 0, 0)
	camera.look_at(camera.global_position + direction)
	for material in materials:
		material.set_shader_parameter("cover_eye", camera.global_position)
		material.set_shader_parameter("comparison_time", 0.0)
		material.set_shader_parameter("wind_strength", 0.0)

func picture(image: Image, name: String, full := false) -> void:
	var data := image.save_jpg_to_buffer(0.90) if full else image.save_png_to_buffer()
	image_bytes += data.size()
	if not check(image_bytes <= 8 * 1024 * 1024, "bounded diagnostic image allocation"):
		quit(1); return
	FileAccess.open(output.path_join(name + (".jpg" if full else ".png")), FileAccess.WRITE).store_buffer(data)

func fixed_mesh(kind: String) -> ArrayMesh:
	var asset := Asset.new()
	if kind == "near": asset.grass(false)
	elif kind == "low": asset.grass(true)
	elif kind == "eight": asset.grass_far()
	else: asset.grass_horizon()
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = asset.vertices
	arrays[Mesh.ARRAY_NORMAL] = asset.normals
	arrays[Mesh.ARRAY_TEX_UV] = asset.uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func silhouette_probe() -> void:
	world = Node3D.new(); root.add_child(world)
	camera = Camera3D.new(); world.add_child(camera); camera.current = true; camera.fov = 75
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color.BLACK
	world.add_child(env)
	var material := ShaderMaterial.new(); var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled; void fragment(){ALBEDO=vec3(1.0);}"
	material.shader = shader
	var multimesh := MultiMesh.new(); multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = 64
	var units_per_pixel := 90.0 * 2.0 * tan(deg_to_rad(75.0) * 0.5) / 1080.0
	var centers: Array[Vector2i] = []
	for row in 8:
		for column in 8:
			var point := Vector3((column - 3.5) * 16.0 * units_per_pixel, (row - 3.5) * 16.0 * units_per_pixel, -90)
			multimesh.set_instance_transform(row * 8 + column, Transform3D(Basis(Vector3.UP, (row * 8 + column) * 2.399963), point))
			centers.append(Vector2i(960 + (column - 3.5) * 16, 540 - (row - 3.5) * 16))
	var view := MultiMeshInstance3D.new(); view.multimesh = multimesh; view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; world.add_child(view)
	var original_msaa := root.msaa_3d
	var measurements: Array = []
	for kind: String in probe_kinds:
		multimesh.mesh = fixed_mesh(kind)
		for aa in [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_8X]:
			root.msaa_3d = aa
			var areas: Array = []
			for plant in 64: areas.append([])
			camera.position = Vector3.ZERO; await settle(8)
			var stationary := root.get_texture().get_image().get_region(Rect2i(880, 460, 160, 160)).get_data()
			await settle(3)
			check(stationary == root.get_texture().get_image().get_region(Rect2i(880, 460, 160, 160)).get_data(), "stationary silhouette is identical " + kind + "/" + str(aa))
			for phase in 16:
				# Exactly one pixel's 4x4 sample phases, not a changing LOD or light.
				camera.position = Vector3((phase % 4) * 0.25, (phase / 4) * 0.25, 0) * units_per_pixel
				await settle(2)
				var frame := root.get_texture().get_image()
				for plant in 64:
					var area := 0.0
					for y in range(centers[plant].y - 8, centers[plant].y + 8):
						for x in range(centers[plant].x - 8, centers[plant].x + 8):
							area += frame.get_pixel(x, y).srgb_to_linear().r
					areas[plant].append(area)
				if phase == 0 or phase == 15:
					picture(frame.get_region(Rect2i(880, 460, 160, 160)), "mask_%s_%d_%d" % [kind, aa, phase])
			var fluctuations: Array[float] = []; var means: Array[float] = []
			for plant: Array in areas:
				var mean := 0.0
				for area: float in plant: mean += area / 16.0
				means.append(mean)
				fluctuations.append((plant.max() - plant.min()) / maxf(mean, 0.0001))
			fluctuations.sort(); means.sort()
			measurements.append({"mesh": kind, "triangles": multimesh.mesh.get_faces().size() / 3, "msaa_enum": aa, "median_projected_area_px": means[32], "median_relative_area_range": fluctuations[32], "p95_relative_area_range": fluctuations[60], "areas": areas})
	diagnostic_report["silhouette"] = {"distance_m": 90, "plants": 64, "phases": 16, "scope": "Fixed meshes, white unlit masks, black background. No wind, textures, shadows, dither, terrain, streaming or LOD switching. Linearized pixel sum per isolated plant measures projected-area instability under subpixel translation; MSAA8 is a diagnostic control, not a runtime recommendation.", "measurements": measurements}
	root.msaa_3d = original_msaa; world.free(); await process_frame

func grass_tag_mesh(mesh: ArrayMesh) -> Dictionary:
	var arrays := mesh.surface_get_arrays(0); var original := arrays.duplicate(true)
	var probe := Asset.new(); probe.grass(false); var near_end: int = probe.vertices.size()
	probe.grass(true); var low_end: int = probe.vertices.size()
	probe.grass_far(); var far_end: int = probe.vertices.size()
	probe.grass_horizon(); var end: int = probe.vertices.size()
	check(end == arrays[Mesh.ARRAY_VERTEX].size(), "tagged LOD ranges match actual production mesh")
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in end: colors[i] = Color.CYAN if i < near_end else (Color.YELLOW if i < low_end else (Color.BLUE if i < far_end else Color.RED))
	arrays[Mesh.ARRAY_COLOR] = colors
	var lods := {}
	for pair in [[0.02, near_end, low_end], [0.12, low_end, far_end], [0.2, far_end, end]]:
		var indices := PackedInt32Array()
		for i in range(pair[1], pair[2]): indices.append(i)
		lods[pair[0]] = indices
	var material := mesh.surface_get_material(0)
	mesh.clear_surfaces(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods); mesh.surface_set_material(0, material)
	return {"arrays": original, "lods": lods, "material": material}

func tag_index(color: Color) -> int:
	if color.b > 0.95 and color.r < 0.02 and color.g < 0.02: return 2
	if color.r > 0.95 and color.g < 0.02 and color.b < 0.02: return 3
	if color.b > 0.95 and color.g > 0.95 and color.r < 0.02: return 0
	if color.r > 0.95 and color.g > 0.95 and color.b < 0.02: return 1
	return -1

func census(image: Image) -> Dictionary:
	var counts := [0, 0, 0, 0]; var tiles := {}
	for y in range(280, 900):
		for x in range(40, 1880):
			var tag := tag_index(image.get_pixel(x, y))
			if tag < 0: continue
			counts[tag] += 1
			var tile := Vector2i(x / 320, y / 120)
			tiles[tile] = int(tiles.get(tile, 0)) + 1
	var best := Vector2i.ZERO; var amount := 0
	for tile: Vector2i in tiles:
		if tiles[tile] > amount: best = tile; amount = tiles[tile]
	return {"counts": counts, "visible_pixels": counts[0] + counts[1] + counts[2] + counts[3], "best_tile": best, "tile_pixels": amount}

func compare(_label: String) -> void:
	# Called only by the inherited read-only world loader; runtime source is untouched.
	var cover: Node = game.ground_cover
	var mesh: ArrayMesh = cover.preview_meshes[2]
	var grass_material: ShaderMaterial = mesh.surface_get_material(0)
	var saved := grass_tag_mesh(mesh)
	var env_node: WorldEnvironment
	for child in game.get_children():
		if child is WorldEnvironment: env_node = child; break
	check(env_node != null, "world environment available")
	var original_environment := env_node.environment
	var original_aa := root.msaa_3d
	var mask_environment: Environment = original_environment.duplicate()
	mask_environment.fog_enabled = false; mask_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env_node.environment = mask_environment; root.msaa_3d = Viewport.MSAA_DISABLED
	var tag_shader := Shader.new()
	tag_shader.code = "shader_type spatial; render_mode unshaded,cull_disabled; uniform vec3 cover_eye; varying float d; void vertex(){d=distance(MODEL_MATRIX[3].xyz,cover_eye);} void fragment(){if(d<60.0 || d>124.0)discard; ALBEDO=COLOR.rgb;}"
	grass_material.shader = tag_shader
	base_eye.y += 14.0
	var views: Array = []; var best_count := -1; var best_direction := direction; var best_census := {}
	for yaw in [0.0, PI * 0.5, PI, PI * 1.5]:
		direction = Vector3(sin(yaw), -0.14, -cos(yaw)).normalized(); pose(0); await settle(6)
		var scan := census(root.get_texture().get_image()); scan["yaw"] = yaw; views.append(scan)
		if scan.visible_pixels > best_count: best_count = scan.visible_pixels; best_direction = direction; best_census = scan
	direction = best_direction; pose(0); await settle(4)
	check(best_count >= 100, "visible far grass verified by fragment tags, not projected hidden roots")
	crop = Rect2i(clampi(best_census.best_tile.x * 320 - 160, 0, 1280), clampi(best_census.best_tile.y * 120 - 60, 220, 660), 640, 240)
	picture(root.get_texture().get_image().get_region(crop), "world_lod_tags")
	# Restore exact arrays, material and rendering settings before visual isolation.
	mesh.clear_surfaces(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, saved.arrays, [], saved.lods); mesh.surface_set_material(0, saved.material)
	env_node.environment = original_environment; root.msaa_3d = original_aa
	var source := comparison_shader(AFTER)
	var rows: Array = []
	for variant in ["baseline", "no_grass", "no_fade", "no_texture", "no_shadow_reception", "flat_grass", "full_detail", "far_lod_moderate", "far_lod_early"]:
		apply_shader(source); pose(0)
		Asset.set_grass_detail(grass_material, true)
		var lod_threshold := root.mesh_lod_threshold
		if variant == "no_grass" or variant == "flat_grass":
			var shader := Shader.new()
			shader.code = "shader_type spatial; render_mode unshaded,cull_disabled; void fragment(){" + ("discard;" if variant == "no_grass" else "ALBEDO=vec3(0.12,0.15,0.075);") + "}"
			grass_material.shader = shader
		if variant == "no_fade":
			grass_material.set_shader_parameter("distance_fade_start", 10000.0); grass_material.set_shader_parameter("distance_fade_end", 11000.0)
		if variant == "no_texture": grass_material.set_shader_parameter("grass_detail_strength", 0.0)
		if variant == "no_shadow_reception":
			var shader := Shader.new(); shader.code = source.code.replace("diffuse_burley", "diffuse_burley, shadows_disabled"); grass_material.shader = shader
		if variant == "full_detail": root.mesh_lod_threshold = 0.0
		if variant.begins_with("far_lod_"):
			var trial_lods := {0.02: saved.lods[0.02], (0.08 if variant == "far_lod_moderate" else 0.06): saved.lods[0.12], (0.14 if variant == "far_lod_moderate" else 0.10): saved.lods[0.2]}
			mesh.clear_surfaces(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, saved.arrays, [], trial_lods); mesh.surface_set_material(0, saved.material)
		await settle(8)
		var initial := root.get_texture().get_image()
		var mean_luma := 0.0
		for y in range(crop.position.y, crop.end.y, 2):
			for x in range(crop.position.x, crop.end.x, 2):
				var c := initial.get_pixel(x,y)
				mean_luma += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
		mean_luma /= float((crop.size.x / 2) * (crop.size.y / 2))
		picture(initial if variant == "baseline" else initial.get_region(crop), "world_" + variant, variant == "baseline")
		var changing := 0.0; var previous := initial.get_region(crop)
		for frame in 24:
			pose(frame + 1); await settle(2)
			var current := root.get_texture().get_image().get_region(crop)
			for y in range(0, crop.size.y, 2):
				for x in range(0, crop.size.x, 2):
					var a := current.get_pixel(x,y); var b := previous.get_pixel(x,y)
					changing += absf((a.r-b.r)*0.2126+(a.g-b.g)*0.7152+(a.b-b.b)*0.0722)
			previous = current
		picture(previous, "world_" + variant + "_end")
		rows.append({"variant": variant, "mean_luma": mean_luma, "screen_difference": changing / (24.0 * (crop.size.x / 2) * (crop.size.y / 2))})
		root.mesh_lod_threshold = lod_threshold
		if variant.begins_with("far_lod_"):
			mesh.clear_surfaces(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, saved.arrays, [], saved.lods); mesh.surface_set_material(0, saved.material)
		grass_material.set_shader_parameter("distance_fade_start",100.0); grass_material.set_shader_parameter("distance_fade_end",124.0)
	apply_shader(source); Asset.set_grass_detail(grass_material, true)
	diagnostic_report["world"] = {"views": views, "chosen": best_census, "camera": str(base_eye), "direction": str(direction), "crop": str(crop), "comparisons": rows, "scope": "Actual visible grass tags prove LOD identity at 60–124m with diagnostic camera elevation. Continuous matched 0.48m sideways travel; screen differences include expected motion/contrast and are descriptive, not visual acceptance or pure aliasing. Removing grass, detail, shadow reception or fade is diagnostic only. Unchanged native populations/pages and save are checked by the inherited loader."}

func run() -> void:
	var slot := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--check-evidence-dir="): output = argument.trim_prefix("--check-evidence-dir=")
		if argument.begins_with("--stability-source-slot="): slot = argument.trim_prefix("--stability-source-slot=")
		if argument.begins_with("--probe-kind="):
			var kind := argument.trim_prefix("--probe-kind=")
			if not kind in ["near", "low", "eight", "three"]: push_error("Unknown mesh probe"); quit(1); return
			probe_kinds = [kind]
		if argument == "--world-only": world_only = true
	if output.is_empty(): push_error("Use the admitted check runner"); quit(1); return
	if world_only and slot.is_empty(): push_error("--world-only requires an existing --stability-source-slot"); quit(1); return
	Engine.max_fps = 60
	diagnostic_report["shader_sha256"] = FileAccess.get_sha256(AFTER)
	diagnostic_report["mesh_sha256"] = FileAccess.get_sha256("res://addons/world_ecosystem/woodland_mesh.gd")
	FileAccess.open(output.path_join("driver.gd"), FileAccess.WRITE).store_string(FileAccess.get_file_as_string("res://tests/vegetation_causes.gd"))
	if not world_only: await silhouette_probe()
	FileAccess.open(output.path_join("vegetation_causes.json"), FileAccess.WRITE).store_string(JSON.stringify(diagnostic_report, "  "))
	if not slot.is_empty(): await actual_world(slot)
	diagnostic_report.merge({"checks": checks, "failures": failures, "world_input": results.get("world_input", {}), "image_bytes": image_bytes, "production_changed": false})
	FileAccess.open(output.path_join("vegetation_causes.json"), FileAccess.WRITE).store_string(JSON.stringify(diagnostic_report, "  "))
	if not FileAccess.file_exists("res://tests/vegetation_causes.gd.uid"):
		FileAccess.open("res://tests/vegetation_causes.gd.uid", FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id()) + "\n")
	print("VEGETATION_CAUSES failures=", failures)
	quit(1 if failures else 0)

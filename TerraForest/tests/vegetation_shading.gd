# SPDX-License-Identifier: 0BSD
extends SceneTree
# Bounded render-only comparison: no world, native rebuild, export or saved state.
const Asset = preload("res://addons/world_ecosystem/woodland_mesh.gd")
const SOURCE = "res://addons/world_ecosystem/woodland.gdshader"
const OLD_FLIP = "if (!FRONT_FACING) { NORMAL = -NORMAL; }"
var failures := 0
var checks := 0
var output := ""
var world: Node3D
var camera: Camera3D
var batches: Array[MultiMeshInstance3D] = []
var materials: Array[ShaderMaterial] = []
var captured_bytes := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func settle() -> void:
	for frame in 10: await RenderingServer.frame_post_draw

func shader_material(source: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = source
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("wind_strength", 0.0)
	material.set_shader_parameter("cover_eye", camera.position)
	material.set_shader_parameter("distance_fade_start", 100.0)
	material.set_shader_parameter("distance_fade_end", 124.0)
	return material

func probe(source: String) -> Array[float]:
	# Encode the actual view-space normal after the production fragment. A
	# double-sided leaf must face the viewer from both sides, so both are white.
	var code := source.replace("cull_disabled, diffuse_burley", "cull_disabled, unshaded")
	code = code.insert(code.rfind("}"), "\nALBEDO = vec3(max(NORMAL.z, 0.0));\n")
	var leaf := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	leaf.mesh = quad
	leaf.material_override = shader_material(code)
	world.add_child(leaf)
	var samples: Array[float] = []
	for angle in [0.0, PI]:
		leaf.rotation.y = angle
		await settle()
		var frame := root.get_texture().get_image()
		samples.append(frame.get_pixel(root.size.x / 2, root.size.y / 2).r)
	leaf.free()
	return samples

func appearance(source: String, label: String) -> Dictionary:
	for material in materials:
		var shader := Shader.new()
		shader.code = source
		material.shader = shader
	await settle()
	var image := root.get_texture().get_image()
	var png := image.save_png_to_buffer()
	captured_bytes += png.size()
	if captured_bytes > 20 * 1024 * 1024:
		push_error("Vegetation comparison exceeded its admitted 20 MiB capture ceiling")
		quit(1)
		return {}
	FileAccess.open(output.path_join(label + ".png"), FileAccess.WRITE).store_buffer(png)
	var dark := 0
	for y in range(160, 1000, 2):
		for x in range(180, 1740, 2):
			var pixel := image.get_pixel(x, y)
			if maxf(pixel.r, maxf(pixel.g, pixel.b)) < 0.12: dark += 1
	return {"label": label, "dark_pixels": dark, "image_sha256": image.get_data().hex_encode().sha256_text()}

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--check-evidence-dir="): output = argument.get_slice("=", 1)
	if output.is_empty():
		push_error("Use tools/run_godot_check.py for storage admission and receipt ownership")
		quit(1)
		return
	Engine.max_fps = 60
	world = Node3D.new()
	root.add_child(world)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.position = Vector3(0, 0, 3)
	camera.look_at(Vector3.ZERO)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("859166")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b8c3ce")
	environment.environment.ambient_light_energy = 0.55
	world.add_child(environment)
	var source := FileAccess.get_file_as_string(SOURCE)
	var candidate := source.replace(OLD_FLIP, "")
	var baseline := source
	if not baseline.contains(OLD_FLIP):
		baseline = source.replace("// Godot already faces double-sided normals toward the viewer.", OLD_FLIP)
	var old_probe: Array[float] = await probe(baseline)
	var new_probe: Array[float] = await probe(candidate)
	var production_probe: Array[float] = await probe(source)
	check(old_probe[0] > 0.9 and old_probe[1] < 0.1, "baseline reproduces reversed back-face lighting normal")
	check(new_probe[0] > 0.9 and new_probe[1] > 0.9, "candidate normals face viewer on both leaf sides")
	check(production_probe[0] > 0.9 and production_probe[1] > 0.9, "production normals face viewer on both leaf sides")
	camera.position = Vector3(0, 16, 28)
	camera.look_at(Vector3(0, 0, -35))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -27, 0)
	light.light_color = Color("fff0d4")
	light.light_energy = 1.3
	world.add_child(light)
	var floor_view := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(120, 180)
	floor_view.mesh = floor_mesh
	floor_view.position = Vector3(0, -0.015, -45)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("859166")
	floor_material.roughness = 1.0
	floor_view.material_override = floor_material
	world.add_child(floor_view)
	var population := 0
	for species in [1, 2, 6, 7]:
		var mesh := Asset.build(species)
		var material := shader_material(baseline)
		materials.append(material)
		mesh.surface_set_material(0, material)
		for row in 8:
			for column in 8:
				var instances := MultiMesh.new()
				instances.transform_format = MultiMesh.TRANSFORM_3D
				instances.mesh = mesh
				instances.instance_count = 144 if species == 2 else 4
				for index in instances.instance_count:
					var phase: float = index * 2.399963 + row * 7.3 + column * 3.7 + species
					var position := Vector3(column * 12.0 - 48.0 + fmod(index * 3.713, 12.0), 0, -row * 12.0 + fmod(index * 7.717, 12.0))
					instances.set_instance_transform(index, Transform3D(Basis(Vector3.UP, phase), position))
				var view := MultiMeshInstance3D.new()
				view.multimesh = instances
				view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				world.add_child(view)
				batches.append(view)
				population += instances.instance_count
	var rows: Array[Dictionary] = []
	rows.append(await appearance(baseline, "baseline"))
	rows.append(await appearance(candidate, "corrected"))
	rows.append(await appearance(baseline, "baseline_repeat"))
	check(rows[0].image_sha256 == rows[2].image_sha256, "frozen baseline repeats exactly")
	check(rows[0].image_sha256 != rows[1].image_sha256, "normal correction changes actual foliage lighting")
	var snapshots: Array[PackedByteArray] = []
	for view in batches: snapshots.append(view.multimesh.buffer.to_byte_array())
	for step in 3:
		camera.position.x = (step - 1) * 0.15
		camera.look_at(Vector3(camera.position.x, 0, -35))
		for material in materials: material.set_shader_parameter("cover_eye", camera.position)
		rows.append(await appearance(baseline, "motion_%d_before" % step))
		rows.append(await appearance(candidate, "motion_%d_after" % step))
	var unchanged := true
	for index in batches.size(): unchanged = unchanged and batches[index].multimesh.buffer.to_byte_array() == snapshots[index]
	check(unchanged, "comparison preserves every instance transform and population")
	check(root.size == Vector2i(1920, 1080), "1080p comparison")
	var result := {"checks": checks, "failures": failures, "population": population, "baseline_probe": old_probe, "corrected_probe": new_probe, "production_probe": production_probe, "rows": rows, "scope": "Render-only synthetic meadow with unchanged production meshes and population. Three matched camera positions; no actual-world, GPU speedup, complete shimmer or user-acceptance claim."}
	FileAccess.open(output.path_join("vegetation_shading.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	world.free()
	await process_frame
	print("VEGETATION_SHADING failures=", failures)
	quit(1 if failures else 0)

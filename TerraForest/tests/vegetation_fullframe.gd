# SPDX-License-Identifier: 0BSD
extends "res://tests/vegetation_stability.gd"
# Full viewport counterfactuals. Raw pixels go to a bounded, local analyzer;
# simulation is frozen only for causal comparisons, never the gameplay gate.
var peer := StreamPeerTCP.new()
var original_shaders: Dictionary = {}
var all_materials: Array[ShaderMaterial] = []
var token := ""
var port := 0
var frame_count := 48

func retains_runtime_far_filter() -> bool: return true

func transmit(meta: Dictionary, pixels: PackedByteArray = PackedByteArray()) -> bool:
	meta["token"] = token
	meta["bytes"] = pixels.size()
	var header := JSON.stringify(meta).to_utf8_buffer()
	peer.put_u32(header.size())
	if peer.put_data(header) != OK or peer.put_data(pixels) != OK:
		check(false, "full-frame stream write"); return false
	var deadline := Time.get_ticks_msec() + 30000
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and peer.get_available_bytes() == 0 and Time.get_ticks_msec() < deadline:
		peer.poll(); await process_frame
	return check(peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and peer.get_available_bytes() > 0 and peer.get_u8() == 1, "full-frame analyzer accepted " + str(meta.get("case", meta.get("kind"))))

func configure_case(mode: String) -> void:
	for material: ShaderMaterial in all_materials:
		var code: String = original_shaders[material].code
		# Reconstruct only the three former unsafe expressions when rerunning
		# against the fixed source. Every other production expression is retained.
		code = code.replace("float edge = min(abs(UV.x - 0.5) * 2.0, 1.0);", "float edge = abs(UV.x - 0.5) * 2.0;").replace("clamp(root_shade,0.64,1.0)", "root_shade").replace("clamp(canopy_shade,1.0-distant_self_shade,1.0)", "canopy_shade")
		code = code.replace("shader_type spatial;", "shader_type spatial;\nuniform float comparison_time = 0.0;").replace("TIME", "comparison_time")
		if mode in ["bounded_edge", "bounded_witness", "bounded_interpolants", "interpolant_witness"]:
			code = code.replace("float edge = abs(UV.x - 0.5) * 2.0;", "float edge = min(abs(UV.x - 0.5) * 2.0, 1.0);")
		if mode in ["bounded_interpolants", "interpolant_witness"]:
			code = code.replace("ALBEDO *= root_shade;", "ALBEDO *= clamp(root_shade,0.64,1.0);").replace("* root_shade * modulation", "* clamp(root_shade,0.64,1.0) * modulation").replace("ALBEDO *= canopy_shade;", "ALBEDO *= clamp(canopy_shade,1.0-distant_self_shade,1.0);")
		if mode in ["invalid_witness", "bounded_witness", "interpolant_witness"]:
			# Magenta: negative finite albedo; cyan: non-finite; yellow: >1.
			# Run the original expression before replacing its result for diagnosis.
			code = code.replace("render_mode ", "render_mode unshaded, fog_disabled, ")
			var tail := code.rfind("}")
			code = code.insert(tail, "\n bool bad = any(isnan(ALBEDO)) || any(isinf(ALBEDO));\n bool neg = any(lessThan(ALBEDO,vec3(0.0)));\n bool high = any(greaterThan(ALBEDO,vec3(1.0)));\n ALBEDO = bad ? vec3(0.0,1.0,1.0) : (neg ? vec3(1.0,0.0,1.0) : (high ? vec3(1.0,1.0,0.0) : vec3(0.0)));\n EMISSION=vec3(0.0);\n")
		if mode == "no_cover": code = code.replace("void fragment() {", "void fragment() { discard;")
		var shader := Shader.new(); shader.code = code; material.shader = shader
		material.set_shader_parameter("cover_clock", 1000000.0)
		material.set_shader_parameter("comparison_time", 0.0)

func full_pose(frame: int) -> void:
	var elevated := frame >= frame_count / 2
	var local_frame := frame % (frame_count / 2)
	camera.global_position = base_eye + Vector3(local_frame * 0.08 - 1.0, 32.0 if elevated else 0.0, -local_frame * 0.035)
	camera.look_at(camera.global_position + Vector3(0, -26.0 if elevated else -8.0, -60))
	for material: ShaderMaterial in all_materials:
		material.set_shader_parameter("cover_eye", camera.global_position)
		material.set_shader_parameter("comparison_time", local_frame / 60.0)
	# The native page selection remains fixed, as do geometry and population.

func compare(_label: String) -> void:
	Engine.time_scale = 0.0
	for mesh: ArrayMesh in game.ground_cover.preview_meshes:
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as ShaderMaterial
			if material != null and not all_materials.has(material):
				all_materials.append(material); original_shaders[material] = material.shader
	check(all_materials.size() >= 15, "all species and near/far surface materials included")
	if not await transmit({"kind":"begin", "output":output,"frames":frame_count,"width":1920,"height":1080}): return
	for mode in ["baseline", "bounded_edge", "bounded_interpolants", "invalid_witness", "bounded_witness", "interpolant_witness", "no_cover", "baseline_repeat"]:
		configure_case(mode); full_pose(0); await settle(24)
		for frame in (1 if mode == "baseline_repeat" else frame_count):
			full_pose(frame); await settle(2)
			var capture := root.get_texture().get_image(); capture.convert(Image.FORMAT_RGB8)
			if not await transmit({"kind":"frame","case":mode,"frame":frame,"camera":str(camera.global_transform)},capture.get_data()): return
	for material: ShaderMaterial in all_materials: material.shader = original_shaders[material]
	Engine.time_scale = 1.0
	await transmit({"kind":"end"})

func run() -> void:
	var slot := "Homestead_Valley"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--check-evidence-dir="): output = argument.trim_prefix("--check-evidence-dir=")
		if argument.begins_with("--fullframe-port="): port = int(argument.trim_prefix("--fullframe-port="))
		if argument.begins_with("--lab-run-id="): token = argument.trim_prefix("--lab-run-id=")
	if output.is_empty() or port == 0 or token.length() != 32: push_error("Use the admitted full-frame launcher"); quit(1); return
	peer.big_endian = false; peer.connect_to_host("127.0.0.1", port)
	check(await wait_for(func(): peer.poll(); return peer.get_status() == StreamPeerTCP.STATUS_CONNECTED, 10), "local raw-pixel analyzer connected")
	FileAccess.open(output.path_join("vegetation_fullframe.gd"),FileAccess.WRITE).store_string(FileAccess.get_file_as_string("res://tests/vegetation_fullframe.gd"))
	FileAccess.open(output.path_join("woodland.gdshader"),FileAccess.WRITE).store_string(FileAccess.get_file_as_string(AFTER))
	Engine.max_fps = 60
	await actual_world(slot)
	results.merge({"checks":checks,"failures":failures,"scope":"Entire raw 1080p viewport; deterministic camera counterfactual, separate from physical gameplay. No timing claims."})
	FileAccess.open(output.path_join("vegetation_fullframe.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	if not FileAccess.file_exists("res://tests/vegetation_fullframe.gd.uid"):
		FileAccess.open("res://tests/vegetation_fullframe.gd.uid",FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	print("VEGETATION_FULLFRAME failures=",failures)
	quit(1 if failures else 0)

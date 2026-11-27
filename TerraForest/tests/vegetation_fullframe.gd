# SPDX-License-Identifier: 0BSD
extends "res://tests/vegetation_stability.gd"
# Full viewport counterfactuals. Raw pixels go to a bounded, local analyzer;
# simulation is frozen only for causal comparisons, never the gameplay gate.
var peer := StreamPeerTCP.new()
var original_shaders: Dictionary = {}
var all_materials: Array[ShaderMaterial] = []
var token := ""
var transition_review := false
var transition_cost: Array = []
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
	if transition_review:
		for material: ShaderMaterial in all_materials:
			var code: String=original_shaders[material].code
			if original_shaders[material]==preload("res://addons/world_ecosystem/filtered_stone.gdshader") and mode in ["baseline","baseline_repeat","near_baseline"]:
				code=FileAccess.get_file_as_string("res://tests/fixtures/stone_pre_transition.gdshader")
			code=code.replace("shader_type spatial;", "shader_type spatial;\nuniform float comparison_time=0.0;").replace("TIME","comparison_time")
			if mode=="no_cover":code=code.replace("void fragment(){","void fragment(){discard;").replace("void fragment() {","void fragment() {discard;")
			var replacement := Shader.new();replacement.code=code;material.shader=replacement
			material.set_shader_parameter("cover_clock",1000000.0)
			material.set_shader_parameter("comparison_time",0.0)
			material.set_shader_parameter("distance_fade_start",92.0 if mode in ["stone_fade","near_corrected"] else 100.0)
			material.set_shader_parameter("distance_fade_end",124.0)
		return
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
	if transition_review:
		for batch in game.ground_cover.batches:batch.update_surface_lod()
	# Instance geometry and population stay fixed.

func compare(_label: String) -> void:
	Engine.time_scale = 0.0
	for mesh: ArrayMesh in game.ground_cover.preview_meshes:
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as ShaderMaterial
			if material != null and not all_materials.has(material):
				all_materials.append(material); original_shaders[material] = material.shader
	check(all_materials.size() >= 15, "all species and near/far surface materials included")
	if not await transmit({"kind":"begin", "output":output,"frames":frame_count,"width":1920,"height":1080,"variant":"stone_transition" if transition_review else "shader_domain"}): return
	var modes: Array = ["baseline","stone_corrected","stone_fade","no_cover","baseline_repeat"] if transition_review else ["baseline", "bounded_edge", "bounded_interpolants", "invalid_witness", "bounded_witness", "interpolant_witness", "no_cover", "baseline_repeat"]
	for mode in modes:
		configure_case(mode); full_pose(0); await settle(24)
		for frame in (1 if mode == "baseline_repeat" else frame_count):
			full_pose(frame); await settle(2)
			var capture := root.get_texture().get_image(); capture.convert(Image.FORMAT_RGB8)
			if not await transmit({"kind":"frame","case":mode,"frame":frame,"camera":str(camera.global_transform)},capture.get_data()): return
	if transition_review:
		var near_pixels := PackedByteArray()
		for mode in ["near_baseline","near_corrected"]:
			configure_case(mode)
			camera.global_position=base_eye;camera.look_at(base_eye+Vector3(0,-1.6,-1.1))
			for mat in all_materials:mat.set_shader_parameter("cover_eye",camera.global_position)
			for batch in game.ground_cover.batches:batch.update_surface_lod()
			await settle(16)
			var pixels := root.get_texture().get_image();pixels.convert(Image.FORMAT_RGB8)
			var scene_pixels := pixels.get_region(Rect2i(0,320,1920,580)).get_data()
			if mode=="near_baseline":near_pixels=scene_pixels
			else:check(scene_pixels==near_pixels,"nearby world pixels unchanged by stone correction and outer fade")
			if not await transmit({"kind":"frame","case":mode,"frame":0},pixels.get_data()):return
		# Readbacks and encoders finish before paired GPU windows.
		await transmit({"kind":"end"})
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
		var fps := Engine.max_fps;var vsync := DisplayServer.window_get_vsync_mode()
		Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		for group in 3:
			for mode in ["baseline","stone_fade","stone_fade","baseline"]:
				configure_case(mode);full_pose(8);await settle(90)
				var samples: Array=[]
				for frame in 120:
					full_pose(frame%24);await RenderingServer.frame_post_draw
					samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
				transition_cost.append({"group":group,"case":mode,"gpu_ms":samples})
		Engine.max_fps=fps;DisplayServer.window_set_vsync_mode(vsync)
	for material: ShaderMaterial in all_materials: material.shader = original_shaders[material]
	Engine.time_scale = 1.0
	if not transition_review:await transmit({"kind":"end"})

func run() -> void:
	var slot := "Homestead_Valley"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--check-evidence-dir="): output = argument.trim_prefix("--check-evidence-dir=")
		if argument=="--stone-transition-review":transition_review=true
		if argument.begins_with("--fullframe-port="): port = int(argument.trim_prefix("--fullframe-port="))
		if argument.begins_with("--lab-run-id="): token = argument.trim_prefix("--lab-run-id=")
	if output.is_empty() or port == 0 or token.length() != 32: push_error("Use the admitted full-frame launcher"); quit(1); return
	peer.big_endian = false; peer.connect_to_host("127.0.0.1", port)
	check(await wait_for(func(): peer.poll(); return peer.get_status() == StreamPeerTCP.STATUS_CONNECTED, 10), "local raw-pixel analyzer connected")
	FileAccess.open(output.path_join("vegetation_fullframe.gd"),FileAccess.WRITE).store_string(FileAccess.get_file_as_string("res://tests/vegetation_fullframe.gd"))
	FileAccess.open(output.path_join("woodland.gdshader"),FileAccess.WRITE).store_string(FileAccess.get_file_as_string(AFTER))
	Engine.max_fps = 60
	await actual_world(slot)
	results.merge({"checks":checks,"failures":failures,"transition_cost":transition_cost,"scope":"Entire raw 1080p viewport; deterministic camera counterfactual, separate from physical gameplay. No timing claims."})
	FileAccess.open(output.path_join("vegetation_fullframe.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	if not FileAccess.file_exists("res://tests/vegetation_fullframe.gd.uid"):
		FileAccess.open("res://tests/vegetation_fullframe.gd.uid",FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	print("VEGETATION_FULLFRAME failures=",failures)
	quit(1 if failures else 0)

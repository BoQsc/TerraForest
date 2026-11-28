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
var near_review := false
var near_meshes:Dictionary={}
var near_page_witness:Array=[]
var near_parity := false
var near_cost_only := false

func select_near_mesh(candidate:bool) -> void:
	var mesh:ArrayMesh=near_meshes.candidate if candidate else near_meshes.baseline
	var batch:Node=game.ground_cover.batches[2]
	check(batch.configure_asset("ground_cover/2/v1",mesh),"grass mesh selection")
	check(preload("res://addons/world_ecosystem/filtered_grass.gd").configure_batch(batch,mesh),"native grass surface selection")

func camera_pose_control() -> void:
	camera.global_transform=Transform3D(Basis.looking_at(Vector3(0,-1.6,-1.1)),base_eye)
	await settle(8)
	var reference:=root.get_texture().get_image();reference.convert(Image.FORMAT_RGB8)
	var pixels:=reference.get_region(Rect2i(0,320,1920,580)).get_data()
	var fixed_local:=camera.transform
	var fixed_global:=camera.global_transform
	var observations:Array=[]
	for iteration in 3:
		camera.global_position=base_eye;camera.look_at(base_eye+Vector3(0,-1.6,-1.1))
		await settle(2)
		var probe:=root.get_texture().get_image();probe.convert(Image.FORMAT_RGB8)
		observations.append({"transform_equal":var_to_bytes(camera.global_transform)==var_to_bytes(fixed_global),"image_equal":probe.get_region(Rect2i(0,320,1920,580)).get_data()==pixels,"matrix_bytes":var_to_bytes(camera.global_transform).hex_encode()})
	# Restore the exact local matrix. Feeding the observed global matrix back
	# through the parent inverse introduces another precision-losing round trip.
	camera.transform=fixed_local;await settle(8)
	var restored:=root.get_texture().get_image();restored.convert(Image.FORMAT_RGB8)
	results["camera_negative_control"]={"legacy_assignments":observations,"fixed_transform_restores_pixels":restored.get_region(Rect2i(0,320,1920,580)).get_data()==pixels,"fixed_transform_restores_matrix":var_to_bytes(camera.global_transform)==var_to_bytes(fixed_global)}
	check(results.camera_negative_control.fixed_transform_restores_pixels and results.camera_negative_control.fixed_transform_restores_matrix,"exact local camera restore reverses legacy assignment artifact")

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
	if near_review:
		select_near_mesh(mode in ["near_fade","near_corrected"])
		for material:ShaderMaterial in all_materials:
			var code:String=original_shaders[material].code
			code=code.replace("shader_type spatial;","shader_type spatial;\nuniform float comparison_time=0.0;").replace("TIME","comparison_time")
			if mode=="no_cover":code=code.replace("void fragment(){","void fragment(){discard;").replace("void fragment() {","void fragment() {discard;")
			var replacement:=Shader.new();replacement.code=code;material.shader=replacement
			material.set_shader_parameter("cover_clock",1000000.0)
			material.set_shader_parameter("comparison_time",0.0)
		return
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
	# Assign one complete transform. Repeated world-position + look_at round trips
	# through the rotated player parent drift at large world coordinates.
	camera.global_transform=Transform3D(Basis.looking_at(Vector3(0,-26.0 if elevated else -8.0,-60)),base_eye+Vector3(local_frame*.08-1.0,32.0 if elevated else 0.0,-local_frame*.035))
	if near_review:
		camera.global_transform=Transform3D(Basis.looking_at(Vector3(0,-6,-35)),base_eye+Vector3(frame*.025,0,-frame*.10))
	for material: ShaderMaterial in all_materials:
		material.set_shader_parameter("cover_eye", camera.global_position)
		material.set_shader_parameter("comparison_time", local_frame / 60.0)
	if transition_review or near_review:
		for batch in game.ground_cover.batches:batch.update_surface_lod()
	# Instance geometry and population stay fixed.

func compare(_label: String) -> void:
	Engine.time_scale = 0.0
	if near_review:
		near_meshes.candidate=game.ground_cover.preview_meshes[2]
		near_meshes.baseline=Asset.build(2,true,true,false,true,false)
		var baseline:ArrayMesh=near_meshes.baseline
		Asset.set_grass_detail(baseline.surface_get_material(0),true)
		for surface in baseline.get_surface_count():
			var mat:ShaderMaterial=baseline.surface_get_material(surface)
			mat.set_shader_parameter("distance_fade_start",92.0);mat.set_shader_parameter("distance_fade_end",124.0)
			all_materials.append(mat);original_shaders[mat]=mat.shader
	for mesh: ArrayMesh in game.ground_cover.preview_meshes:
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as ShaderMaterial
			if material != null and not all_materials.has(material):
				all_materials.append(material); original_shaders[material] = material.shader
	check(all_materials.size() >= 15, "all species and near/far surface materials included")
	if near_parity:
		if not await transmit({"kind":"begin","output":output,"frames":48,"width":1920,"height":1080,"variant":"near_parity"}):return
		var suns:=game.find_children("*","DirectionalLight3D",true,false)
		results["near_parity_suns"]=suns.size()
		var terrain_snapshots:Array=[]
		for mode in ["baseline","same_baseline","near_fade","baseline_repeat","near_full","baseline_no_shadow","candidate_no_shadow"]:
			if mode!="same_baseline":configure_case("near_fade" if mode in ["near_fade","candidate_no_shadow","near_full"] else "baseline")
			for sun in suns:sun.shadow_enabled=not mode.ends_with("no_shadow")
			near_meshes.candidate.surface_get_material(0).set_shader_parameter("near_lod_metric",703.74)
			camera.global_transform=Transform3D(Basis.looking_at(Vector3(0,-1.6,-1.1)),base_eye)
			for mat in all_materials:mat.set_shader_parameter("cover_eye",camera.global_position)
			if mode=="near_full":near_meshes.candidate.surface_get_material(0).set_shader_parameter("near_lod_metric",1000000.0)
			for batch in game.ground_cover.batches:batch.update_surface_lod()
			await settle(24)
			var terrain_rows:Array=[]
			for node in game.terrain.find_children("*","MeshInstance3D",true,false):
				if node.visible:terrain_rows.append([str(node.get_path()),node.mesh.get_rid().get_id(),str(node.global_transform),str(node.get_aabb())])
			terrain_snapshots.append({"case":mode,"nodes":terrain_rows,"camera":str(camera.global_transform),"camera_bytes":var_to_bytes(camera.global_transform).hex_encode()})
			var pixels:=root.get_texture().get_image();pixels.convert(Image.FORMAT_RGB8)
			if not await transmit({"kind":"frame","case":mode,"frame":0},pixels.get_data()):return
		results["near_parity_terrain"]=terrain_snapshots
		await camera_pose_control()
		await transmit({"kind":"end"})
		for mat in all_materials:mat.shader=original_shaders[mat]
		select_near_mesh(true);Engine.time_scale=1.0;return
	if not await transmit({"kind":"begin", "output":output,"frames":frame_count,"width":1920,"height":1080,"variant":"near_cost" if near_cost_only else ("near_transition" if near_review else ("stone_transition" if transition_review else "shader_domain"))}): return
	var modes: Array = ["baseline","stone_corrected","stone_fade","no_cover","baseline_repeat"] if transition_review else ["baseline", "bounded_edge", "bounded_interpolants", "invalid_witness", "bounded_witness", "interpolant_witness", "no_cover", "baseline_repeat"]
	if near_review:modes=["baseline","near_fade","no_cover","baseline_repeat"]
	if near_cost_only:modes=[]
	for mode in modes:
		configure_case(mode); full_pose(0); await settle(24)
		for frame in (1 if mode == "baseline_repeat" else frame_count):
			full_pose(frame); await settle(2)
			if near_review and mode=="baseline":
				var metric:float=root.size.x/(root.mesh_lod_threshold*camera.get_camera_projection().get_lod_multiplier())
				var pages:Array=[]
				for page in game.ground_cover.batches[2].get_children():
					if not page is MultiMeshInstance3D or not page.visible:continue
					var box:AABB=page.global_transform*page.multimesh.get_aabb()
					var distance:float=camera.global_position.distance_to(camera.global_position.clamp(box.position,box.end))
					if distance>40 or not camera.is_position_in_frustum(box.get_center()):continue
					pages.append({"id":page.get_instance_id(),"distance":distance,"full":distance<.02*metric,"bounds_min":str(box.position),"bounds_size":str(box.size),"screen_center":str(camera.unproject_position(box.get_center()))})
				near_page_witness.append({"frame":frame,"pages":pages})
			var capture := root.get_texture().get_image(); capture.convert(Image.FORMAT_RGB8)
			if not await transmit({"kind":"frame","case":mode,"frame":frame,"camera":str(camera.global_transform)},capture.get_data()): return
	if near_review and not near_cost_only:
		configure_case("baseline");full_pose(24)
		var tagged_pages:Array=[]
		var metric:float=root.size.x/(root.mesh_lod_threshold*camera.get_camera_projection().get_lod_multiplier())
		for page in game.ground_cover.batches[2].get_children():
			if not page is MultiMeshInstance3D or not page.visible:continue
			var box:AABB=page.global_transform*page.multimesh.get_aabb()
			var distance:float=camera.global_position.distance_to(camera.global_position.clamp(box.position,box.end))
			if distance>28:continue
			var mat:ShaderMaterial=near_meshes.baseline.surface_get_material(0).duplicate()
			var code:String=mat.shader.code.replace("render_mode ","render_mode unshaded, ")
			code=code.insert(code.rfind("}"),"\nALBEDO="+("vec3(0.9,0.1,0.1)" if distance<.02*metric else "vec3(0.1,0.2,0.9)")+";\n")
			mat.shader=Shader.new();mat.shader.code=code
			mat.set_shader_parameter("cover_eye",camera.global_position)
			page.material_override=mat;tagged_pages.append(page)
		await settle(12)
		var witness:=root.get_texture().get_image();witness.convert(Image.FORMAT_RGB8)
		if not await transmit({"kind":"frame","case":"page_witness","frame":0},witness.get_data()):return
		for page in tagged_pages:page.material_override=null
	if transition_review or near_review:
		var near_pixels := PackedByteArray()
		for mode in ([] if near_cost_only else ["near_baseline","near_corrected"]):
			configure_case(mode)
			camera.global_transform=Transform3D(Basis.looking_at(Vector3(0,-1.6,-1.1)),base_eye)
			for mat in all_materials:mat.set_shader_parameter("cover_eye",camera.global_position)
			for batch in game.ground_cover.batches:batch.update_surface_lod()
			await settle(16)
			var pixels := root.get_texture().get_image();pixels.convert(Image.FORMAT_RGB8)
			var scene_pixels := pixels.get_region(Rect2i(0,320,1920,580)).get_data()
			if mode=="near_baseline":near_pixels=scene_pixels
			else:check(scene_pixels==near_pixels,"nearby world pixels unchanged by candidate")
			if not await transmit({"kind":"frame","case":mode,"frame":0},pixels.get_data()):return
		if near_review and not near_cost_only:await camera_pose_control()

		# Readbacks and encoders finish before paired GPU windows.
		await transmit({"kind":"end"})
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
		var fps := Engine.max_fps;var vsync := DisplayServer.window_get_vsync_mode()
		Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		for group in 3:
			for mode in (["baseline","near_fade","near_fade","baseline"] if near_review else ["baseline","stone_fade","stone_fade","baseline"]):
				configure_case(mode);full_pose(8);await settle(90)
				var samples: Array=[]
				for frame in 120:
					full_pose(frame%24);await RenderingServer.frame_post_draw
					samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
				transition_cost.append({"group":group,"case":mode,"gpu_ms":samples})
		Engine.max_fps=fps;DisplayServer.window_set_vsync_mode(vsync)
	for material: ShaderMaterial in all_materials: material.shader = original_shaders[material]
	Engine.time_scale = 1.0
	if near_review:select_near_mesh(true)
	if not (transition_review or near_review):await transmit({"kind":"end"})

func run() -> void:
	var slot := "Homestead_Valley"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--check-evidence-dir="): output = argument.trim_prefix("--check-evidence-dir=")
		if argument=="--stone-transition-review":transition_review=true
		if argument=="--near-transition-review":near_review=true
		if argument=="--near-parity":near_review=true;near_parity=true
		if argument=="--near-cost-only":near_review=true;near_cost_only=true
		if argument.begins_with("--fullframe-port="): port = int(argument.trim_prefix("--fullframe-port="))
		if argument.begins_with("--lab-run-id="): token = argument.trim_prefix("--lab-run-id=")
	if output.is_empty() or port == 0 or token.length() != 32: push_error("Use the admitted full-frame launcher"); quit(1); return
	peer.big_endian = false; peer.connect_to_host("127.0.0.1", port)
	check(await wait_for(func(): peer.poll(); return peer.get_status() == StreamPeerTCP.STATUS_CONNECTED, 10), "local raw-pixel analyzer connected")
	FileAccess.open(output.path_join("vegetation_fullframe.gd"),FileAccess.WRITE).store_string(FileAccess.get_file_as_string("res://tests/vegetation_fullframe.gd"))
	FileAccess.open(output.path_join("woodland.gdshader"),FileAccess.WRITE).store_string(FileAccess.get_file_as_string(AFTER))
	Engine.max_fps = 60
	await actual_world(slot)
	results.merge({"checks":checks,"failures":failures,"transition_cost":transition_cost,"near_page_witness":near_page_witness,"near_review":near_review,"scope":"Entire raw 1080p viewport; deterministic camera counterfactual, separate from physical gameplay. Paired GPU windows exclude readback; frozen local population only."})
	FileAccess.open(output.path_join("vegetation_fullframe.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	if not FileAccess.file_exists("res://tests/vegetation_fullframe.gd.uid"):
		FileAccess.open("res://tests/vegetation_fullframe.gd.uid",FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	print("VEGETATION_FULLFRAME failures=",failures)
	quit(1 if failures else 0)

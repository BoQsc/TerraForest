# SPDX-License-Identifier: 0BSD
extends "res://tests/vegetation_transitions.gd"
# Unpromoted experiment: first opaque grass LOD only. This deliberately contains
# no billboard/filter quads, streaming or spawning, to isolate rectangular batch
# changes. The production resources are never mutated.
var trial: ArrayMesh
var trial_alpha: ArrayMesh
var tagged: ArrayMesh
var shader_sources: Dictionary={}
var costs: Array=[]
var endpoints := {}
var full_indices := PackedInt32Array()
var low_indices := PackedInt32Array()
var active_case := ""
var region := Rect2i(448,480,1024,128)
var produced_bytes := 0
var production_near := false

func store_file(name: String,bytes: PackedByteArray) -> void:
	produced_bytes+=bytes.size()
	if produced_bytes>11*1024*1024:check(false,"12 MiB admitted output cap");quit(1);return
	FileAccess.open(output.path_join(name),FileAccess.WRITE).store_buffer(bytes)

func material_for(code: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	code=code.replace("shader_type spatial;","shader_type spatial;\nuniform float comparison_time=0.0;").replace("TIME","comparison_time")
	mat.shader=shader(code);mat.set_shader_parameter("cover_clock",1000000.0)
	materials.append(mat);return mat

func mesh_for(arrays: Array,indices: PackedInt32Array,lods: Dictionary,mat: ShaderMaterial) -> ArrayMesh:
	var values := arrays.duplicate(true);values[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,values,[],lods)
	mesh.surface_set_material(0,mat);mesh.custom_aabb=source.custom_aabb if source!=null else AABB(Vector3(-.4,0,-.4),Vector3(.8,.75,.8))
	return mesh

func setup() -> void:
	world=Node3D.new();root.add_child(world)
	camera=Camera3D.new();world.add_child(camera);camera.current=true;camera.fov=75
	var env := WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("859166")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("b8c3ce");env.environment.ambient_light_energy=.55;world.add_child(env)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-52,-27,0);sun.light_energy=1.3;sun.shadow_enabled=production_near;world.add_child(sun)
	var ground := MeshInstance3D.new();var plane := PlaneMesh.new();plane.size=Vector2(250,250);ground.mesh=plane;ground.position.y=-.03
	var tint := StandardMaterial3D.new();tint.albedo_color=Color("859166");tint.roughness=1;ground.material_override=tint;world.add_child(ground)
	var authored := Asset.build(2,false)
	var saved := preload("res://tests/fixtures/grass_filtered.gd").capture(authored)
	var arrays: Array=saved.arrays
	full_indices=arrays[Mesh.ARRAY_INDEX];low_indices=saved.lods[.02]
	var tier := PackedVector2Array();tier.resize(arrays[Mesh.ARRAY_VERTEX].size())
	for index in low_indices:tier[index]=Vector2(1,0)
	arrays[Mesh.ARRAY_TEX_UV2]=tier
	var code := FileAccess.get_file_as_string("res://addons/world_ecosystem/woodland.gdshader")
	var baseline_code:=FileAccess.get_file_as_string("res://tests/fixtures/woodland_pre_near.gdshader") if production_near else code
	source=mesh_for(arrays,full_indices,{.02:low_indices},material_for(baseline_code))
	original=mesh_for(arrays,full_indices,{},source.surface_get_material(0))
	low=mesh_for(arrays,low_indices,{},source.surface_get_material(0))
	var header := "\nuniform float trial_start=12.0;\nuniform float trial_end=18.0;\nuniform float trial_override=-1.0;\nuniform bool trial_hard=false;\nvarying flat float trial_tier;\nvarying flat float trial_blend;\nvarying flat float trial_visibility;\n"
	var vertex := "\ntrial_tier=UV2.x;\nfloat td=distance(MODEL_MATRIX[3].xyz,cover_eye);\ntrial_blend=trial_override>=0.0?trial_override:(trial_hard?step(14.0748,td):smoothstep(trial_start,trial_end,td));\ntrial_visibility=mix(1.0-trial_blend,trial_blend,trial_tier);\n"
	var shared := code.replace("void vertex() {",header+"void vertex() {"+vertex)
	# Collapse only the wholly inactive representation. At the fully detailed
	# endpoint the original vertex/shading arithmetic and geometry remain exact.
	shared=shared.replace("void fragment() {","void fragment() {")
	var stage := preload("res://tests/fixtures/grass_filtered.gd").extract_stage(shared,"vertex")
	shared=stage[0]+"\nvoid vertex(){"+stage[1]+"\nif(trial_visibility<=0.0)VERTEX=vec3(0.0);\n}\n"
	var dither := shared.replace("if(coverage<=threshold)discard;","if(coverage<=threshold)discard;\nif(trial_tier<0.5?threshold<trial_blend:threshold>=trial_blend)discard;")
	var alpha := shared.replace("void fragment() {","void fragment() {\nALPHA=trial_visibility;")
	var combined := full_indices.duplicate();combined.append_array(low_indices)
	# A batch may switch to low-only once even its closest point has cleared the
	# per-plant fade. No CPU instance updates; this is a lab-only shader prototype.
	trial=mesh_for(arrays,combined,{.03:low_indices},material_for(dither))
	trial_alpha=mesh_for(arrays,combined,{.03:low_indices},material_for(alpha))
	if production_near:
		var candidate:=Asset.build(2,true,true,false,true,true)
		trial=candidate.get_meta("surface_lod_near")
		var mat:ShaderMaterial=trial.surface_get_material(0)
		mat.shader=material_for(mat.shader.code).shader
		mat.set_shader_parameter("cover_clock",1000000.0)
		materials.append(mat)
		for target:ShaderMaterial in [source.surface_get_material(0),mat]:Asset.set_grass_detail(target,true)
	var tag_code := "shader_type spatial;render_mode unshaded,cull_disabled;varying flat float tier;void vertex(){tier=UV2.x;}void fragment(){ALBEDO=mix(vec3(0.9,0.1,0.1),vec3(0.1,0.2,0.9),tier);}"
	tagged=mesh_for(arrays,full_indices,{.02:low_indices},material_for(tag_code))
	batch=ClassDB.instantiate("NativeStaticBatch");world.add_child(batch)
	check(batch.configure_appearance_fade() and batch.configure_asset("ground_cover/2/v1",source),"source first two grass tiers configured")
	check(batch.configure_render_streaming(true,180,192,1600000,16,65536) and batch.configure_render_partitions(2,.05),"same 16 m draw partitions as production")
	batch.set_casts_shadows(production_near)
	var ids := PackedInt64Array();var transforms: Array[Transform3D]=[]
	for z in 12:
		for x in 12:
			var i:=z*12+x;ids.append(i+1)
			transforms.append(Transform3D(Basis(Vector3.UP,i*1.72),Vector3(-14.4+x*2.4,0,-14.4+z*2.4)))
	check(batch.upsert_transforms(ids,transforms),"144 fixed grass clumps; no streaming/spawning changes")
	batch.set_render_focus(Vector3(0,1.8,30))

func mode(name: String) -> void:
	active_case=name;batch.visible=name!="no_cover"
	for mesh: ArrayMesh in [trial,trial_alpha]:
		var mat: ShaderMaterial=mesh.surface_get_material(0);mat.set_shader_parameter("trial_override",-1.0);mat.set_shader_parameter("trial_hard",name=="per_plant_hard")
	trial.surface_get_material(0).set_shader_parameter("near_lod_metric",703.74)
	var selected:=source
	if name=="fixed_full":selected=original
	elif name=="fixed_low":selected=low
	elif name in ["per_plant_hard","dither6"]:selected=trial
	elif name=="alpha6":selected=trial_alpha
	elif name=="tagged":selected=tagged
	check(batch.configure_asset("ground_cover/2/v1",selected),name+" selected without population changes")

func pose(distance_m: float) -> void:
	camera.position=Vector3(0,1.8,12+distance_m);camera.look_at(Vector3(0,.15,0))
	for mat in materials:mat.set_shader_parameter("cover_eye",camera.position)

func capture(name: String,frame: int,distance_m: float) -> void:
	var image := root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	if name=="source" and frame==0:original_pixels=image.get_data()
	if name=="repeat":check(original_pixels==image.get_data(),"exact source frame repeats")
	var metric := root.size.x/(root.mesh_lod_threshold*camera.get_camera_projection().get_lod_multiplier())
	var selected := {"full":0,"low":0};var page_boxes: Array=[]
	for child in batch.get_children():
		if child is MultiMeshInstance3D and child.visible:
			var box: AABB=child.global_transform*child.multimesh.get_aabb()
			var d:=camera.position.distance_to(camera.position.clamp(box.position,box.end))
			selected["full" if d<.02*metric else "low"]+=1
			page_boxes.append({"min":str(box.position),"size":str(box.size),"distance":d})
	var crop := image.get_region(region);var raw:=crop.get_data()
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(raw)
	var meta: Dictionary={"case":name,"frame":frame,"distance_m":distance_m,"selection":selected,"rgb_sha256":hash.finish().hex_encode(),"page_boxes":page_boxes}
	var encoded:=crop.save_png_to_buffer();var json:=JSON.stringify(meta).to_utf8_buffer()
	packets.put_u32(json.size());packets.put_data(json);packets.put_u32(encoded.size());packets.put_data(encoded);rows.append(meta)
	if frame==13 and name in ["source","dither6","tagged"]:store_file(name+"_context.png",image.save_png_to_buffer())
	if packets.get_size()>9*1024*1024:check(false,"9 MiB packet cap");quit(1)

func run() -> void:
	var refine := false
	var fade_sweep:=false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="):output=arg.trim_prefix("--check-evidence-dir=")
		if arg=="--near-refine":refine=true
		if arg=="--production-near":production_near=true
		if arg=="--fade-sweep":fade_sweep=true
	if output.is_empty():push_error("Use admitted runner");quit(1);return
	cases=["no_cover","source","fixed_full","fixed_low","per_plant_hard","dither6","alpha6","tagged","repeat"]
	frame_count=24;start_distance=20;step_distance=.5
	if refine:
		cases=["no_cover","source","fixed_low","dither6","repeat"]
		frame_count=41;start_distance=14.8;step_distance=.025
	if production_near:cases=["no_cover","source","fixed_low","dither6","repeat"]
	if fade_sweep:frame_count=41;start_distance=14.2;step_distance=.06
	Engine.max_fps=120;setup();pose(start_distance);await settle(40)
	var population: int=batch.get_ids().size();var initial: Dictionary=batch.render_stats()
	for name in cases:
		mode(name);pose(start_distance);await settle(12)
		for frame in (1 if name=="repeat" else frame_count):
			var d:=start_distance-frame*step_distance;pose(d);await settle(2);capture(name,frame,d)
	# Compare both fully established endpoints at an identical view. Disabling
	# mesh LOD ensures the override controls reach every resident instance.
	pose(8.0)
	for child in batch.get_children():
		if child is MultiMeshInstance3D:child.lod_bias=1000000.0
	for endpoint in [0.0,1.0]:
		mode("fixed_full" if endpoint==0.0 else "fixed_low");await settle(10)
		var reference:=root.get_texture().get_image().get_data()
		for name in (["dither6"] if production_near else ["dither6","alpha6"]):
			mode(name);var mesh: ArrayMesh=trial_alpha if name=="alpha6" else trial
			mesh.surface_get_material(0).set_shader_parameter("trial_override",endpoint)
			if production_near:mesh.surface_get_material(0).set_shader_parameter("near_lod_metric",1000000.0 if endpoint==0.0 else 0.001)
			await settle(10)
			endpoints[name+"_"+str(endpoint)]=reference==root.get_texture().get_image().get_data()
	check(endpoints["dither6_"+str(0.0)] and endpoints["dither6_"+str(1.0)],"opaque transition fully near/low endpoint parity")
	for child in batch.get_children():
		if child is MultiMeshInstance3D:child.lod_bias=1.0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for group in 3:
		for name in ["source","dither6","dither6","source"]:
			mode(name);pose(14.0);await settle(60)
			var samples: Array=[]
			for frame in 90:
				await RenderingServer.frame_post_draw;samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			costs.append({"group":group,"case":name,"gpu_ms":samples})
	check(population==batch.get_ids().size() and initial.resident_batches==batch.render_stats().resident_batches,"resident population and page count preserved")
	store_file("transition.frames",packets.data_array)
	store_file("transition.json",JSON.stringify({"failures":failures,"cases":cases,"frame_count":frame_count,"rows":rows,"endpoints":endpoints,"cost":costs,"full_triangles":full_indices.size()/3,"low_triangles":low_indices.size()/3,"partition_width_m":16,"population":population,"mesh_lod_threshold":root.mesh_lod_threshold,"fov":camera.fov,"scope":"Unpromoted first grass LOD lab. Fixed population/lighting/time, no filtered quads, streaming, spawning or shadows. Lossless 1024x128 strips plus 1080p context. Local cost only, not full gameplay qualification."}).to_utf8_buffer())
	store_file("vegetation_near_transitions.gd",FileAccess.get_file_as_bytes("res://tests/vegetation_near_transitions.gd"))
	if not FileAccess.file_exists("res://tests/vegetation_near_transitions.gd.uid"):FileAccess.open("res://tests/vegetation_near_transitions.gd.uid",FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	if not FileAccess.file_exists("res://tests/fixtures/woodland_pre_near.gdshader.uid"):FileAccess.open("res://tests/fixtures/woodland_pre_near.gdshader.uid",FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	print("VEGETATION_NEAR_TRANSITIONS failures=",failures);quit(1 if failures else 0)

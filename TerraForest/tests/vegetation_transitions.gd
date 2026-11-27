# SPDX-License-Identifier: 0BSD
extends SceneTree
# Fixed resident objects separate representation changes from streaming/spawn.
const Asset = preload("res://addons/world_ecosystem/woodland_mesh.gd")
const Surface = preload("res://addons/world_ecosystem/filtered_grass.gd")
var output := ""
var failures := 0
var camera: Camera3D
var world: Node3D
var batch: Node3D
var source: ArrayMesh
var original: ArrayMesh
var low: ArrayMesh
var far: ArrayMesh
var materials: Array[ShaderMaterial] = []
var source_shaders: Array[Shader] = []
var packets := StreamPeerBuffer.new()
var rows: Array = []
var original_pixels := PackedByteArray()
var individuals: Array[MeshInstance3D]=[]
var bounds: AABB
var cases: PackedStringArray=["no_cover","source","no_page_optimization","no_distance_fade","fixed_low","fixed_far","original_opaque","tagged","repeat"]
var start_distance := 140.0
var step_distance := 2.0
var frame_count := 63

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1
	print("CHECK ","PASS " if ok else "FAIL ",label)
func settle(n := 3) -> void:
	for i in n: await RenderingServer.frame_post_draw
func store_file(name: String,bytes: PackedByteArray) -> void:
	if bytes.size()>10*1024*1024: check(false,"capture cap");quit(1);return
	FileAccess.open(output.path_join(name),FileAccess.WRITE).store_buffer(bytes)
func shader(code: String) -> Shader:
	var result := Shader.new();result.code=code;return result
func setup() -> void:
	world=Node3D.new();root.add_child(world)
	camera=Camera3D.new();world.add_child(camera);camera.current=true;camera.fov=75
	var environment := WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("859166")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("b8c3ce");environment.environment.ambient_light_energy=0.55
	world.add_child(environment)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-52,-27,0);sun.light_energy=1.3;world.add_child(sun)
	var ground := MeshInstance3D.new();var plane := PlaneMesh.new();plane.size=Vector2(500,500);ground.mesh=plane;ground.position.y=-0.10
	var tint := StandardMaterial3D.new();tint.albedo_color=Color("859166");tint.roughness=1;ground.material_override=tint;world.add_child(ground)
	source=Asset.build(0,true,true,false,true);original=Asset.build(0);low=Asset.build(0,false,true,true)
	source.surface_get_material(1).shader=preload("res://tests/fixtures/stone_pre_transition.gdshader")
	far=ArrayMesh.new();var arrays := source.surface_get_arrays(1);arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,2,1,0,3,2])
	far.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);far.surface_set_material(0,source.surface_get_material(1));far.custom_aabb=source.custom_aabb
	for mesh in [source,original,low]:
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as ShaderMaterial
			if not materials.has(mat):materials.append(mat);source_shaders.append(mat.shader)
	batch=ClassDB.instantiate("NativeStaticBatch");world.add_child(batch)
	check(batch.configure_asset("ground_cover/0/v1",source),"source stone asset configured")
	check(batch.configure_render_streaming(true,2048,16,1048576,16,1048576),"all fixed pages resident")
	batch.set_casts_shadows(false)
	var ids := PackedInt64Array();var transforms: Array[Transform3D]=[]
	for z in 4:
		for x in 4:
			var i := z*4+x;ids.append(i+1)
			transforms.append(Transform3D(Basis(Vector3.UP,i*1.72).scaled(Vector3.ONE*(0.7+0.1*(i%7))),Vector3(x*3.0+0.6,0,z*3.0+0.6)))
	check(batch.upsert_transforms(ids,transforms),"16 deterministic resident stones")
	for transform in transforms:
		var view := MeshInstance3D.new();view.mesh=far;view.transform=transform
		view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;view.visible=false
		world.add_child(view);individuals.append(view)
	batch.set_render_focus(Vector3(5,2,70))

func mode(name: String) -> void:
	batch.visible=name not in ["no_cover","individual_front"]
	for view in individuals:view.visible=name=="individual_front"
	for i in materials.size():
		materials[i].shader=source_shaders[i]
		materials[i].set_shader_parameter("cover_clock",1000000.0)
		materials[i].set_shader_parameter("distance_fade_start",100.0 if name!="no_distance_fade" else 10000.0)
		materials[i].set_shader_parameter("distance_fade_end",124.0 if name!="no_distance_fade" else 11000.0)
	var mesh: ArrayMesh=low if name=="fixed_low" else (far if name in ["fixed_far","hemisphere_far","no_depth_far","instance_depth_far","instance_all_far","instance_front_far","individual_front"] else (original if name=="original_opaque" else source))
	check(batch.configure_asset("ground_cover/0/v1",mesh),name+" asset selected")
	if mesh==source:check(Surface.configure_batch(batch,source,name!="no_page_optimization"),name+" surface mode")
	if name in ["hemisphere_far","hemisphere_source","individual_front"]:
		var mat := source.surface_get_material(1) as ShaderMaterial
		mat.shader=shader(mat.shader.code.replace("face_axis=normalize(cross(row_x,row_y));","face_axis=normalize(cross(row_x,row_y));\n    if((MODELVIEW_MATRIX*vec4(face_axis*RADII,0.0)).z<0.0)face_axis=-face_axis;"))
	if name in ["instance_depth_far","instance_all_far","instance_all_source","instance_front_far","instance_front_source"]:
		var mat := source.surface_get_material(1) as ShaderMaterial
		var code := mat.shader.code
		if name=="instance_depth_far":
			code=code.replace("void vertex(){","varying flat vec3 instance_depth;\nvoid vertex(){\n    instance_depth=vec3(MODELVIEW_MATRIX[0].z,MODELVIEW_MATRIX[1].z,MODELVIEW_MATRIX[2].z);")
			code=code.replace("VIEW_MATRIX*MODEL_MATRIX*vec4(surface*RADII,1.0)","vec4(VERTEX.xy,VERTEX.z+dot(instance_depth,surface*RADII),1.0)")
		else:
			code=code.replace("varying flat vec2 center_px;", "varying flat mat3 instance_basis;")
			code=code.replace("void vertex(){", "void vertex(){\n    instance_basis=mat3(MODELVIEW_MATRIX);")
			code=code.replace("center_px=center.xy/center.w*VIEWPORT_SIZE*0.5;", "vec2 center_px=center.xy/center.w*VIEWPORT_SIZE*0.5;")
			code=code.replace("point_px=center_px+(UV*2.0-1.0)*extent;", "point_px=(UV*2.0-1.0)*extent;").replace("vec4(point_px/(VIEWPORT_SIZE", "vec4((center_px+point_px)/(VIEWPORT_SIZE")
			code=code.replace("vec2 delta=point_px-center_px;", "vec2 delta=point_px;")
			code=code.replace("VIEW_MATRIX*MODEL_MATRIX*vec4(surface*RADII,1.0)","vec4(instance_basis*(surface*RADII)+VERTEX,1.0)")
			code=code.replace("mat3(VIEW_MATRIX)*MODEL_NORMAL_MATRIX", "instance_basis").replace("mat3(VIEW_MATRIX*MODEL_MATRIX)", "instance_basis")
		if name in ["instance_front_far","instance_front_source"]:
			code=code.replace("face_axis=normalize(cross(row_x,row_y));","face_axis=normalize(cross(row_x,row_y));\n    if((MODELVIEW_MATRIX*vec4(face_axis*RADII,0.0)).z<0.0)face_axis=-face_axis;")
		mat.shader=shader(code)
	if name in ["production","fade32"]:
		source.surface_get_material(1).shader=preload("res://addons/world_ecosystem/filtered_stone.gdshader")
		if name=="fade32":
			for mat in materials:mat.set_shader_parameter("distance_fade_start",92.0)
	if name=="no_depth_far":
		var mat := source.surface_get_material(1) as ShaderMaterial
		mat.shader=shader(mat.shader.code.replace("DEPTH=clip.z/clip.w;",""))
	if name=="tagged":
		var near_mat := source.surface_get_material(0) as ShaderMaterial
		near_mat.shader=shader("shader_type spatial;render_mode unshaded,cull_disabled;void fragment(){ALBEDO=vec3(1.0,0.0,0.0);}")
		var far_mat := source.surface_get_material(1) as ShaderMaterial
		var code := far_mat.shader.code.replace("diffuse_burley","unshaded")
		code=code.insert(code.rfind("}"),"ALBEDO=vec3(0.0,0.0,1.0);\n")
		far_mat.shader=shader(code)

func pose(distance_m: float) -> void:
	camera.position=Vector3(5.1,1.8,9.6+distance_m);camera.look_at(Vector3(5.1,0.0,5.1))
	for mat in materials:mat.set_shader_parameter("cover_eye",camera.position)
	batch.update_surface_lod()

func capture(name: String,frame: int,distance_m: float) -> void:
	var image := root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	if name=="source" and frame==0:original_pixels=image.get_data()
	if name=="repeat":check(original_pixels==image.get_data(),"exact source frame repeats after all interventions")
	var selection := {"near":0,"far":0,"combined":0,"other":0}
	for child in batch.get_children():
		if child is MultiMeshInstance3D and child.visible:
			var mesh: Mesh=child.multimesh.mesh
			selection["combined" if mesh==source else ("near" if mesh==source.get_meta("surface_lod_near") else ("far" if mesh==source.get_meta("surface_lod_far") else "other"))]+=1
	var cropped := image.get_region(Rect2i(448,480,1024,128));var raw := cropped.get_data()
	var context := HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(raw)
	var metadata := {"case":name,"frame":frame,"distance_m":distance_m,"selection":selection,"rgb_sha256":context.finish().hex_encode(),"stats":batch.render_stats()}
	var encoded := cropped.save_png_to_buffer();var json := JSON.stringify(metadata).to_utf8_buffer()
	packets.put_u32(json.size());packets.put_data(json);packets.put_u32(encoded.size());packets.put_data(encoded)
	rows.append(metadata)
	if name=="source" and frame==34:store_file("transition_context.png",image.save_png_to_buffer())
	if packets.get_size()>9*1024*1024:check(false,"bounded motion packets");quit(1)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="):output=arg.trim_prefix("--check-evidence-dir=")
		if arg.begins_with("--transition-cases="):cases=arg.trim_prefix("--transition-cases=").split(",")
		if arg.begins_with("--transition-start="):start_distance=float(arg.trim_prefix("--transition-start="))
		if arg.begins_with("--transition-step="):step_distance=float(arg.trim_prefix("--transition-step="))
		if arg.begins_with("--transition-frames="):frame_count=int(arg.trim_prefix("--transition-frames="))
	if output.is_empty():push_error("Use admitted runner");quit(1);return
	if frame_count>96 or frame_count<1:push_error("Unbounded plan");quit(1);return
	Engine.max_fps=120;setup();pose(start_distance);await settle(30)
	var initial: Dictionary=batch.render_stats()
	for name in cases:
		mode(name);pose(start_distance);await settle(16)
		for frame in (1 if name=="repeat" else frame_count):
			var distance_m := start_distance-frame*step_distance
			pose(distance_m);await settle(2);capture(name,frame,distance_m)
	check(initial.resident_batches==batch.render_stats().resident_batches,"resident page count unchanged")
	store_file("transition.frames",packets.data_array)
	store_file("transition.json",JSON.stringify({"failures":failures,"cases":cases,"frame_count":frame_count,"start_distance":start_distance,"step_distance":step_distance,"rows":rows,"mesh_lod_threshold":root.mesh_lod_threshold,"fov":camera.fov,"scope":"Fixed 16 resident stones; 1080p renderer, lossless 1024x128 field strip. Streaming/spawn absent, shadow casting disabled in all cases. Not normal gameplay or cost qualification."}).to_utf8_buffer())
	store_file("vegetation_transitions.gd",FileAccess.get_file_as_bytes("res://tests/vegetation_transitions.gd"))
	if not FileAccess.file_exists("res://tests/vegetation_transitions.gd.uid"):FileAccess.open("res://tests/vegetation_transitions.gd.uid",FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	if not FileAccess.file_exists("res://tests/fixtures/stone_pre_transition.gdshader.uid"):FileAccess.open("res://tests/fixtures/stone_pre_transition.gdshader.uid",FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	print("VEGETATION_TRANSITIONS failures=",failures);quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends "res://tests/vegetation_transitions.gd"
# Fixed resident pages: distinguish each remaining geometry switch from streaming.
var seamless_suite:=false
var shadow_suite:=false
var smoke:=false
var lab_sun:DirectionalLight3D
var scenarios:Array=[]
var active:Dictionary={}
var candidate:ArrayMesh
var opaque_suite:=false
var outer_suite:=false
var endpoint_checks:Dictionary={}
var held_before:ArrayMesh
var held_after:ArrayMesh
var all_rows:Array=[]
var original_frame:PackedByteArray
var total_bytes:=0

func freeze(mesh:ArrayMesh) -> void:
	for surface in mesh.get_surface_count():
		var mat:ShaderMaterial=mesh.surface_get_material(surface)
		if materials.has(mat):continue
		var code:=mat.shader.code.replace("shader_type spatial;","shader_type spatial;\nuniform float comparison_time=0.0;").replace("TIME","comparison_time")
		mat.shader=shader(code);mat.set_shader_parameter("cover_clock",1000000.0)
		mat.set_shader_parameter("distance_fade_start",10000.0);mat.set_shader_parameter("distance_fade_end",11000.0)
		materials.append(mat)

func held(mesh:ArrayMesh,error:float) -> ArrayMesh:
	var result:=ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays:=mesh.surface_get_arrays(surface)
		var raw:Dictionary=RenderingServer.mesh_get_surface(mesh.get_rid(),surface)
		for level:Dictionary in raw.get("lods",[]):
			if float(level.edge_length)>error:continue
			var bytes:PackedByteArray=level.index_data
			var stride:=2 if arrays[Mesh.ARRAY_VERTEX].size()<65536 else 4
			var indices:=PackedInt32Array();indices.resize(bytes.size()/stride)
			for index in indices.size():indices[index]=bytes.decode_u16(index*stride) if stride==2 else bytes.decode_u32(index*stride)
			arrays[Mesh.ARRAY_INDEX]=indices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},mesh.surface_get_format(surface))
		result.surface_set_material(surface,mesh.surface_get_material(surface))
	result.custom_aabb=mesh.custom_aabb
	return result

func setup() -> void:
	world=Node3D.new();root.add_child(world)
	camera=Camera3D.new();world.add_child(camera);camera.current=true;camera.fov=75
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("859166");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("b8c3ce");env.environment.ambient_light_energy=.55;world.add_child(env)
	var sun:=DirectionalLight3D.new();lab_sun=sun;sun.rotation_degrees=Vector3(-52,-27,0);sun.light_energy=1.3;world.add_child(sun)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(300,300);ground.mesh=plane;ground.position.y=-.04
	var tint:=StandardMaterial3D.new();tint.albedo_color=Color("859166");tint.roughness=1;ground.material_override=tint;world.add_child(ground)

func prepare(row:Dictionary) -> void:
	active=row;materials.clear()
	if batch!=null:batch.queue_free();await process_frame
	source=Asset.build(row.species,true,true,false,row.species in [0,1,2,3,4,5],true if seamless_suite else row.species==2)
	if row.species==2:Asset.set_grass_detail(source.surface_get_material(0),true)
	freeze(source)
	candidate=Asset.build(row.species,true,true,false,row.species in [0,1,2,3,4,5],true,seamless_suite)
	if row.species==2:Asset.set_grass_detail(candidate.surface_get_material(0),true)
	freeze(candidate)
	if shadow_suite:
		source=Asset.build(row.species,false,true,false,false,false,false)
		candidate=Asset.build(row.species,false,true,false,false,false,true)
		freeze(source);freeze(candidate)
	lab_sun.shadow_enabled=shadow_suite
	lab_sun.directional_shadow_max_distance=180.0
	held_before=held(source,row.error-.0001);held_after=held(source,row.error+.0001)
	batch=ClassDB.instantiate("NativeStaticBatch");world.add_child(batch)
	check(batch.configure_appearance_fade() and batch.configure_asset("ground_cover/%d/v1"%row.species,source),"audit asset")
	check(batch.configure_render_streaming(true,180,192,1600000,16,65536) and batch.configure_render_partitions(2,.05),"fixed partition residency")
	batch.set_casts_shadows(shadow_suite)
	if shadow_suite:batch.set_shadow_distance(active.radius)
	var ids:=PackedInt64Array();var transforms:Array[Transform3D]=[]
	for z in 12:
		for x in 12:
			var i:=z*12+x;ids.append(i+1)
			transforms.append(Transform3D(Basis(Vector3.UP,i*1.72),Vector3(-14.4+x*2.4,0,-14.4+z*2.4)))
	check(batch.upsert_transforms(ids,transforms),"fixed population")
	batch.set_render_focus(Vector3(0,1.8,30));await settle(24)

func mode(name:String) -> void:
	batch.visible=name!="no_cover"
	var mesh:=candidate if name in ["candidate","candidate_no_cut"] else (held_before if name=="held_before" else (held_after if name=="held_after" else source))
	check(batch.configure_asset("ground_cover/%d/v1"%active.species,mesh),"select "+name)
	if shadow_suite:
		batch.set_shadow_distance(0.0 if name in ["held_before","candidate_no_cut"] else active.radius)
		batch.set_casts_shadows(name not in ["no_cover","held_after"])
	if mesh.has_meta("surface_lod_near"):
		check(Surface.configure_batch(batch,mesh,name!="no_optimization"),"page mode "+name)

func pose(distance_m:float) -> void:
	camera.transform=Transform3D(Basis.looking_at(Vector3(0,.15,0)-Vector3(0,1.8,12+distance_m)),Vector3(0,1.8,12+distance_m))
	for mat in materials:mat.set_shader_parameter("cover_eye",camera.position)
	batch.set_render_focus(camera.position);batch.update_surface_lod()

func capture(name:String,frame:int,distance_m:float) -> void:
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var crop:=image.get_region(Rect2i(448,480,1024,128));var raw:=crop.get_data()
	if name=="source" and frame==0:original_frame=raw
	if name=="repeat":check(original_frame==raw,"exact repeated source "+active.name)
	var metric:float=root.size.x/(root.mesh_lod_threshold*camera.get_camera_projection().get_lod_multiplier())
	var selected:Dictionary={};var pages:Array=[]
	for child in batch.get_children():
		if not child is MultiMeshInstance3D or not child.visible:continue
		var box:AABB=child.global_transform*child.multimesh.get_aabb()
		var d:=camera.position.distance_to(camera.position.clamp(box.position,box.end))
		var tier:="before" if d<active.error*metric else "after"
		selected[tier]=int(selected.get(tier,0))+1
		pages.append({"distance":d,"tier":tier,"mesh":child.multimesh.mesh.get_surface_count(),"id":child.get_instance_id(),"casts_shadows":child.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF})
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(raw)
	var meta:Dictionary={"scenario":active.name,"case":name,"frame":frame,"distance_m":distance_m,"selection":selected,"rgb_sha256":hash.finish().hex_encode(),"pages":pages}
	var encoded:=crop.save_png_to_buffer();var json:=JSON.stringify(meta).to_utf8_buffer()
	packets.put_u32(json.size());packets.put_data(json);packets.put_u32(encoded.size());packets.put_data(encoded);all_rows.append(meta)

	if packets.get_size()>=(512*1024 if smoke else 9*1024*1024):push_error("Packet budget exhausted");quit(1)
	if not smoke and name=="source" and frame==(4 if outer_suite else 6):store_file(active.name+".png",image.save_png_to_buffer())

func store_file(name:String,bytes:PackedByteArray) -> void:
	total_bytes+=bytes.size()
	if total_bytes>(768*1024 if smoke else 11*1024*1024):push_error("Output budget");quit(1);return
	FileAccess.open(output.path_join(name),FileAccess.WRITE).store_buffer(bytes)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="):output=arg.trim_prefix("--check-evidence-dir=")
		if arg=="--opaque-suite":opaque_suite=true
		if arg=="--outer-opaque-suite":outer_suite=true
		if arg=="--shadow-suite":shadow_suite=true
		if arg=="--smoke":smoke=true
	if output.is_empty():quit(1);return
	setup();Engine.max_fps=120
	scenarios=[{"name":"grass_filtered","species":2,"error":.045},{"name":"grass_horizon","species":2,"error":.10},{"name":"fern_near","species":1,"error":.025},{"name":"fern_filtered","species":1,"error":.04},{"name":"bush_near","species":6,"error":.025}]
	if opaque_suite:scenarios=[{"name":"fern_near","species":1,"error":.025},{"name":"bush_near","species":6,"error":.025},{"name":"flower_near","species":3,"error":.02},{"name":"stone_near","species":0,"error":.03}]
	if outer_suite:scenarios=[{"name":"twig_near","species":7,"error":.02},{"name":"woody_near","species":8,"error":.025},{"name":"bush_outer","species":6,"error":.08},{"name":"twig_outer","species":7,"error":.08},{"name":"woody_outer","species":8,"error":.08}]
	if seamless_suite:scenarios=[{"name":"grass_filtered","species":2,"error":.045},{"name":"grass_horizon","species":2,"error":.10},{"name":"fern_filtered","species":1,"error":.04},{"name":"flower_filtered","species":3,"error":.04},{"name":"stone_filtered","species":0,"error":.045}]
	if shadow_suite:scenarios=[{"name":"grass_shadow","species":2,"error":.02,"radius":24.0},{"name":"fern_shadow","species":1,"error":.025,"radius":48.0}]
	if smoke:scenarios.resize(1)
	for scenario in scenarios:
		await prepare(scenario)
		var metric:float=root.size.x/(root.mesh_lod_threshold*camera.get_camera_projection().get_lod_multiplier())
		for material in materials:material.set_shader_parameter("near_lod_metric",metric)
		var start:float=(scenario.radius+4.0-12.0 if shadow_suite else scenario.error*metric)+(2.4 if seamless_suite else 1.6)
		var cases:Array=["no_cover","source","held_before","held_after","no_optimization","candidate","repeat"]
		if shadow_suite:cases.insert(6,"candidate_no_cut")
		for name in cases:
			mode(name);pose(start);await settle(12)
			for frame in (1 if name=="repeat" or smoke else (9 if outer_suite else 13)):
				var d:=start-frame*(1.0 if seamless_suite else (.30 if outer_suite else .20));pose(d);await settle(2);capture(name,frame,d)
		check(batch.get_ids().size()==144,"resident population unchanged")
		# Exact nearby endpoint, after all measurement; original shade and geometry.
		root.mesh_lod_threshold=0.0;pose(8.0)
		if shadow_suite:
			var near_poses:Array[Transform3D]=[]
			for index in 144:near_poses.append(Transform3D(Basis(Vector3.UP,index*1.72),Vector3(-2.75+(index%12)*.5,0,-2.75+(index/12)*.5)))
			check(batch.upsert_transforms(batch.get_ids(),near_poses),"near shadow parity layout entirely inside unchanged radius")
			pose(0.0)
		for material in materials:material.set_shader_parameter("near_lod_metric",1000000.0)
		mode("source");await settle(12)
		var nearby:=root.get_texture().get_image().get_data()
		mode("candidate")
		for surface in candidate.get_surface_count():candidate.surface_get_material(surface).set_shader_parameter("near_lod_metric",1000000.0)
		await settle(12)
		endpoint_checks[scenario.name]=nearby==root.get_texture().get_image().get_data()
		check(endpoint_checks[scenario.name],"exact nearby pixels "+scenario.name)
		root.mesh_lod_threshold=1.0
	store_file("transition.frames",packets.data_array)
	store_file("handoffs.json",JSON.stringify({"failures":failures,"scenarios":scenarios,"nearby_exact":endpoint_checks,"rows":all_rows,"seamless_suite":seamless_suite,"shadow_suite":shadow_suite,"smoke":smoke,"scope":("Fixed 144 plants, 16m partitions, frozen wind/time and opaque color geometry; native cutoff, all-caster, no-caster and candidate-without-cutoff shadow controls." if shadow_suite else "Fixed 144 plants, 16m draw partitions, no shadows/spawning/streaming changes, frozen wind/time; source/held-before/held-after/page-optimization controls.")}).to_utf8_buffer())
	store_file("vegetation_handoffs.gd",FileAccess.get_file_as_bytes("res://tests/vegetation_handoffs.gd"))
	if seamless_suite:
		store_file("vegetation_final_handoffs.gd",FileAccess.get_file_as_bytes("res://tests/vegetation_final_handoffs.gd"))
		for path in ["res://tests/vegetation_final_handoffs.gd","res://addons/world_ecosystem/representation_fade.gd"]:
			if not FileAccess.file_exists(path+".uid"):FileAccess.open(path+".uid",FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	if not FileAccess.file_exists("res://tests/vegetation_handoffs.gd.uid"):FileAccess.open("res://tests/vegetation_handoffs.gd.uid",FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	print("VEGETATION_HANDOFFS failures=",failures);quit(1 if failures else 0)

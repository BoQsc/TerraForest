# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:run.call_deferred()
func capture(path: String) -> void:
	for i in 8:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	Engine.max_fps=60
	DirAccess.make_dir_recursive_absolute("res://reports/ground_mesh")
	var old: Array[Mesh]=[];var meshes: Array[Mesh]=[]
	for species in 3:
		old.append(load("res://tests/fixtures/ground_cover_mesh_v1.gd").build(species))
		var mesh: ArrayMesh=load("res://addons/world_ecosystem/ground_mesh.gd").build(species);meshes.append(mesh)
		var bounds:=AABB(Vector3(-0.4,-0.2 if species==0 else 0,-0.4),Vector3(0.8,0.4 if species==0 else 0.75,0.8))
		var arrays:=mesh.surface_get_arrays(0);var valid:=true
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			var point: Vector3=arrays[Mesh.ARRAY_VERTEX][i];var normal: Vector3=arrays[Mesh.ARRAY_NORMAL][i]
			valid=valid and point.is_finite() and bounds.has_point(point) and normal.is_finite() and normal.length_squared()>0.99
		check(valid,"species %d has finite geometry/normals inside existing interaction bounds"%species)
		check(mesh.get_faces().size()/3==[54,28,15][species],"species %d stays within declared triangle budget"%species)
		check(mesh.surface_get_material(0).transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"species %d uses opaque material"%species)
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true;camera.position=Vector3(1.7,1.3,3.3);camera.look_at(Vector3(0,0.2,0));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.7
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("30373d");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=0.4;root.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-30,0);root.add_child(light)
	var gallery: Array[MeshInstance3D]=[]
	for row in 2:
		for species in 3:
			var item:=MeshInstance3D.new();item.mesh=old[species] if row==0 else meshes[species];item.position=Vector3(species-1,0,(row-0.5)*1.1);root.add_child(item);gallery.append(item)
	await capture("res://reports/ground_mesh/gallery.png")
	for item in gallery:item.free()
	# Isolated visible patch: 3072 clumps, identical transforms in both versions.
	var batches: Array[MultiMeshInstance3D]=[]
	for species in 3:
		var batch:=MultiMeshInstance3D.new();var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=old[species];multi.instance_count=[308,614,2150][species]
		for i in multi.instance_count:
			var index: int=i+[0,308,922][species]
			multi.set_instance_transform(i,Transform3D(Basis(Vector3.UP,index*2.399963),Vector3((index%56)*0.33-9,0,(index/56)*0.33-9)))
		batch.multimesh=multi;batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(batch);batches.append(batch)
	camera.position=Vector3(0,13,17);camera.look_at(Vector3.ZERO);camera.size=25
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var phases: Array=[]
	for version in [0,1,1,0]:
		for species in 3:batches[species].multimesh.mesh=old[species] if version==0 else meshes[species]
		for frame in 30:await RenderingServer.frame_post_draw
		var rows: Array=[];var previous:=Time.get_ticks_usec()
		for frame in 120:
			await RenderingServer.frame_post_draw
			var now:=Time.get_ticks_usec()
			rows.append({"frame_ms":(now-previous)/1000.0,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
			previous=now
		var gpu: Array=[];var frames: Array=[]
		for row in rows:gpu.append(row.gpu_ms);frames.append(row.frame_ms)
		gpu.sort();frames.sort()
		check(gpu[113]>0,"GPU timer available")
		check(frames[113]<=18.5,"version %d frame p95 %.3f ms <=18.5"%[version,frames[113]])
		phases.append({"version":version,"gpu_p95_ms":gpu[113],"frame_p95_ms":frames[113],"rows":rows})
		if version==1 and phases.size()==2:await capture("res://reports/ground_mesh/patch.png")
	var delta: float=maxf(phases[1].gpu_p95_ms,phases[2].gpu_p95_ms)-minf(phases[0].gpu_p95_ms,phases[3].gpu_p95_ms)
	check(delta<=0.5,"conservative new-vs-baseline GPU p95 difference %.3f ms <=0.5 ms"%delta)
	check(root.size==Vector2i(1920,1080) and DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN],"fullscreen1080p")
	var report:={"checks":checks,"failures":failures,"phases":phases,"gpu_delta_ms":delta,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"population":[308,614,2150],"triangles_per_mesh":[54,28,15],"scope":"Isolated same-transform 3072-instance ABBA rendering comparison, no terrain/forest/simulation/native streaming. Fixed camera, no shadows in either patch. Does not close mixed-world timing or prove density/LOD/endurance. Gallery back row is previous assets, front row is new assets."}
	var file:=FileAccess.open("res://reports/ground_mesh/result.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	for batch in batches:batch.free()
	camera.free();env.free();light.free();await process_frame;quit(1 if failures else 0)

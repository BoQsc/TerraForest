extends SceneTree

const Asset=preload("res://addons/world_ecosystem/woodland_mesh.gd")
var failures:=0
var output:="res://reports/vegetation_lod_visual"
var camera:Camera3D
var rows:=[]

func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)

func settle(frames:int=30)->void:
	for frame in frames:await RenderingServer.frame_post_draw

func primitives()->int:
	return RenderingServer.viewport_get_render_info(root.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)

func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lod-output="):output=argument.trim_prefix("--lod-output=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1920,1080);root.mesh_lod_threshold=1.0
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("88a8ba")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.55
	root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-43,-27,0)
	root.add_child(sun)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(1800,1800)
	var material:=StandardMaterial3D.new();material.albedo_color=Color("58684a");plane.material=material
	ground.mesh=plane;ground.position.y=-.2;root.add_child(ground)
	camera=Camera3D.new();camera.far=1800;camera.fov=75;root.add_child(camera);camera.current=true
	var batches:=[];var meshes:=[[],[]]
	for species in [1,6,7,8]:
		for enabled in [false,true]:
			var mesh:=Asset.build(species,true,enabled)
			var shader:ShaderMaterial=mesh.surface_get_material(0)
			shader.set_shader_parameter("wind_strength",0.0)
			shader.set_shader_parameter("cover_eye",Vector3.ZERO)
			shader.set_shader_parameter("fade_start",1000.0);shader.set_shader_parameter("fade_end",1200.0)
			meshes[int(enabled)].append(mesh)
		var batch:=MultiMeshInstance3D.new();batch.multimesh=MultiMesh.new()
		batch.multimesh.transform_format=MultiMesh.TRANSFORM_3D
		batch.multimesh.mesh=meshes[0][-1];batch.multimesh.instance_count=800
		for index in 800:
			var pose:=Transform3D(Basis(Vector3.UP,index*2.399963),Vector3((index%40)*.7-14+(batches.size()%2)*30,0,(index/40)*.7+(batches.size()/2)*22))
			batch.multimesh.set_instance_transform(index,pose)
		root.add_child(batch);batches.append(batch)
	for distance in [4,35,80]:
		camera.position=Vector3(14,4+distance*.08,-distance);camera.look_at(Vector3(14,.4,14))
		var counts:=[]
		for enabled in [false,true]:
			for index in batches.size():batches[index].multimesh.mesh=meshes[int(enabled)][index]
			await settle()
			counts.append(primitives())
			root.get_texture().get_image().save_png(output.path_join("understory_%d_%s.png"%[distance,"extended" if enabled else "baseline"]))
		check(counts[1]<=counts[0],"actual draw never increases at %dm"%distance)
		rows.append({"distance":distance,"baseline_triangles":counts[0],"extended_triangles":counts[1]})
	check(rows[-1].extended_triangles<rows[-1].baseline_triangles*.8,"distant understory actually uses cheaper indices")
	var sweeps:=[]
	for enabled in [false,true]:
		for index in batches.size():batches[index].multimesh.mesh=meshes[int(enabled)][index]
		await settle()
		var intervals:Array[float]=[];var previous:=Time.get_ticks_usec()
		for frame in 180:
			camera.position=Vector3(14,7,-95).lerp(Vector3(14,2,-4),float(frame)/179);camera.look_at(Vector3(14,.4,14))
			await RenderingServer.frame_post_draw
			var now:=Time.get_ticks_usec();intervals.append((now-previous)/1000.0);previous=now
		intervals.sort();sweeps.append({"extended":enabled,"median_ms":intervals[90],"p95_ms":intervals[171],"max_ms":intervals[-1]})
	for batch:MultiMeshInstance3D in batches:batch.free()
	var forest=preload("res://addons/vegetation/vegetation_world.gd").new()
	forest.camera=camera;forest.wind_strength=0;root.add_child(forest)
	check(forest.initialize()==OK,"existing native forest renderer initializes")
	var ids:=PackedInt64Array();var poses:Array[Transform3D]=[]
	for row in 32:
		for column in 32:
			var index:=row*32+column
			ids.append(index+1)
			poses.append(Transform3D(Basis(Vector3.UP,index*2.399963).scaled(Vector3.ONE*(.8+.3*absf(sin(index)))),Vector3(column*20-320,0,row*20)))
	check(forest.upsert_chunk("test/forest",ids,poses),"same 1024 trees in both range comparisons")
	camera.position=Vector3(0,36,-50);camera.look_at(Vector3(0,8,450))
	for distance in [448,576]:
		forest.draw_distance=distance;forest.renderer.far_distance=distance
		await settle(60)
		root.get_texture().get_image().save_png(output.path_join("forest_%d.png"%distance))
	check(forest.renderer.roots.size()==1024,"distance changes never replace tree identities")
	check(forest.remove_root(513) and not forest.renderer.roots.has(513),"native removal still removes exact distant tree")
	forest.free();camera.free();ground.free();sun.free();environment.free()
	await process_frame
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"views":rows,"sweeps":sweeps,"scope":"1920x1080 nonactivating offscreen fixture, 3200 understory plants and 1024 tree range comparison; capped wall timings, not isolated GPU speedup or populated-world qualification."},"  "))
	print("VEGETATION_LOD_VISUAL failures=",failures)
	quit(1 if failures else 0)

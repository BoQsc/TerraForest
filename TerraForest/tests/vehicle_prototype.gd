# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
var output:="res://reports/vehicle_prototype"
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func quad(material:Material,second_uv:bool=false,threshold:float=.25)->ArrayMesh:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(0,0,0),Vector3(1,0,0),Vector3(1,1,0),Vector3(0,1,0)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD])
	arrays[Mesh.ARRAY_TANGENT]=PackedFloat32Array([1,0,0,-1,1,0,0,-1,1,0,0,-1,1,0,0,-1])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)])
	arrays[Mesh.ARRAY_COLOR]=PackedColorArray([Color.RED,Color.GREEN,Color.BLUE,Color.WHITE])
	if second_uv:arrays[Mesh.ARRAY_TEX_UV2]=arrays[Mesh.ARRAY_TEX_UV]
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{threshold:PackedInt32Array([0,1,2])});mesh.surface_set_material(0,material);return mesh
func pixels(first:Image,second:Image)->Dictionary:
	first.convert(Image.FORMAT_RGB8);second.convert(Image.FORMAT_RGB8)
	var before:=first.get_data();var after:=second.get_data();var total:=0.0;var changed:=0
	for pixel in before.size()/3:
		var difference:=0
		for channel in 3:difference=maxi(difference,absi(before[pixel*3+channel]-after[pixel*3+channel]));total+=absi(before[pixel*3+channel]-after[pixel*3+channel])
		if difference>3:changed+=1
	return {"mean_channel_error":total/before.size(),"changed_pixels_over_3":changed,"pixels":before.size()/3}
func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--view-output="):output=argument.trim_prefix("--view-output=")
	DirAccess.make_dir_recursive_absolute(output)
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var baker:RefCounted=ClassDB.instantiate("NativeVehiclePrototype")
	var material:=StandardMaterial3D.new();var mesh:=quad(material)
	var transform:=Transform3D(Basis.from_euler(Vector3(.2,.3,.4)).scaled(Vector3.ONE*2),Vector3(2,3,4))
	var parts:Array=[{"mesh":mesh,"transform":Transform3D.IDENTITY},{"mesh":quad(material,false,.5),"transform":transform}]
	check(not baker.bake([]).ok and not baker.bake([{}]).ok and not baker.bake([{},{}]).ok,"invalid prototype shapes reject safely")
	var baked:Dictionary=baker.bake(parts)
	check(baked.ok and baked.parts.size()==1,"same-material parts consolidate")
	if not baked.ok:finish({"bake":baked});return
	var arrays:Array=baked.parts[0].mesh.surface_get_arrays(0);var source:Array=mesh.surface_get_arrays(0);var parity:=true
	var geometry_errors:Dictionary={"position":0.0,"normal":0.0,"tangent":0.0,"uv":0.0,"color":0.0}
	for vertex in 4:
		geometry_errors.position=maxf(geometry_errors.position,arrays[Mesh.ARRAY_VERTEX][vertex+4].distance_to(transform*source[Mesh.ARRAY_VERTEX][vertex]))
		geometry_errors.normal=maxf(geometry_errors.normal,arrays[Mesh.ARRAY_NORMAL][vertex+4].distance_to((transform.basis.inverse().transposed()*source[Mesh.ARRAY_NORMAL][vertex]).normalized()))
		var tangent:=Vector3(source[Mesh.ARRAY_TANGENT][vertex*4],source[Mesh.ARRAY_TANGENT][vertex*4+1],source[Mesh.ARRAY_TANGENT][vertex*4+2])
		var result_tangent:=Vector3(arrays[Mesh.ARRAY_TANGENT][(vertex+4)*4],arrays[Mesh.ARRAY_TANGENT][(vertex+4)*4+1],arrays[Mesh.ARRAY_TANGENT][(vertex+4)*4+2])
		geometry_errors.tangent=maxf(geometry_errors.tangent,result_tangent.distance_to((transform.basis*tangent).normalized()))
		parity=parity and geometry_errors.tangent<.0001 and arrays[Mesh.ARRAY_TANGENT][(vertex+4)*4+3]==source[Mesh.ARRAY_TANGENT][vertex*4+3]
		geometry_errors.uv=maxf(geometry_errors.uv,arrays[Mesh.ARRAY_TEX_UV][vertex+4].distance_to(source[Mesh.ARRAY_TEX_UV][vertex]))
		geometry_errors.color=maxf(geometry_errors.color,Vector4(arrays[Mesh.ARRAY_COLOR][vertex+4].r,arrays[Mesh.ARRAY_COLOR][vertex+4].g,arrays[Mesh.ARRAY_COLOR][vertex+4].b,arrays[Mesh.ARRAY_COLOR][vertex+4].a).distance_to(Vector4(source[Mesh.ARRAY_COLOR][vertex].r,source[Mesh.ARRAY_COLOR][vertex].g,source[Mesh.ARRAY_COLOR][vertex].b,source[Mesh.ARRAY_COLOR][vertex].a)))
		parity=parity and arrays[Mesh.ARRAY_VERTEX][vertex].is_equal_approx(source[Mesh.ARRAY_VERTEX][vertex])
		parity=parity and arrays[Mesh.ARRAY_VERTEX][vertex+4].is_equal_approx(transform*source[Mesh.ARRAY_VERTEX][vertex])
		parity=parity and arrays[Mesh.ARRAY_NORMAL][vertex+4].distance_to((transform.basis.inverse().transposed()*source[Mesh.ARRAY_NORMAL][vertex]).normalized())<.0001
		parity=parity and arrays[Mesh.ARRAY_TEX_UV][vertex+4]==source[Mesh.ARRAY_TEX_UV][vertex] and arrays[Mesh.ARRAY_COLOR][vertex+4]==source[Mesh.ARRAY_COLOR][vertex]
	print("SYNTHETIC_ERRORS ",JSON.stringify(geometry_errors))
	check(parity and arrays[Mesh.ARRAY_INDEX]==PackedInt32Array([0,1,2,0,2,3,4,5,6,4,6,7]),"transformed positions normals tangents UV colors and topology retain source geometry")
	check(baked.parts[0].material==material and baked.parts[0].transform==Transform3D.IDENTITY,"material reference retained with baked local coordinates")
	var lods:Array=RenderingServer.mesh_get_surface(baked.parts[0].mesh.get_rid(),0).get("lods",[])
	check(lods.size()==2 and is_equal_approx(lods[0].edge_length,.25) and is_equal_approx(lods[1].edge_length,.5),"MultiMesh LOD thresholds retain parent-instance scale policy, not double-applied row scale")
	check(lods[0].index_data.size()==18 and lods[1].index_data.size()==12,"LOD assembly retains detailed contributor until its own error threshold")
	var split:Array=parts.duplicate();split.append({"mesh":quad(material,true),"transform":Transform3D.IDENTITY})
	check(baker.bake(split).parts.size()==2,"different attribute formats stay in separate draw groups")
	var shader:=ShaderMaterial.new();var changed:Array=parts.duplicate(true);changed[0].material=shader
	check(not baker.bake(changed).ok,"custom shader semantics are never silently baked")
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	check(not baker.bake(parts).ok,"transparent sorting semantics retain original representation")
	material.transparency=BaseMaterial3D.TRANSPARENCY_DISABLED;material.uv1_triplanar=true
	check(not baker.bake(parts).ok,"object-local triplanar semantics retain original representation")
	material.uv1_triplanar=false
	if not "--native-only" in OS.get_cmdline_user_args():
		var cache=load("res://addons/vehicle_runtime/parked_prototype_cache.gd")
		var receipt:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(cache.RECEIPT))
		if not cache.valid_receipt(receipt):
			print("BAKE_RECEIPT output ",FileAccess.get_sha256(cache.PATH)," expected ",receipt.get("output_sha256"))
			for path:String in receipt.get("sources",{}):
				if FileAccess.file_exists(path):print("BAKE_RECEIPT source ",path," ",FileAccess.get_sha256(path)," expected ",receipt.sources[path])
		check(cache.valid_receipt(receipt),"offline prototype receipt matches current artifact and available sources")
		var stale:Dictionary=receipt.duplicate(true);stale.output_sha256="0".repeat(64)
		check(not cache.valid_receipt(stale),"changed derived artifact is rejected without runtime mesh baking")
		stale=receipt.duplicate(true);stale.sources[cache.PATH]="0".repeat(64)
		check(not cache.valid_receipt(stale) and not cache.valid_receipt({"schema":1,"sources":[]}),"stale sources and malformed bake metadata reject safely")
	changed=parts.duplicate();changed[1]={"mesh":mesh,"transform":Transform3D(Basis.IDENTITY.scaled(Vector3(2,1,1)),Vector3.ZERO)}
	check(not baker.bake(changed).ok,"nonuniform transforms retain original representation")
	changed[1]={"mesh":mesh,"transform":Transform3D(Basis.IDENTITY.scaled(Vector3(-1,1,1)),Vector3.ZERO)}
	check(not baker.bake(changed).ok,"reflections retain original winding representation")
	var many:Array=[];many.resize(65);many.fill(parts[0]);check(not baker.bake(many).ok,"prototype admission respects part budget")
	var excessive_levels:Array=[]
	for surface in 5:
		var levels:Dictionary={}
		for level in 32:levels[float(surface*32+level+1)]=PackedInt32Array([0,1,2])
		var detailed:=ArrayMesh.new();detailed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,source,[],levels);detailed.surface_set_material(0,material)
		excessive_levels.append({"mesh":detailed,"transform":Transform3D.IDENTITY})
	var rejected:Dictionary=baker.bake(excessive_levels)
	check(not rejected.ok and rejected.reason=="merged_lod_budget","more than 128 distinct thresholds reject instead of delaying imported LODs")
	if "--native-only" in OS.get_cmdline_user_args():finish({"geometry_errors":geometry_errors,"scope":"Synthetic native prototype validation, source geometry/attributes, MultiMesh LOD policy and bounded rejection; no actual-car cache or visual test."});return
	var body:RigidBody3D=load("res://vehicle_demo/scenes/car.tscn").instantiate();body.freeze=true;body.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(body)
	body.set_controls_enabled(false);body.set_physics_process(false);await process_frame
	parts=[]
	for node:MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
		if node.mesh!=null and node.is_visible_in_tree():parts.append({"mesh":node.mesh,"transform":body.global_transform.affine_inverse()*node.global_transform,"material":node.material_override})
	baked=baker.bake(parts);body.free()
	var stats:Dictionary=baked.duplicate();stats.erase("parts");print("ACTUAL_PROTOTYPE ",JSON.stringify(stats))
	check(baked.ok and baked.parts.size()==1,"actual Ranger consolidates from 32 parts to one shared-material mesh")
	if not baked.ok:finish({"bake":stats});return
	var published:Array=load("res://addons/vehicle_runtime/parked_prototype_cache.gd").parts(parts)
	check(published.size()==1,"rendered comparison uses the production cached binary rather than a fresh test bake")
	var fleet:RefCounted=ClassDB.instantiate("NativeVehicleFleet");fleet.spawn(Transform3D(Basis.IDENTITY,Vector3(120,1,120)))
	var original:Node3D=ClassDB.instantiate("NativeVehicleHorizon");root.add_child(original);original.configure(fleet,parts,"terraforest.ranger.v1")
	var compact:Node3D=ClassDB.instantiate("NativeVehicleHorizon");root.add_child(compact);compact.configure(fleet,published,"terraforest.ranger.v1")
	while not original.statistics().ready or not compact.statistics().ready:await process_frame
	var camera:=Camera3D.new();camera.far=2000;root.add_child(camera);camera.current=true
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("566474");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.6;root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-25,0);root.add_child(sun)
	var comparisons:Array=[]
	for distance:float in [8.0,40.0,180.0]:
		camera.position=Vector3(120,1,120)+Vector3(distance*.7,distance*.35,distance);camera.look_at(Vector3(120,2,120));root.mesh_lod_threshold=0 if distance==8 else 1
		original.show();compact.hide()
		for frame in 12:await RenderingServer.frame_post_draw
		var before:=root.get_texture().get_image();before.save_png(output.path_join("original_%d.png"%distance))
		original.hide();compact.show()
		for frame in 12:await RenderingServer.frame_post_draw
		var after:=root.get_texture().get_image();after.save_png(output.path_join("compact_%d.png"%distance))
		var difference:=pixels(before,after);difference.distance=distance;comparisons.append(difference)
		if distance==8:check(difference.mean_channel_error<.05 and difference.changed_pixels_over_3<root.size.x*root.size.y*.001,"full-detail rendered pixels retain original appearance")
	original.free();compact.free();camera.free();environment.free();sun.free();await process_frame
	finish({"bake":stats,"comparisons":comparisons,"scope":"Bounded static opaque prototype compaction and imported-LOD reuse; near source appearance plus far review images. Not universal pixel-identical LOD selection or visual acceptance."})
func finish(result:Dictionary)->void:
	result.checks=checks;result.failures=failures
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("VEHICLE_PROTOTYPE checks=",checks," failures=",failures);quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends SceneTree
const Asset=preload("res://addons/world_ecosystem/woodland_mesh.gd")
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:run.call_deferred()
func settle() -> void:
	for i in 12:await RenderingServer.frame_post_draw
func run() -> void:
	Engine.max_fps=60;root.mesh_lod_threshold=0
	DirAccess.make_dir_recursive_absolute("res://reports/woodland_visual")
	var meshes: Array[Mesh]=[];var counts: Array=[]
	for species in 3:
		var mesh:=Asset.build(species);meshes.append(mesh)
		check(mesh!=null,"species %d loads including stone maps"%species)
		if mesh==null:quit(1);return
		var arrays:=mesh.surface_get_arrays(0);var full:=Asset.build(species,false)
		var bounds:=AABB(Vector3(-0.4,-0.2 if species==0 else 0,-0.4),Vector3(0.8,0.4 if species==0 else 0.75,0.8))
		var valid:=true;var faces: PackedVector3Array=mesh.get_faces()
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			var point: Vector3=arrays[Mesh.ARRAY_VERTEX][i];var normal: Vector3=arrays[Mesh.ARRAY_NORMAL][i]
			valid=valid and point.is_finite() and bounds.has_point(point) and normal.is_finite() and normal.length_squared()>0.99
			if species>0:valid=valid and bounds.has_point(point+Vector3(0.012,0,0.007)) and bounds.has_point(point-Vector3(0.012,0,0.007))
		check(valid,"species %d geometry, normals and wind fit interaction envelope"%species)
		valid=true
		for i in range(0,faces.size(),3):valid=valid and (faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).length_squared()>0.000000000000001
		check(valid,"species %d near triangles are nondegenerate"%species)
		check(mesh.get_faces()==full.get_faces(),"species %d LOD retains exact near geometry"%species)
		counts.append({"species":species,"near_triangles":faces.size()/3,"distant_triangles":(arrays[Mesh.ARRAY_VERTEX].size()-full.surface_get_array_len(0))/3})
		mesh.surface_get_material(0).set_shader_parameter("wind_strength",0.0)
	var world:=Node3D.new();root.add_child(world)
	var camera:=Camera3D.new();world.add_child(camera);camera.current=true;camera.position=Vector3(1.3,1.7,3.4);camera.look_at(Vector3(0,0.2,0));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.45
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("202b27");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("bbc9bd");env.environment.ambient_light_energy=0.55;world.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-52,-27,0);light.light_color=Color("fff0d4");light.light_energy=1.3;light.shadow_enabled=true;world.add_child(light)
	for row in 2:
		for species in 3:
			var item:=MeshInstance3D.new();item.mesh=preload("res://addons/world_ecosystem/ground_mesh.gd").build(species,false) if row==0 else meshes[species];item.position=Vector3(species-1,0.20 if species==0 else 0.005,(row-0.5)*1.0);world.add_child(item)
	var floor_mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(3.5,0.05,2.3);floor_mesh.mesh=box;var material:=StandardMaterial3D.new();material.albedo_color=Color("454b3c");material.roughness=1;floor_mesh.material_override=material;world.add_child(floor_mesh)
	var label:=Label.new();label.position=Vector2(40,32);label.add_theme_font_size_override("font_size",26);label.text="TEMPERATE WOODLAND / first art pass\nBack: previous assets   Front: detailed sample\nStone + fern understory + mixed green/dry grass";root.add_child(label)
	await settle();var still:=root.get_texture().get_image();still.save_png("res://reports/woodland_visual/comparison.png")
	for species in [1,2]:meshes[species].surface_get_material(0).set_shader_parameter("wind_strength",1.0)
	await settle()
	check(still.get_data()!=root.get_texture().get_image().get_data(),"foliage shader produces visible wind without instance updates")
	root.get_texture().get_image().save_png("res://reports/woodland_visual/wind.png")
	check(root.size==Vector2i(1920,1080) and DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN] and Engine.max_fps==60,"fullscreen1080p cap60")
	var result:={"checks":checks,"failures":failures,"meshes":counts,"scope":"Visual asset/geometry regression; no GPU-time, final-art approval or combined density qualification."}
	var file:=FileAccess.open("res://reports/woodland_visual/result.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	label.free();world.free();await process_frame
	print("WOODLAND_VISUAL ",JSON.stringify(result));quit(1 if failures else 0)

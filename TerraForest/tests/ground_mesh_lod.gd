# SPDX-License-Identifier: 0BSD
extends SceneTree
const Asset=preload("res://addons/world_ecosystem/woodland_mesh.gd")
var failures:=0
var checks:=0
var rows: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:run.call_deferred()
func settle() -> void:
	for i in 8:await RenderingServer.frame_post_draw
func primitives() -> int:
	return RenderingServer.viewport_get_render_info(root.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
func run() -> void:
	Engine.max_fps=60
	DirAccess.make_dir_recursive_absolute("res://reports/ground_mesh_lod")
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("30373d");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=0.7;root.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-30,0);root.add_child(light)
	for species in 3:
		var mesh:=Asset.build(species);var full:=Asset.build(species,false)
		mesh.surface_get_material(0).set_shader_parameter("wind_strength",0.0)
		var arrays:=mesh.surface_get_arrays(0);var old:=full.surface_get_arrays(0)
		check(mesh.get_faces()==full.get_faces(),"species %d near geometry is unchanged"%species)
		var valid:=true
		var bounds:=AABB(Vector3(-0.4,-0.2 if species==0 else 0,-0.4),Vector3(0.8,0.4 if species==0 else 0.75,0.8))
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			valid=valid and bounds.has_point(arrays[Mesh.ARRAY_VERTEX][i]) and arrays[Mesh.ARRAY_NORMAL][i].is_finite() and arrays[Mesh.ARRAY_NORMAL][i].length_squared()>0.99
		check(valid,"species %d all LOD vertices/normals stay inside picking envelope"%species)
		check((arrays[Mesh.ARRAY_VERTEX].size()-old[Mesh.ARRAY_VERTEX].size())/3==[48,392,83][species],"species %d distant triangle budget"%species)
		var batch=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch)
		check(batch.configure_asset("ground_cover/%d/v1"%species,mesh) and batch.configure_render_streaming(true,200,32,200000,4,8192),"native batch configured")
		batch.set_casts_shadows(false)
		var ids:=PackedInt64Array();var poses: Array[Transform3D]=[]
		for i in 256:
			ids.append(i+1);poses.append(Transform3D(Basis.IDENTITY,Vector3((i%16)*0.5,0,(i/16)*0.5)))
		check(batch.upsert_transforms(ids,poses),"256 interactive identities accepted")
		var snapshot: PackedByteArray=batch.capture_snapshot()
		camera.position=Vector3(4,5,14);camera.look_at(Vector3(4,0,4));root.mesh_lod_threshold=0
		await settle();var near_full:=primitives();var near_image:=root.get_texture().get_image().get_data()
		root.mesh_lod_threshold=1;await settle();var near_lod:=primitives()
		check(near_image==root.get_texture().get_image().get_data(),"species %d near pixels match LOD-disabled image"%species)
		camera.position=Vector3(4,35,100);camera.look_at(Vector3(4,0,4));root.mesh_lod_threshold=0
		await settle();var far_full:=primitives()
		root.mesh_lod_threshold=1;await settle();var far_lod:=primitives()
		# Godot ed1daf0bf Forward+ counts per page in the LOD branch, but
		# multiplies by instance_count when LOD is disabled (lines 995-1017).
		# Compare the same branch, with every page in view; retain raw counters.
		check(far_full==near_full and far_lod>0 and far_lod<=near_lod*0.55,"species %d far per-page primitives reduced: %d -> %d"%[species,near_lod,far_lod])
		check(near_lod==batch.get_child_count()*[360,1512,468][species] and far_lod==batch.get_child_count()*[48,392,8][species],"species %d native near/far LOD counts match both mesh tiers"%species)
		if species==2:
			camera.position=Vector3(4,35,160);camera.look_at(Vector3(4,0,4));await settle()
			check(primitives()==batch.get_child_count()*3,"outer grass LOD draws three triangles per instance")
		check(batch.capture_snapshot()==snapshot and batch.get_ids()==ids,"LOD leaves all identities and placement bytes unchanged")
		rows.append({"species":species,"near_full":near_full,"near_lod":near_lod,"far_full":far_full,"far_lod":far_lod})
		check(batch.set_shadow_distance(12.0) and not batch.set_shadow_distance(-1.0),"native shadow radius validates")
		batch.set_casts_shadows(true);batch.set_render_focus(Vector3.ZERO);await settle()
		check(batch.render_stats().shadow_batches==batch.get_child_count(),"near pages cast shadows")
		batch.set_render_focus(Vector3(150,0,0));await settle()
		check(batch.get_child_count()>0 and batch.render_stats().shadow_batches==0,"distant pages keep geometry without cast shadows")
		batch.set_render_focus(Vector3.ZERO);await settle()
		check(batch.render_stats().shadow_batches==batch.get_child_count() and batch.capture_snapshot()==snapshot,"return restores shadows without changing placement")
		batch.free()
	# Magnified high/low comparison: forced low is review only, not runtime policy.
	var gallery: Array[MeshInstance3D]=[]
	camera.position=Vector3(1.7,1.3,3.3);camera.look_at(Vector3(0,0.2,0));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.7
	for row in 2:
		for species in 3:
			var item:=MeshInstance3D.new();item.mesh=Asset.build(species,row==1);item.lod_bias=0.000001 if row==1 else 1.0;item.position=Vector3(species-1,0,(row-0.5)*1.1);root.add_child(item);gallery.append(item)
	await settle();root.get_texture().get_image().save_png("res://reports/ground_mesh_lod/gallery.png")
	check(root.size==Vector2i(1920,1080) and DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN],"fullscreen1080p cap60")
	var result:={"checks":checks,"failures":failures,"rows":rows,"scope":"Native batched draw-count/identity regression. Not GPU speedup, density, mixed-world or endurance qualification. Gallery back high/front forced distant LOD."}
	var file:=FileAccess.open("res://reports/ground_mesh_lod/result.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	for item in gallery:item.free()
	camera.free();env.free();light.free();await process_frame
	print("GROUND_MESH_LOD ",JSON.stringify(result));quit(1 if failures else 0)

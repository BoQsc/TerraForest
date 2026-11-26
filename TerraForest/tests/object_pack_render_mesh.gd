# SPDX-License-Identifier: 0BSD
extends SceneTree
const Packs=preload("res://addons/structures/pack_registry.gd")
const RenderMesh=preload("res://addons/structures/pack_render_mesh.gd")
var checks:=0
var failures:=0
var folder:=""
var pixel_comparison: Dictionary={}
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="): folder=arg.trim_prefix("--check-evidence-dir=")
	run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func triangle_count(mesh: Mesh) -> int:
	var result:=0
	for index in mesh.get_surface_count(): result+=mesh.surface_get_array_index_len(index)/3
	return result
func run() -> void:
	check(Packs.discover(),"pack discovery succeeds")
	var sources: Array=[]
	for row: Dictionary in Packs.objects.values(): sources.append(load(row.directory+"/models/"+row.id+".tres"))
	RenderMesh.configure(sources)
	var before:=0;var after:=0;var lod_levels:=0
	for row: Dictionary in Packs.objects.values():
		var source: ArrayMesh=load(row.directory+"/models/"+row.id+".tres")
		var mesh: Mesh=RenderMesh.prepare(source)
		before+=source.get_surface_count();after+=mesh.get_surface_count()
		lod_levels+=int(mesh.get_meta("pack_lod_levels",0))
		check(mesh.get_aabb().is_equal_approx(source.get_aabb()) and triangle_count(source)==triangle_count(mesh),"unchanged bounds and triangle count: "+row.key)
		check(mesh.get_meta("collision_boxes")==source.get_meta("collision_boxes") and mesh.get_meta("authored_size")==source.get_meta("authored_size") and RenderMesh.prepare(source)==mesh,"collision, dimensions and cached ownership: "+row.key)
		for index in source.get_surface_count():
			var material: Material=source.surface_get_material(index)
			if RenderMesh.supported(material,source.surface_get_arrays(index)): continue
			var preserved:=false
			for j in mesh.get_surface_count(): preserved=preserved or mesh.surface_get_material(j)==material
			check(preserved,"unsupported material retained exactly: "+row.key+"/"+str(index))
	check(after<before,"material surfaces are actually consolidated")
	check(lod_levels>0,"distance-based index LODs are present without replacing full-detail surfaces")
	print("PACK_RENDER_SURFACES before=",before," after=",after)
	if DisplayServer.get_name()!="headless": await compare_views()
	FileAccess.open(folder.path_join("render_mesh.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"source_surfaces":before,"render_surfaces":after,"lod_levels":lod_levels,"pixels":pixel_comparison}))
	print("OBJECT_PACK_RENDER_MESH checks=",checks," failures=",failures);quit(1 if failures else 0)
func compare_views() -> void:
	var examples:=["homestead_07/chessboard","homestead_10/bread_basket","homestead_10/china_cabinet","homestead_07/floor_lamp","outdoor_01/bird_nest","outdoor_01/trash_can"]
	var original:=Image.create(1152,768,false,Image.FORMAT_RGB8);var combined:=Image.create(1152,768,false,Image.FORMAT_RGB8)
	var far_source:=Image.create(1152,768,false,Image.FORMAT_RGB8);var far_lods:=Image.create(1152,768,false,Image.FORMAT_RGB8)
	for index in examples.size():
		var source: Mesh=load("res://addons/structures/packs/"+examples[index].get_slice("/",0)+"/models/"+examples[index].get_slice("/",1)+".tres")
		var view:=SubViewport.new();view.size=Vector2i(384,384);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;view.msaa_3d=Viewport.MSAA_4X;root.add_child(view)
		var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("263c40");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65;view.add_child(environment)
		var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-35,0);sun.light_energy=1.8;sun.shadow_enabled=true;view.add_child(sun)
		var instance:=MeshInstance3D.new();instance.mesh=source;instance.lod_bias=1000000;view.add_child(instance)
		var bounds:=source.get_aabb();var centre:=bounds.get_center();var radius:=bounds.size.length()
		var camera:=Camera3D.new();view.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=radius*1.1;camera.position=centre+Vector3(1,.8,-1.4 if index==2 else 1.4)*radius;camera.look_at(centre);camera.make_current()
		for frame in 6: await RenderingServer.frame_post_draw
		var pixels:=view.get_texture().get_image();pixels.convert(Image.FORMAT_RGB8);original.blit_rect(pixels,Rect2i(0,0,384,384),Vector2i((index%3)*384,(index/3)*384))
		instance.mesh=RenderMesh.prepare(source)
		for frame in 6: await RenderingServer.frame_post_draw
		pixels=view.get_texture().get_image();pixels.convert(Image.FORMAT_RGB8);combined.blit_rect(pixels,Rect2i(0,0,384,384),Vector2i((index%3)*384,(index/3)*384))
		camera.size*=4;instance.mesh=source
		for frame in 6: await RenderingServer.frame_post_draw
		pixels=view.get_texture().get_image();pixels.convert(Image.FORMAT_RGB8);far_source.blit_rect(pixels,Rect2i(0,0,384,384),Vector2i((index%3)*384,(index/3)*384))
		instance.mesh=RenderMesh.prepare(source);instance.lod_bias=1.0
		for frame in 6: await RenderingServer.frame_post_draw
		pixels=view.get_texture().get_image();pixels.convert(Image.FORMAT_RGB8);far_lods.blit_rect(pixels,Rect2i(0,0,384,384),Vector2i((index%3)*384,(index/3)*384));view.free()
	check(original.save_png(folder.path_join("source_materials.png"))==OK and combined.save_png(folder.path_join("combined_materials.png"))==OK,"paired geometry, PBR, textured, glass and emissive comparisons captured")
	check(far_source.save_png(folder.path_join("lod_source.png"))==OK and far_lods.save_png(folder.path_join("lod_render.png"))==OK,"matched small-screen-size LOD comparisons captured")
	var original_bytes:=original.get_data();var combined_bytes:=combined.get_data();var peak:=0;var total:=0
	for index in original_bytes.size():
		var difference:=absi(int(original_bytes[index])-int(combined_bytes[index]));peak=maxi(peak,difference);total+=difference
	pixel_comparison={"max_channel_error":peak,"mean_channel_error":float(total)/original_bytes.size(),"samples":original_bytes.size()}
	check(peak<=2 and pixel_comparison.mean_channel_error<=.01,"combined materials match original pixels within two 8-bit levels")

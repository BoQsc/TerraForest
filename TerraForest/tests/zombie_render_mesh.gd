# SPDX-License-Identifier: 0BSD
extends SceneTree
const Zombie=preload("res://addons/characters/runtime/zombie.gd")
const RenderMesh=preload("res://addons/characters/runtime/zombie_render_mesh.gd")
var checks:=0
var failures:=0
var folder:=""
var actor:Node3D
var originals:Dictionary={}
var prepared:Dictionary={}
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="):folder=arg.trim_prefix("--check-evidence-dir=")
	run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func set_combined(enabled:bool)->void:
	for node:MeshInstance3D in originals:
		var weights:Array=[]
		for index in node.mesh.get_blend_shape_count():weights.append(node.get_blend_shape_value(index))
		node.mesh=prepared[node].mesh if enabled and prepared.has(node) else originals[node]
		for index in weights.size():node.set_blend_shape_value(index,weights[index])
func run()->void:
	var view:=SubViewport.new();view.size=Vector2i(512,512);view.own_world_3d=true;view.msaa_3d=Viewport.MSAA_4X;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	actor=Zombie.new();actor.merge_render_materials=false;actor.set_simulation_available(false);view.add_child(actor)
	check(actor.initialized,"original rig initializes")
	var meshes:Array=[]
	for node:MeshInstance3D in actor.part_meshes.values():originals[node]=node.mesh;meshes.append(node.mesh)
	for pair:Dictionary in actor.caps.values():
		for node:MeshInstance3D in pair.values():originals[node]=node.mesh;meshes.append(node.mesh)
	check(RenderMesh.configure(meshes),"shared PBR arrays retain original texture sizes and mipmaps")
	var before:=0;var after:=0
	for node:MeshInstance3D in originals:
		var source:ArrayMesh=originals[node];before+=source.get_surface_count()
		var packet:Dictionary=actor._bake_source(source)
		var result:Dictionary=RenderMesh.prepare(source,packet)
		if result.is_empty():
			after+=source.get_surface_count()
			if source.get_surface_count()>1:
				var rejected:Array=[]
				for index in source.get_surface_count():
					var material:=source.surface_get_material(index)
					if not RenderMesh.supported(material):
						var differences:Dictionary={}
						for property:Dictionary in RenderMesh.defaults.get_property_list():
							if property.usage&PROPERTY_USAGE_STORAGE and material.get(property.name)!=RenderMesh.defaults.get(property.name):differences[property.name]=str(material.get(property.name))
						rejected.append(differences)
				print("RENDER_FALLBACK ",node.name," ",JSON.stringify(rejected))
			continue
		prepared[node]=result;after+=result.mesh.get_surface_count()
		var positions:=PackedVector3Array();var bones:=PackedInt32Array();var weights:=PackedFloat32Array();var triangles:=0
		for values:Array in packet.surfaces:
			positions.append_array(values[Mesh.ARRAY_VERTEX]);bones.append_array(values[Mesh.ARRAY_BONES]);weights.append_array(values[Mesh.ARRAY_WEIGHTS]);triangles+=values[Mesh.ARRAY_INDEX].size()/3
		var combined:Array=result.packet.surfaces[0]
		check(combined[Mesh.ARRAY_VERTEX]==positions and combined[Mesh.ARRAY_BONES]==bones and combined[Mesh.ARRAY_WEIGHTS]==weights and combined[Mesh.ARRAY_INDEX].size()/3==triangles,"exact source-order vertices, skin weights and triangles: "+str(node.name))
		check(result.mesh.get_blend_shape_count()==source.get_blend_shape_count() and result.mesh.custom_aabb==source.get_aabb(),"morph count and original culling bounds preserved: "+str(node.name))
	check(after<before/2,"material submissions fall by more than half")
	print("ZOMBIE_RENDER_SURFACES before=",before," after=",after)
	var comparison:Dictionary={}
	if DisplayServer.get_name()!="headless" and not prepared.is_empty():comparison=await compare_views(view)
	view.free();await process_frame
	FileAccess.open(folder.path_join("zombie_render_mesh.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"surfaces_before":before,"surfaces_after":after,"pixels":comparison}))
	print("ZOMBIE_RENDER_MESH checks=",checks," failures=",failures);quit(1 if failures else 0)
func compare_views(view:SubViewport)->Dictionary:
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("263c40");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65;view.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-35,0);sun.light_energy=1.8;sun.shadow_enabled=not OS.get_cmdline_user_args().has("--no-shadows");view.add_child(sun)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;view.add_child(camera);camera.make_current()
	var original:=Image.create(1024,1536,false,Image.FORMAT_RGB8);var combined:=Image.create(1024,1536,false,Image.FORMAT_RGB8)
	var views:Array[Dictionary]=[]
	for index in 6:
		set_combined(false)
		actor.animation_player.play(actor._animation_key("Zombie_Attack_Bite" if index==2 else "Zombie_Attack_Left"));actor.animation_player.seek(.65 if index==2 else .3,true);actor.animation_player.pause();actor.skeleton.force_update_all_bone_transforms()
		var center:=Vector3(0,1.62,0) if index in [2,3] else Vector3(0,.9,0)
		camera.projection=Camera3D.PROJECTION_PERSPECTIVE if index>=4 else Camera3D.PROJECTION_ORTHOGONAL
		camera.size=.5 if index in [2,3] else 2.15
		camera.position=center+(Vector3(0,0,6 if index==4 else 24) if index>=4 else Vector3(1,.15,2 if index%2==0 else -2)*2);camera.look_at(center)
		for frame in 8:await RenderingServer.frame_post_draw
		var pixels:=view.get_texture().get_image();pixels.convert(Image.FORMAT_RGB8);original.blit_rect(pixels,Rect2i(0,0,512,512),Vector2i(index%2*512,index/2*512))
		var source_pixels:=pixels.get_data()
		var source_primitives:=view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		set_combined(true)
		for frame in 8:await RenderingServer.frame_post_draw
		pixels=view.get_texture().get_image();pixels.convert(Image.FORMAT_RGB8);combined.blit_rect(pixels,Rect2i(0,0,512,512),Vector2i(index%2*512,index/2*512))
		var comparison:=pixel_error(source_pixels,pixels.get_data())
		comparison.source_primitives=source_primitives;comparison.combined_primitives=view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		views.append(comparison)
		check(comparison.mean<.1 and float(comparison.channels_over_2)/comparison.channels<.001,"original appearance preserved in view "+str(index))
	check(views[5].combined_primitives<views[0].combined_primitives and views[5].source_primitives<views[0].source_primitives,"distance LODs remain active in both rigs")
	check(original.save_png(folder.path_join("zombie_source.png"))==OK and combined.save_png(folder.path_join("zombie_combined.png"))==OK,"paired full-body, face/morph and distance views captured")
	var result:=pixel_error(original.get_data(),combined.get_data());result.views=views
	print("ZOMBIE_RENDER_PIXELS ",JSON.stringify(result))
	return result
func pixel_error(a:PackedByteArray,b:PackedByteArray)->Dictionary:
	var peak:=0;var total:=0;var changed:=0
	for index in a.size():
		var error:=absi(int(a[index])-int(b[index]));peak=maxi(peak,error);total+=error
		if error>2:changed+=1
	return {"peak":peak,"mean":float(total)/a.size(),"channels_over_2":changed,"channels":a.size()}

# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var output:="res://reports/current_drop_models/source"
	var previous:=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--drop-model-evidence="):output=argument.trim_prefix("--drop-model-evidence=")
		if argument.begins_with("--old-drops="):previous=argument.trim_prefix("--old-drops=")
	var scene:=Node3D.new();root.add_child(scene)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("182a28");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.6;scene.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-30,0);scene.add_child(light)
	var view=preload("res://addons/player_runtime/tool_view.gd").new();scene.add_child(view)
	var pickups=preload("res://addons/world_runtime/material_pickups.gd").new();scene.add_child(pickups)
	check(pickups.prepare(preload("res://addons/world_runtime/world_persistence.gd").new()),"actual native world-drop renderer initializes")
	pickups.set_full_size_enabled(false) # This historical comparison uses compact art.
	for item:int in [1,2]:
		view.human.equip(item)
		var parts:Array[MeshInstance3D]=[];var bounds:=AABB();var first:=true
		for mesh:MeshInstance3D in view.human.meshes:
			if not String(mesh.name).to_lower().replace("_",".").begins_with("equipment.") or not mesh.visible:continue
			parts.append(mesh);var box:AABB=mesh.global_transform*mesh.mesh.get_aabb()
			bounds=box if first else bounds.merge(box);first=false
		var factor:=.35/maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))
		var normalized:=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*factor),-bounds.get_center()*factor)
		var expected:PackedVector3Array=[]
		var center:=Vector3(0,.38 if item==1 else -.38,0)
		for mesh:MeshInstance3D in parts:
			var copy:=MeshInstance3D.new();copy.mesh=mesh.mesh;copy.skeleton=NodePath("");copy.skin=null;scene.add_child(copy)
			copy.transform=Transform3D(Basis.IDENTITY,center)*normalized*mesh.global_transform
			for surface in mesh.mesh.get_surface_count():
				copy.set_surface_override_material(surface,mesh.get_active_material(surface))
				var data:=mesh.mesh.surface_get_arrays(surface)
				var vertices:PackedVector3Array=data[Mesh.ARRAY_VERTEX];var indices:PackedInt32Array=data[Mesh.ARRAY_INDEX]
				if indices.is_empty():
					for vertex in vertices.size():indices.append(vertex)
				for vertex:int in indices:expected.append(normalized*mesh.global_transform*vertices[vertex])
		var baked:Mesh=pickups.renderers[item].multimesh.mesh
		var arrays:=baked.surface_get_arrays(0);var actual:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var matches:bool=actual.size()==expected.size()
		if matches:
			for vertex in actual.size():
				if actual[vertex].distance_to(expected[vertex])>.00001:matches=false;break
		check(not parts.is_empty() and matches,"item %d drop preserves every triangle of the current held model (%d triangles)"%[item,expected.size()/3])
		check(baked.get_surface_count()==1 and maxf(baked.get_aabb().size.x,maxf(baked.get_aabb().size.y,baked.get_aabb().size.z))<=.35001,"item %d keeps one batched surface and the existing 35 cm size"%item)
		check(arrays[Mesh.ARRAY_BONES]==null or arrays[Mesh.ARRAY_BONES].is_empty(),"item %d drop contains no player skin/animation rig"%item)
		var material:=baked.surface_get_material(0) as ShaderMaterial
		check(material!=null and material.get_shader_parameter("wood_albedo") is Texture2D and material.get_shader_parameter("wood_normal") is Texture2D,"item %d retains current wood texture and normal detail"%item)
		var pbr:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2];var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		var has_wood:=false;var has_metal:=false
		for vertex in pbr.size():
			has_wood=has_wood or pbr[vertex].y>.5
			has_metal=has_metal or colors[vertex].a>.8
		check(has_wood and has_metal,"item %d preserves distinct wood and metal material properties"%item)
		if not previous.is_empty():
			var old:Mesh=load(previous.path_join("%d.res"%item))
			var old_node:=MeshInstance3D.new();old_node.mesh=old;old_node.position=center+Vector3(-.75,0,0);scene.add_child(old_node)
			check(old.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()!=actual.size(),"item %d replaces the old representative geometry"%item)
		pickups.spawn(item,center+Vector3(.75,0,0))
		for column in 3:
			var label:=Label3D.new();label.text=("Pickaxe" if item==1 else "Hatchet")+" · "+["Previous drop","Current held source","Current world drop"][column];label.font_size=25;label.pixel_size=.0015;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.position=center+Vector3((column-1)*.75,-.27,.15);scene.add_child(label)
	view.hide();pickups.update_view(0,Vector3.ZERO,true)
	check(pickups.render_status[1].rendered==1 and pickups.render_status[2].rendered==1,"updated models render through the actual native pickup batches")
	if DisplayServer.get_name()!="headless":
		var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.65;scene.add_child(camera);camera.position=Vector3(1,.65,3);camera.look_at(Vector3.ZERO);camera.make_current()
		for i in 5:await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(output)
		check(root.get_texture().get_image().save_png(output.path_join("comparison.png"))==OK,"comparison capture saves")
	scene.free();await process_frame
	print("CURRENT_DROP_MODELS checks=",checks," failures=",failures);quit(1 if failures else 0)

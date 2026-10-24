# SPDX-License-Identifier: 0BSD
extends SceneTree
const Icons=preload("res://addons/player_runtime/item_icons.gd")
const Cache=preload("res://tools/item_icon_cache.gd")
func _initialize() -> void:run.call_deferred()
func bounds(node: Node3D) -> AABB:
	var box:=AABB();var first:=true
	for child in node.get_children():
		if child is MeshInstance3D:
			var b: AABB=child.transform*child.mesh.get_aabb()
			box=b if first else box.merge(b);first=false
	return box
func instance(mesh: Mesh) -> MeshInstance3D:
	var out:=MeshInstance3D.new();out.mesh=mesh;return out
func copy_visible(source:Node,model:Node3D)->void:
	if source is MeshInstance3D and source.mesh!=null and source.is_visible_in_tree():copy_mesh(source,model)
	for child in source.get_children():copy_visible(child,model)
func copy_mesh(source:MeshInstance3D,model:Node3D)->void:
	# Detached, static imported geometry/materials: no player or driving rig is
	# rendered into the icon, and no gameplay asset is modified by this bake.
	var copy:=instance(source.mesh);copy.transform=model.global_transform.affine_inverse()*source.global_transform
	copy.material_override=source.material_override;copy.skeleton=NodePath("");copy.skin=null
	for surface in source.mesh.get_surface_count():copy.set_surface_override_material(surface,source.get_surface_override_material(surface))
	model.add_child(copy)
func run() -> void:
	var current_models:bool="--current-models" in OS.get_cmdline_user_args()
	var selected:Array=["1","2","501"]
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--icon-items="):selected=Array(argument.trim_prefix("--icon-items=").split(",",false));current_models=true
	var input_state:=Cache.snapshot();var baked:Array=[]
	var viewport:=SubViewport.new();viewport.size=Vector2i(512,512);viewport.transparent_bg=true;viewport.own_world_3d=true;viewport.msaa_3d=Viewport.MSAA_4X;root.add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.7;viewport.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-35,0);sun.light_energy=1.6;viewport.add_child(sun)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;viewport.add_child(camera);camera.current=true
	var tool=preload("res://addons/player_runtime/tool_view.gd").new();viewport.add_child(tool);tool.hide()
	var atlas:=Image.create(1024,ceili(Icons.KEYS.size()/8.0)*128,false,Image.FORMAT_RGBA8);atlas.fill(Color.TRANSPARENT)
	if current_models:
		var previous:=Image.new()
		if previous.load_png_from_buffer(FileAccess.get_file_as_bytes("res://addons/player_runtime/art/item_icons.trtex"))!=OK:viewport.free();quit(1);return
		atlas.blit_rect(previous,Rect2i(Vector2i.ZERO,previous.get_size()),Vector2i.ZERO)
	DirAccess.make_dir_recursive_absolute("res://reports/current_item_icons")
	for i in Icons.KEYS.size():
		var key: String=Icons.KEYS[i];var id:=key.to_int();var model:=Node3D.new();viewport.add_child(model)
		if current_models and key not in selected:model.free();continue
		if id in [1,2]:
			tool.human.equip(id)
			for mesh:MeshInstance3D in tool.human.meshes:
				var label:=String(mesh.name).to_lower().replace("_",".")
				if label.begins_with("equipment.") and mesh.visible:copy_mesh(mesh,model)
		elif id==501:
			var car:RigidBody3D=load("res://vehicle_demo/scenes/car.tscn").instantiate()
			car.freeze=true;car.process_mode=Node.PROCESS_MODE_DISABLED;viewport.add_child(car)
			copy_visible(car,model);car.free()
		elif id in [3,4]:
			for child in tool.tools[id].get_children():model.add_child(child.duplicate())
		elif id in [101,102,103,104]:
			var mesh:=BoxMesh.new();mesh.size=Vector3.ONE
			var material:=StandardMaterial3D.new();material.albedo_texture=load("res://addons/structures/textures/terraforest/"+["brick","wood","concrete","metal"][id-101]+"_albedo.png");mesh.material=material;model.add_child(instance(mesh))
		elif id>=201 and id<=212:
			var species: int={201:0,202:0,203:0,204:1,205:2,206:3,207:4,208:5,209:6,210:7,211:0,212:8}[id]
			var mesh: Mesh=preload("res://addons/world_ecosystem/woodland_mesh.gd").build(species,false)
			mesh.surface_get_material(0).set_shader_parameter("wind_strength",0.0)
			if species==2:preload("res://addons/world_ecosystem/woodland_mesh.gd").set_grass_detail(mesh.surface_get_material(0),true)
			var object:=instance(mesh)
			if id in [202,203,211]:
				var material:=StandardMaterial3D.new();material.albedo_color=Color("797e8b") if id==202 else (Color("aa6845") if id==203 else Color("64432d"));material.roughness=0.85;object.material_override=material
			model.add_child(object)
		elif id in [301,302,303]:
			# Clothing currently has no world mesh. Folded woven garment silhouettes.
			tool.part(model,Vector3(0.5,0.16,0.45),Vector3.ZERO,Color("ad9f77"))
			if id==301:tool.part(model,Vector3(0.32,0.22,0.3),Vector3(0,0.15,0),Color("c4b38a"))
			elif id==302:
				for x in [-0.3,0.3]:tool.part(model,Vector3(0.2,0.12,0.25),Vector3(x,0,0),Color("ad9f77"))
			else:tool.part(model,Vector3(0.5,0.13,0.22),Vector3(0,0.14,0),Color("c4b38a"))
		elif key in ["Metal beam","Floor panel"]:
			tool.part(model,Vector3(4,0.2,0.2) if key=="Metal beam" else Vector3(4,0.25,4),Vector3.ZERO,Color("3b5359"))
		else:
			var file: String={"Wood framed window":"window","Wooden door (E open / close)":"door","Metal guardrail":"guardrail","Wooden fence":"fence","Doorway":"doorway","Wooden table":"table","Wooden chair":"chair","Wooden shelf":"shelf","Wooden ladder":"ladder","Wooden storage chest (E open)":"storage_chest"}[key]
			model.add_child(instance(load("res://addons/structures/prefabs/"+file+"_model.tres")))
		if id>0 and id!=501 and not current_models and not "--icons-only" in OS.get_cmdline_user_args() and (not "--woody-bush-only" in OS.get_cmdline_user_args() or id==212):bake_drop(model,id)
		var box:=bounds(model);var center:=box.get_center();var radius:=box.size.length()*0.5
		if box.size.length_squared()<.000001:push_error("No current icon geometry for "+key);model.free();viewport.free();quit(1);return
		camera.position=center+Vector3(1.3,0.9,2).normalized()*maxf(4,radius*3);camera.look_at(center);camera.size=maxf(0.1,radius*2.2)
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		for frame in 3:await RenderingServer.frame_post_draw
		var image:=viewport.get_texture().get_image();image.resize(128,128,Image.INTERPOLATE_LANCZOS);atlas.blit_rect(image,Rect2i(0,0,128,128),Vector2i((i%8)*128,(i/8)*128))
		if image.get_used_rect().size==Vector2i.ZERO:push_error("Empty current icon for "+key);model.free();viewport.free();quit(1);return
		if id in [1,2,501]:
			image.save_png("res://reports/current_item_icons/%d.png"%id)
			print("CURRENT_ICON ",id," meshes=",model.get_child_count()," bounds=",box)
		baked.append(key)
		model.free()
	var error:=Cache.publish(atlas,input_state,baked)
	viewport.free();print("ICON_BAKE failures=",0 if error==OK else 1);quit(0 if error==OK else 1)

func bake_drop(model: Node3D,id: int) -> void:
	var box:=bounds(model);var scale_factor:=0.35/maxf(box.size.x,maxf(box.size.y,box.size.z))
	var normalized:=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*scale_factor),-box.get_center()*scale_factor)
	var output:=ArrayMesh.new()
	var tool_surface:=SurfaceTool.new();tool_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for child: MeshInstance3D in model.get_children():
		for surface in child.mesh.get_surface_count():
			var material: Material=child.material_override if child.material_override!=null else child.mesh.surface_get_material(surface)
			if id in [1,2,3,4] or id>=301:
				var arrays:=child.mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
				var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
				if indices.is_empty():
					for j in vertices.size():indices.append(j)
				for index in indices:
					tool_surface.set_color(material.albedo_color);tool_surface.set_normal(child.basis*normals[index]);tool_surface.add_vertex(normalized*child.transform*vertices[index])
			else:
				var builder:=SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES);builder.append_from(child.mesh,surface,normalized*child.transform);builder.set_material(material);builder.commit(output)
	if id in [1,2,3,4] or id>=301:
		var material:=StandardMaterial3D.new();material.vertex_color_use_as_albedo=true;material.roughness=0.8;tool_surface.set_material(material);tool_surface.commit(output)
	DirAccess.make_dir_recursive_absolute("res://addons/player_runtime/art/drops")
	if ResourceSaver.save(output,"res://addons/player_runtime/art/drops/%d.res"%id)!=OK:push_error("Drop mesh bake failed")

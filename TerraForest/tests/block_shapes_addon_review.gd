extends SceneTree
var output:=""
var native_mode:=false
var failures:=0
func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->void:
	if not condition:failures+=1
	print("PASS " if condition else "FAIL ",label)
func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--shape-review-output="):output=argument.trim_prefix("--shape-review-output=")
		if argument=="--native-reference":native_mode=true
	if output.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	var world:Node3D=ClassDB.instantiate("NativeBlockWorld") if native_mode else load("res://addons/block_shapes/world.gd").new()
	root.add_child(world);world.set_process(false)
	var cells:=PackedInt32Array();var began:=Time.get_ticks_usec()
	for column in 16:
		for height in 16:
			for row in 16:
				if native_mode:cells.append_array(PackedInt32Array([column,height,row,1]))
				else:world.set_block(Vector3i(column,height,row),"cube.full")
	if native_mode:check(world.set_cells(cells),"native reference accepts identical cube cells")
	var authored_us:=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
	if native_mode:world.flush_bakes()
	else:world.flush()
	var initial_us:=Time.get_ticks_usec()-began
	var initial:Dictionary=world.stats() if native_mode else world.statistics()
	var edits:Array[int]=[]
	for cycle in 6:
		began=Time.get_ticks_usec()
		if native_mode:world.set_cells(PackedInt32Array([7,15,7,0 if cycle%2==0 else 1]));world.flush_bakes()
		else:
			if cycle%2==0:world.remove_block(Vector3i(7,15,7))
			else:world.set_block(Vector3i(7,15,7),"cube.full")
			world.flush()
		edits.append(Time.get_ticks_usec()-began)
	var final:Dictionary=world.stats() if native_mode else world.statistics()
	check(int(final.get("cells",final.get("blocks",0)))==4096,"six alternating edits preserve all 4096 final cells")
	var result:Dictionary={"mode":"native_reference" if native_mode else "upstream_addon","author_us":authored_us,"initial_flush_us":initial_us,"edit_flush_us":edits,"initial":initial,"final":final,"scope":"Synchronous 16-cubed solid fill and six alternating boundary-cell edits, collision enabled. Explicit native flush includes waiting for worker completion; not frame-time or general shape performance.","display":DisplayServer.get_name(),"engine":Engine.get_version_info()}
	world.free();await process_frame
	if not native_mode:result["geometry_probes"]=await geometry_probes()
	FileAccess.open(output.path_join("native.json" if native_mode else "addon.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	if not native_mode and DisplayServer.get_name()!="headless":await modular_gallery()
	print("SHAPE_ADDON_REVIEW failures=",failures);quit(1 if failures else 0)
func geometry_probes()->Dictionary:
	var library:RefCounted=load("res://addons/block_shapes/library.gd").new()
	var stage:=Node3D.new();root.add_child(stage)
	var identifiers:Array[String]=["window.t0.125.d0.125","door.t0.125.d0.125","arch.door.t0.125.d0.5"]
	for index in identifiers.size():
		var body:=StaticBody3D.new();var collider:=CollisionShape3D.new();collider.shape=library.create_collision(library.find_shape(identifiers[index]));body.add_child(collider);body.position=Vector3(index*3,0,0);stage.add_child(body)
	for frame in 4:await physics_frame;await process_frame
	for index in identifiers.size():
		for sideways:float in [0.5,0.05]:
			var query:=PhysicsRayQueryParameters3D.create(Vector3(index*3+sideways,0.3,-1),Vector3(index*3+sideways,0.3,2),1)
			var hit:Dictionary=root.world_3d.direct_space_state.intersect_ray(query)
			check(hit.is_empty() if sideways==0.5 else not hit.is_empty(),"physical opening/jamb: "+identifiers[index]+" x="+str(sideways))
	var capsule:=CapsuleShape3D.new();capsule.radius=0.34;capsule.height=1.8
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,Vector3(3.5,.9,.5));query.collision_mask=1
	var frame_obstructs_player:bool=not root.world_3d.direct_space_state.intersect_shape(query,1).is_empty()
	check(frame_obstructs_player,"unit-cell door frame is not a full-height player doorway and needs a multi-cell assembly")
	stage.free();await process_frame
	var pair:Node3D=load("res://addons/block_shapes/world.gd").new();root.add_child(pair);pair.set_process(false)
	pair.set_block(Vector3i.ZERO,"slab.4of8.edge");pair.set_block(Vector3i.RIGHT,"slab.4of8.edge");pair.flush()
	var triangles:int=pair.statistics().triangles
	check(triangles==24,"partial-height neighbor faces remain uncropped in the upstream mesher")
	pair.free();await process_frame
	return {"one_cell_door_frame_obstructs_player":frame_obstructs_player,"adjacent_half_slab_triangles":triangles,"culled_half_slab_target_triangles":20}
func source_gallery()->void:
	var library:RefCounted=load("res://addons/block_shapes/library.gd").new()
	var identifiers:Array[String]=["ramp.h1.w1","panel.r0.5.t0.125.w1","ridge.h0.5.w1","corner.outer.h1","corner.inner.h1","ramp.segment.4.2","arch.door.t0.125.d0.5","window.t0.125.d0.125","door.t0.125.d0.125","beam.0.25.center","corner.trim.t0.125.d0.125","panel.r0.25.t0.0625.w1"]
	var labels:Array[String]=["Full ramp","Thin roof panel","Roof ridge","Outer roof corner","Inner roof corner","Shallow ramp section","Arched opening","Window frame","Door frame","Quarter-width beam","Corner trim","Shallow roof panel"]
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("17232a");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("c6d2da");environment.environment.ambient_light_energy=0.65;stage.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-40,-30,0);light.shadow_enabled=true;stage.add_child(light)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=15.5;camera.position=Vector3(13,16,22);stage.add_child(camera);camera.look_at(Vector3(6,0,4));camera.current=true
	var material:=StandardMaterial3D.new();material.albedo_color=Color("cabf9e");material.roughness=0.9
	var panel_material:=StandardMaterial3D.new();panel_material.albedo_color=Color("597a85");panel_material.roughness=0.9
	for index in identifiers.size():
		var shape:int=library.find_shape(identifiers[index]);check(shape>=0,"review shape exists: "+identifiers[index])
		if shape<0:continue
		var position:=Vector3((index%4)*3.3,0,(index/4)*3.0)
		var platform:=MeshInstance3D.new();var slab:=BoxMesh.new();slab.size=Vector3(2.6,0.08,2.4);platform.mesh=slab;platform.position=position+Vector3(.5,-.08,.5);platform.material_override=panel_material;stage.add_child(platform)
		var mesh:=MeshInstance3D.new();mesh.mesh=library.create_mesh(shape);mesh.position=position;mesh.material_override=material;stage.add_child(mesh)
		var label:=Label3D.new();label.text=str(index+1)+"  "+labels[index];label.font_size=48;label.pixel_size=0.005;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.position=position+Vector3(.5,1.5,.5);label.no_depth_test=true;stage.add_child(label)
	var hud:=CanvasLayer.new();root.add_child(hud)
	var title:=Label.new();title.text="UPSTREAM SOURCE REFERENCE / NOT AN APPROVED BLOCK KIT";title.position=Vector2(32,22);title.add_theme_font_size_override("font_size",28);hud.add_child(title)
	var note:=Label.new();note.text="Actual Godot meshes, one-metre cells. Shape inspection only: no house redesign or world deployment approved.";note.position=Vector2(32,62);note.add_theme_font_size_override("font_size",19);hud.add_child(note)
	for frame in 8:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("shape_gallery.png"))
	camera.position=Vector3(14,12,-12);camera.look_at(Vector3(6,0,4))
	for frame in 8:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("shape_gallery_reverse.png"))
	stage.free();hud.free();await process_frame
func modular_gallery()->void:
	var world:Node3D=load("res://addons/block_shapes/world.gd").new();root.add_child(world);world.set_process(false)
	var library:RefCounted=world.library
	var left:int=library.find_orientation(Basis(Vector3.BACK,-PI/2));var right:int=library.find_orientation(Basis(Vector3.BACK,PI/2));var upside:int=library.find_orientation(Basis(Vector3.BACK,PI));var mirrored:int=library.find_orientation(Basis(Vector3.UP,PI))
	check(left>=0 and right>=0 and upside>=0 and mirrored>=0,"all assembly rotations are grid-preserving quarter turns")
	for color:Color in [Color("c49a66"),Color("628b9a")]:
		var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=0.9;world.materials.append(material)
	var curved:="curve.quarter.t0.125.d1";var straight:="slab.1of8.edge";var corner:="corner.trim.t0.125.d1"
	for base:int in [0,4]:
		world.set_block(Vector3i(base,1,0),curved,mirrored,0);world.set_block(Vector3i(base+1,1,0),curved,0,1)
	world.set_block(Vector3i(4,0,0),straight,left,1);world.set_block(Vector3i(5,0,0),straight,right,0)
	for height in 2:
		world.set_block(Vector3i(8,height,0),straight,left,height%2);world.set_block(Vector3i(9,height,0),straight,right,1-height%2)
	world.set_block(Vector3i(8,2,0),corner,left,0);world.set_block(Vector3i(9,2,0),corner,upside,1)
	world.set_block(Vector3i(12,0,0),corner,0,0);world.set_block(Vector3i(14,0,0),corner,right,0)
	world.set_block(Vector3i(12,2,0),corner,left,0);world.set_block(Vector3i(14,2,0),corner,upside,0)
	world.set_block(Vector3i(13,0,0),straight,0,1);world.set_block(Vector3i(13,2,0),straight,upside,1)
	world.set_block(Vector3i(12,1,0),straight,left,1);world.set_block(Vector3i(14,1,0),straight,right,1)
	world.flush();check(world.statistics().blocks==20,"2 + 4 + 6 + 8 independently stored one-metre building blocks")
	check(world.save_world(output.path_join("assemblies_before.json")),"save stores individual cells, shapes and orientations")
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("17232a");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_energy=0.65;world.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-35,0);light.shadow_enabled=true;world.add_child(light)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.size=17;camera.position=Vector3(8,7,17);world.add_child(camera);camera.look_at(Vector3(7.5,1.3,0.5));camera.current=true
	var grid:=ImmediateMesh.new();grid.surface_begin(Mesh.PRIMITIVE_LINES)
	for block_x in 16:
		grid.surface_add_vertex(Vector3(block_x,0,1.01));grid.surface_add_vertex(Vector3(block_x,3,1.01))
	for block_y in 4:
		grid.surface_add_vertex(Vector3(0,block_y,1.01));grid.surface_add_vertex(Vector3(15,block_y,1.01))
	grid.surface_end();var guide:=MeshInstance3D.new();guide.mesh=grid;var guide_material:=StandardMaterial3D.new();guide_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;guide_material.albedo_color=Color("35505e");guide.material_override=guide_material;world.add_child(guide)
	var names:Array[String]=["2 BLOCKS / ARCH CROWN","4 BLOCKS / ARCHWAY","6 BLOCKS / DOOR FRAME","8 BLOCKS / WINDOW FRAME"]
	for index in names.size():
		var label:=Label3D.new();label.text=names[index];label.font_size=40;label.pixel_size=0.0035;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.position=Vector3(index*4+1,3.65,0.5);label.no_depth_test=true;world.add_child(label)
	var hud:=CanvasLayer.new();root.add_child(hud);var title:=Label.new();title.text="MODULAR BUILDING BLOCKS / ONE-METRE GRID";title.position=Vector2(32,22);title.add_theme_font_size_override("font_size",28);hud.add_child(title)
	var note:=Label.new();note.text="Every coloured piece is its own stored cell. No whole-frame or whole-arch meshes. Component proof only; houses remain unchanged.";note.position=Vector2(32,65);note.add_theme_font_size_override("font_size",18);hud.add_child(note)
	for frame in 8:await physics_frame;await process_frame
	var query:=PhysicsRayQueryParameters3D.create(Vector3(4.35,1.65,3),Vector3(4.35,1.65,-2),1)
	check(not root.world_3d.direct_space_state.intersect_ray(query).is_empty(),"arch segment has its own occupied collision geometry")
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output.path_join("modular_blocks.png"))
	check(world.remove_block(Vector3i(4,1,0)),"remove exactly one arch block by grid coordinate");world.flush()
	check(world.statistics().blocks==19 and world.has_block(Vector3i(5,1,0)) and world.has_block(Vector3i(4,0,0)),"neighbor arch block, jambs and other assemblies survive removal")
	for frame in 4:await physics_frame;await process_frame
	check(root.world_3d.direct_space_state.intersect_ray(query).is_empty(),"removed arch block also disappears from collision")
	check(world.save_world(output.path_join("assemblies_after.json")),"save after removal preserves the other nineteen cells")
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output.path_join("modular_block_removed.png"))
	check(world.load_world(output.path_join("assemblies_before.json")),"individual block assembly restores");world.flush()
	check(world.statistics().blocks==20 and world.has_block(Vector3i(4,1,0)),"restore reconstructs the missing block without replacing an assembly model")
	world.free();hud.free();await process_frame

# SPDX-License-Identifier: 0BSD
extends SceneTree
const Catalog=preload("res://addons/structures/shape_catalog.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var target:="res://addons/player_runtime/art/shape_orientations"
	DirAccess.make_dir_recursive_absolute(target)
	var viewport:=SubViewport.new();viewport.size=Vector2i(192,192);viewport.transparent_bg=true;viewport.own_world_3d=true;viewport.msaa_3d=Viewport.MSAA_4X;root.add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65;viewport.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-35,0);sun.light_energy=1.4;viewport.add_child(sun)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;viewport.add_child(camera);camera.position=Vector3(.5,.5,.5)+Vector3(1.3,.95,2).normalized()*4;camera.look_at(Vector3.ONE*.5);camera.size=1.9;camera.current=true
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld");viewport.add_child(blocks);blocks.set_process(false)
	var model:=MeshInstance3D.new();viewport.add_child(model)
	var material:=StandardMaterial3D.new();material.albedo_color=Color("a9c8c0");material.roughness=.8;model.material_override=material
	var receipt:={"license":"CC0-1.0","source":"Original native block geometry; tools/bake_shape_orientations.gd","native_sha256":FileAccess.get_sha256("res://addons/structures/bin/structures.windows.template_debug.x86_64.dll"),"assets":{}}
	for shape in range(1,Catalog.NAMES.size()+1):
		var atlas:=Image.create(384,256,false,Image.FORMAT_RGBA8);atlas.fill(Color.TRANSPARENT)
		for rotation in Catalog.rotation_count(shape):
			model.mesh=blocks.preview_mesh(shape,rotation)
			viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
			for frame in 2:await RenderingServer.frame_post_draw
			var pixels:=viewport.get_texture().get_image();pixels.resize(64,64,Image.INTERPOLATE_LANCZOS)
			if pixels.get_used_rect().size==Vector2i.ZERO:push_error("Empty orientation thumbnail");quit(1);return
			atlas.blit_rect(pixels,Rect2i(0,0,64,64),Vector2i((rotation%6)*64,(rotation/6)*64))
		var path:=target+"/shape_%02d.trtex"%shape
		if atlas.save_png(path)!=OK:quit(1);return
		receipt.assets[path]=FileAccess.get_sha256(path)
	FileAccess.open(target+"/provenance.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"  ")+"\n")
	viewport.free();print("SHAPE_ORIENTATIONS count=",Catalog.NAMES.size()," failures=0");quit()

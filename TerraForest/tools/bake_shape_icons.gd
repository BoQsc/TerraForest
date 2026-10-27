extends SceneTree

const Cache=preload("res://tools/shape_icon_cache.gd")
const Icons=preload("res://addons/player_runtime/shape_icons.gd")

func _initialize()->void:run.call_deferred()
func run()->void:
	var state:=Cache.snapshot()
	var viewport:=SubViewport.new();viewport.size=Vector2i(512,512);viewport.transparent_bg=true;viewport.own_world_3d=true;viewport.msaa_3d=Viewport.MSAA_4X;root.add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65;viewport.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-35,0);sun.light_energy=1.4;viewport.add_child(sun)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;viewport.add_child(camera);camera.current=true
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld");viewport.add_child(blocks);blocks.set_process(false)
	var model:=MeshInstance3D.new();viewport.add_child(model)
	var material:=StandardMaterial3D.new();material.albedo_color=Color("a9c8c0");material.roughness=.8;model.material_override=material
	var atlas:=Image.create(Icons.COLUMNS*Icons.TILE,ceili(Icons.Catalog.NAMES.size()/float(Icons.COLUMNS))*Icons.TILE,false,Image.FORMAT_RGBA8);atlas.fill(Color.TRANSPARENT)
	for shape in range(1,Icons.Catalog.NAMES.size()+1):
		model.mesh=blocks.preview_mesh(shape,0)
		if model.mesh==null:viewport.free();push_error("Missing native shape mesh: "+str(shape));quit(1);return
		var bounds:=model.mesh.get_aabb();var center:=bounds.get_center()
		camera.position=center+Vector3(1.3,.95,2).normalized()*4;camera.look_at(center);camera.size=maxf(.1,bounds.size.length()*1.1)
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		for frame in 3:await RenderingServer.frame_post_draw
		var pixels:=viewport.get_texture().get_image();pixels.resize(Icons.TILE,Icons.TILE,Image.INTERPOLATE_LANCZOS)
		if pixels.get_used_rect().size==Vector2i.ZERO:viewport.free();push_error("Empty native shape icon: "+str(shape));quit(1);return
		atlas.blit_rect(pixels,Rect2i(0,0,Icons.TILE,Icons.TILE),Vector2i(((shape-1)%Icons.COLUMNS)*Icons.TILE,((shape-1)/Icons.COLUMNS)*Icons.TILE))
	var error:=Cache.publish(atlas,state)
	viewport.free();print("SHAPE_ICONS count=",Icons.Catalog.NAMES.size()," failures=",0 if error==OK else 1);quit(0 if error==OK else 1)

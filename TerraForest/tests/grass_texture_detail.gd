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
func run() -> void:
	Engine.max_fps=60
	var world:=Node3D.new();root.add_child(world)
	var camera:=Camera3D.new();world.add_child(camera);camera.current=true
	camera.position=Vector3(0.8,0.65,1.4);camera.look_at(Vector3(0,0.22,0));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=0.9
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color.BLACK;env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=0.65;world.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-30,0);world.add_child(light)
	var mesh:=Asset.build(2);var material: ShaderMaterial=mesh.surface_get_material(0);material.set_shader_parameter("wind_strength",0.0)
	var item:=MeshInstance3D.new();item.mesh=mesh;world.add_child(item)
	var images: Array[Image]=[]
	DirAccess.make_dir_recursive_absolute("res://reports/grass_texture_detail")
	for enabled in [false,true,false]:
		check(Asset.set_grass_detail(material,enabled),"optional texture loads and toggles")
		for i in 15:await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.save_png("res://reports/grass_texture_detail/view_%d.png"%images.size());images.append(image)
	var total_off:=0.0;var total_on:=0.0;var difference:=0.0;var count:=0
	for y in range(0,1080,4):
		for x in range(0,1920,4):
			var a: Color=images[0].get_pixel(x,y).srgb_to_linear();var b: Color=images[1].get_pixel(x,y).srgb_to_linear()
			var off: float=a.r*0.2126+a.g*0.7152+a.b*0.0722
			if off<0.005:continue
			var on: float=b.r*0.2126+b.g*0.7152+b.b*0.0722
			total_off+=off;total_on+=on;difference+=absf(off-on);count+=1
	var ratio: float=total_on/maxf(total_off,0.00001)
	var variation: float=difference/maxf(total_off,0.00001)
	check(count>1000 and ratio>0.78 and ratio<1.03,"dark tones remain within the bounded art-review range")
	var residual:=0.0
	for y in range(0,1080,4):
		for x in range(0,1920,4):
			var a: Color=images[0].get_pixel(x,y).srgb_to_linear();var b: Color=images[1].get_pixel(x,y).srgb_to_linear()
			var off: float=a.r*0.2126+a.g*0.7152+a.b*0.0722
			if off<0.005:continue
			var on: float=b.r*0.2126+b.g*0.7152+b.b*0.0722
			residual+=absf(on-off*ratio)
	residual/=maxf(total_off,0.00001)
	check(residual>0.025,"texture adds local detail beyond uniform darkening")
	check(variation>0.05,"leaf variation is visibly stronger than uniform tint")
	check(images[0].get_data()==images[2].get_data(),"off restores exact original pixels")
	check(root.size==Vector2i(1920,1080) and DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN],"fullscreen1080p")
	var result:={"checks":checks,"failures":failures,"linear_brightness_ratio":ratio,"variation_after_brightness_removed":residual,"relative_absolute_difference":variation,"sampled_foreground_pixels":count,"scope":"Static close-up appearance test, not a world GPU or thermal benchmark"}
	var file:=FileAccess.open("res://reports/grass_texture_detail/result.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	world.free();await process_frame
	print("GRASS_TEXTURE_DETAIL ",JSON.stringify(result));quit(1 if failures else 0)

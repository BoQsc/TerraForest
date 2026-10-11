# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize():run.call_deferred()
func run():
 var viewport:=SubViewport.new();viewport.size=Vector2i(256,256);viewport.transparent_bg=true;viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.msaa_3d=Viewport.MSAA_4X;root.add_child(viewport)
 var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.7;viewport.add_child(environment)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-35,0);sun.light_energy=1.6;viewport.add_child(sun)
 var item:=MeshInstance3D.new();item.mesh=preload("res://addons/volumetric_water/bucket_model.gd").mesh();viewport.add_child(item)
 var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;viewport.add_child(camera);camera.current=true;camera.position=Vector3(0.5,0.4,0.8);camera.look_at(Vector3(0,0.05,0));camera.size=0.52
 for i in 3:await RenderingServer.frame_post_draw
 var image:=viewport.get_texture().get_image();image.resize(128,128,Image.INTERPOLATE_LANCZOS)
 var error:=image.save_png("res://addons/volumetric_water/bucket_icon.trtex")
 viewport.free();print("BUCKET_ICON failures=",int(error!=OK));quit(int(error!=OK))

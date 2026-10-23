# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run():
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
 if not await wait_for(func():return not game.loading_active,60):failures+=1;await done();return
 game.set_physics_process(false);game._clear_motion()
 game.camera.position=Vector3(0,20,0);game.camera.rotation.x=-.12
 for i in 180:await process_frame
 var canopy=game.get_node("CanopyShadows");canopy.set_process(false)
 var viewport=root.get_viewport_rid();RenderingServer.viewport_set_measure_render_time(viewport,true)
 DirAccess.make_dir_recursive_absolute("res://reports/canopy_shadows")
 for enabled in [false,true,false,true]:
  game.terrain_material.set_shader_parameter("canopy_enabled",enabled)
  for i in 30:await process_frame
  var gpu=[]
  for i in 90:
   await process_frame
   gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
  gpu.sort()
  print("CANOPY_RENDER enabled=",enabled," gpu_median=",gpu[45]," gpu_p95=",gpu[85]," roots=",game.vegetation.renderer.roots.size()," native_max_us=",canopy.max_native_us)
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/canopy_shadows/"+("on" if enabled else "off")+".png")
 check(canopy.rebuilds>0 and canopy.texture!=null,"native canopy mask active")
 await done()
func done():
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
 print("CANOPY_SHADOW_REVIEW failures=",failures);quit(1 if failures else 0)

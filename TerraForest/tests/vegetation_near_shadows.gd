# SPDX-License-Identifier: 0BSD
extends "res://tests/southern_vegetation.gd"
func run()->void:
 DirAccess.make_dir_recursive_absolute("res://reports/vegetation_near_shadows")
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.max_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"world ready"):await done();return
 var center:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator).sites[4].position
 game.teleport(center+Vector3(28,0,32))
 if not check(await wait_for(func():return not game.loading_active,45),"arrival ready"):await done();return
 game.set_physics_process(false);game._clear_motion()
 if not check(await wait_for(settled,20),"cover ready"):await done();return
 var foot:Vector3=center+Vector3(28,0,32)
 await wait_for(func():return not game._terrain_pick(foot+Vector3.UP*12,foot-Vector3.UP*12).is_empty(),8)
 var hit:Dictionary=game._terrain_pick(foot+Vector3.UP*12,foot-Vector3.UP*12)
 if not check(not hit.is_empty(),"ground hit"):await done();return
 game.camera.global_position=hit.position+Vector3.UP*1.7
 game.camera.look_at(hit.position+Vector3(-1,0,-3))
 for material in game.ground_cover.foliage_materials:material.set_shader_parameter("wind_strength",0.0)
 print("SHADOW_BASE ",game.sun.directional_shadow_mode," splits ",game.sun.directional_shadow_split_1," ",game.sun.directional_shadow_split_2," ",game.sun.directional_shadow_split_3)
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 check(is_equal_approx(game.sun.directional_shadow_split_1,0.035) and game.sun.directional_shadow_blend_splits and ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")==4096,"production near-shadow configuration")
 var results:Array=[]
 for variant in ["baseline","focused","focused_low_bias","focused_4096"]:
  if variant=="baseline":
   RenderingServer.directional_shadow_atlas_set_size(2048,false)
   game.sun.directional_shadow_split_1=0.1
   game.sun.directional_shadow_split_2=0.2
   game.sun.directional_shadow_split_3=0.5
   game.sun.directional_shadow_blend_splits=false
  if variant!="baseline":
   game.sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
   game.sun.directional_shadow_split_1=0.035
   game.sun.directional_shadow_split_2=0.12
   game.sun.directional_shadow_split_3=0.35
   game.sun.directional_shadow_blend_splits=true
  if variant=="focused_low_bias":game.sun.shadow_normal_bias=0.7
  if variant=="focused_4096":
   game.sun.shadow_normal_bias=2.0
   RenderingServer.directional_shadow_atlas_set_size(4096,false)
  for frame in 45:await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/vegetation_near_shadows/"+variant+".png")
  for frame in 30:await RenderingServer.frame_post_draw
  var gpu:Array=[]
  for frame in 60:
   await RenderingServer.frame_post_draw
   gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
  gpu.sort();results.append({"variant":variant,"gpu_median":gpu[30]})
 check(game.ground_cover.rejected_batches==0,"no rejected cover")
 FileAccess.open("res://reports/vegetation_near_shadows/result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"phases":results},"  "))
 await done()

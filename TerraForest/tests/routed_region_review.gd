# SPDX-License-Identifier: 0BSD
extends "res://tests/village_shop_review.gd"
func run()->void:
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await ready_world(game):quit(1);return
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 var selected:PackedVector3Array=layout.roads[0].points;var station:=12;var largest:=-1.0
 for road:Dictionary in layout.roads:
  var points:PackedVector3Array=road.points;var axis:Vector3=points[-1]-points[0];axis.y=0;axis=axis.normalized()
  for i in range(5,20):
   var deviation:float=absf((points[i]-points[0]).dot(Vector3(-axis.z,0,axis.x)))
   if deviation>largest:largest=deviation;selected=points;station=i
 var bend:Vector3=selected[station]
 game.teleport(bend+Vector3.UP*2)
 if not await ready_world(game):quit(1);return
 game.set_physics_process(false);game._clear_motion()
 for row:Dictionary in [{"name":"overview","position":bend+Vector3(85,65,65),"target":bend},{"name":"ground","position":bend+Vector3.UP*1.7,"target":selected[station+2]+Vector3.UP}]:
  game.camera.global_position=row.position;game.camera.look_at(row.target)
  for i in 120:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/routed_region_"+row.name+".png")
 game.app_focused=true;game.world_map.set_open(true);game.world_map.view.overview()
 var deadline:int=Time.get_ticks_msec()+30000
 while game.world_map.texture==null and Time.get_ticks_msec()<deadline:await process_frame
 if game.world_map.texture==null:quit(1);return
 await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/routed_region_map.png")
 print("ROUTED_REGION_REVIEW failures=0 deviation=",largest)
 game.free();quit()

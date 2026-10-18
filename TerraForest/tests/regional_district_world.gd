# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+90000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 if game.loading_active:quit(1);return
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 var counts:=[0,0,0,0,0]
 for id:int in game.doors.collection.get_ids():
  var pose:PackedFloat32Array=game.doors.collection.get_instance(id)
  var position:=Vector3(pose[3],pose[7],pose[11])
  for site:Dictionary in layout.sites:
   if Vector2(position.x-site.position.x,position.z-site.position.z).length()<120:counts[site.id]+=1
 var ok:bool=counts==[8,5,2,4,4]
 for index in [3,4]:
  var center:Vector3=layout.sites[index].position
  game.teleport(center+Vector3(25,0,-30))
  deadline=Time.get_ticks_msec()+60000
  while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
  ok=ok and not game.loading_active
  game.set_physics_process(false);game._clear_motion()
  game.camera.global_position=center+Vector3(28,25,-30);game.camera.look_at(center+Vector3(-30,5,-35))
  for frame in 90:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/regional_district_%d.png"%index)
 print("REGIONAL_DISTRICT_WORLD failures=",0 if ok else 1," buildings_by_site=",counts)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(0 if ok else 1)

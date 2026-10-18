# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+90000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 if game.loading_active:quit(1);return
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 var center:Vector3=layout.sites[4].position
 game.teleport(center+Vector3(25,0,-30))
 deadline=Time.get_ticks_msec()+60000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 if game.loading_active:quit(1);return
 game.set_physics_process(false);game._clear_motion()
 var found:=false
 for id:int in game.doors.collection.get_ids():
  var pose:PackedFloat32Array=game.doors.collection.get_instance(id)
  var at:=Vector3(pose[3],pose[7],pose[11])
  if Vector2(at.x-center.x,at.z-center.z).length()>100:continue
  var forward:=Vector3(pose[2],pose[6],pose[10]).normalized()
  var right:=Vector3(pose[0],pose[4],pose[8]).normalized()
  game.camera.global_position=at+forward*13+right*3+Vector3.UP*5
  game.camera.look_at(at+forward*3-Vector3.UP)
  found=true;break
 for frame in 150:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/regional_entrance_view.png")
 print("REGIONAL_ENTRANCE_VIEW failures=",0 if found else 1)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(0 if found else 1)

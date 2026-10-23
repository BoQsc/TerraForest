# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func _initialize():run.call_deferred()
func run():
 var game=load("res://demo/world.tscn").instantiate()
 game.temporary_world=true;game.lakes.offline_preparation=true;game.background_fps=60
 root.add_child(game)
 var end=Time.get_ticks_msec()+45000
 while Time.get_ticks_msec()<end and (game.loading_active or game.lakes.statistics().ready<4):await process_frame
 game.set_physics_process(false);game._clear_motion()
 for record in game.lakes._lakes.values():
  if record.dirty or not record.failure.is_empty() or game.lakes.depth_at(record.seed)<=0:failures+=1
 print("GENERATED_BASINS ",game.lakes.statistics())
 DirAccess.make_dir_recursive_absolute("res://reports/generated_basins")
 if failures==0:
  for id in [1,3]:
   var record=game.lakes._lakes[id]
   var target:Vector3=record.seed;target.y=record.level
   var position=target+Vector3(35,25,35)
   game.teleport(position,position.y)
   end=Time.get_ticks_msec()+15000
   while Time.get_ticks_msec()<end and game.loading_active:await process_frame
   game.set_physics_process(false);game._clear_motion();game.camera.global_position=position;game.camera.look_at(target)
   for i in 90:await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://reports/generated_basins/lake_%d.png"%id)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
 print("GENERATED_BASIN_REVIEW failures=",failures);quit(1 if failures else 0)

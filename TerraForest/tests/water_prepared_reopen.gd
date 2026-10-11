# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize():run.call_deferred()
func run():
 var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 game.background_fps=60;game.max_fps=60
 var deadline:=Time.get_ticks_msec()+20000
 while (game.loading_active or not game.terrain.world_ready) and Time.get_ticks_msec()<deadline:await process_frame
 var s:Dictionary=game.lakes.statistics()
 var ok:bool=not game.loading_active and s.lakes>0 and s.cache_hits>0 and s.sampled_nodes==0 and s.cached_region_rebuilds==0 and s.active_cells==0 and s.render_ready
 print("PREPARED_REOPEN ",JSON.stringify(s))
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/water_prepared_reopen.png")
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("PREPARED_REOPEN failures=",int(not ok));quit(int(not ok))

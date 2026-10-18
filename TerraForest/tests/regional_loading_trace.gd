# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
 if "--snapshot-readonly" not in OS.get_cmdline_user_args():quit(2);return
 var began:=Time.get_ticks_msec()
 var game=load("res://demo/world.tscn").instantiate()
 var compare:bool="--loading-cap-comparison" in OS.get_cmdline_user_args()
 game.max_fps=15 if compare else 60;game.background_fps=game.max_fps
 root.add_child(game)
 var next_report:=0
 while game.loading_active and Time.get_ticks_msec()-began<60000:
  if compare and Time.get_ticks_msec()-began>15000 and game.background_fps==15:
   game.max_fps=60;game.background_fps=60;Engine.max_fps=60
   print("LOADING_CAP_CHANGED 15 -> 60")
  if Time.get_ticks_msec()>=next_report:
   print("LOADING_TRACE ",JSON.stringify({"ms":Time.get_ticks_msec()-began,"fps_cap":Engine.max_fps,"fps":Engine.get_frames_per_second(),"terrain":game.terrain.loading_state(game.player.position,game.fly),"water":game.lakes.statistics(),"spawn":game.waiting_spawn,"position":game.player.position,"label":game.loading_label.text}))
   next_report=Time.get_ticks_msec()+5000
  await process_frame
 var failed:bool=game.loading_active
 print("LOADING_TRACE_END ",JSON.stringify({"ms":Time.get_ticks_msec()-began,"terrain":game.terrain.loading_state(game.player.position,game.fly),"water":game.lakes.statistics(),"spawn":game.waiting_spawn,"position":game.player.position,"label":game.loading_label.text}))
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
 print("REGIONAL_LOADING_TRACE failures=",1 if failed else 0);quit(1 if failed else 0)

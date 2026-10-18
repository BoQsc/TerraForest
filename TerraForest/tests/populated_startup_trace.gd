# SPDX-License-Identifier: 0BSD
extends SceneTree
var game: Node
var maxima: Dictionary={}
func _initialize()->void:run.call_deferred()
func run()->void:
 var safe:=false
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--world-slot=startup_trace_"):safe=true
 if not safe:quit(2);return
 game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 game.terrain.stage_measured.connect(func(label: String,ms: float):maxima[label]=maxf(float(maxima.get(label,0)),ms))
 var deadline:=Time.get_ticks_msec()+45000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 var ready: bool=not game.loading_active
 for frame in 120:await process_frame
 print("STARTUP_STAGE_MAXIMA ",JSON.stringify(maxima))
 print("STARTUP_RESIDENTS ",game.actors.store.statistics().active)
 game.shutdown_requested=true;game._close_journal();game.terrain.shutdown();game.free();await process_frame
 print("POPULATED_STARTUP_TRACE failures=",0 if ready else 1)
 quit(0 if ready else 1)

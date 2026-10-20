# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
 var report:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--prepare-report="):report=arg.trim_prefix("--prepare-report=")
 if report.is_empty() or not "--snapshot-readonly" in OS.get_cmdline_user_args():quit(2);return
 var game=load("res://demo/world.tscn").instantiate();game.max_fps=60;game.background_fps=60;root.add_child(game)
 game.set_physics_process(false);game.set_process_unhandled_input(false);game._clear_motion()
 var began:=Time.get_ticks_msec();var deadline:=began+90000;var stable:=0
 while Time.get_ticks_msec()<deadline:
  if not game.terrain.latest_error.is_empty():break
  if not game.loading_active and game.terrain.world_ready and not game.terrain.pending_edit and game.terrain.backend.queued()==0 and game.terrain.backend.status()=="idle":stable+=1
  else:stable=0
  if stable>=12:break
  await process_frame
 var ready:bool=stable>=12 and game.terrain.backend.readonly_snapshot
 var data:Dictionary={"ready":ready,"slot":game.terrain.save_slot,"cache_path":game.terrain.backend.cache_path,"elapsed_ms":Time.get_ticks_msec()-began,"cache":game.terrain.derived_metrics.duplicate(true),"scope":"Saved spawn focus and ordinary terrain coverage; not an entire-world bake or a performance qualification."}
 var map_worker:=Thread.new()
 var map_job:=preload("res://addons/world_runtime/survey_cache.gd").prepare.bind(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 if ready and map_worker.start(map_job)==OK:
  while map_worker.is_alive():await process_frame
  data["cartography"]=map_worker.wait_to_finish()
  ready=ready and data.cartography.get("ok",false)
 else:ready=false
 data.ready=ready
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits()
 data.cache=game.terrain.backend.disk_cache.counters()
 var file:=FileAccess.open(report,FileAccess.WRITE);file.store_string(JSON.stringify(data,"  "));file.close()
 game.free();await process_frame
 print("WORLD_CACHE_PREPARATION failures=",0 if ready else 1);quit(0 if ready else 1)

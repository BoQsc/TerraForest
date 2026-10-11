# SPDX-License-Identifier: 0BSD
extends SceneTree
# Runs the real game scene and normal save path, with input disabled.
# Prepares the spawn area, not an unbounded entire-world bake.
func _initialize():run.call_deferred()
func run():
 var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 game.background_fps=60;game.max_fps=60
 var deadline:=Time.get_ticks_msec()+90000
 var stable:=0
 while Time.get_ticks_msec()<deadline:
  var water:Dictionary=game.lakes.statistics()
  if not game.loading_active and game.terrain.world_ready and not game.terrain.pending_edit and water.lakes>0 and water.ready==water.lakes and water.render_ready and water.active_cells==0 and game.terrain.backend.queued()==0 and game.terrain.backend.status()=="idle":stable+=1
  else:stable=0
  if stable>=12:break
  await process_frame
 if stable<12:
  printerr("Preparation did not reach a settled spawn area; existing saved data retained. ",game.lakes.statistics())
  game.terrain.shutdown();game.queue_free();await process_frame;quit(1);return
 var saved:Array=[false]
 game.terrain.message_changed.connect(func(message:String):
  if message.begins_with("World saved and verified"):saved[0]=true)
 game.terrain.save_world();deadline=Time.get_ticks_msec()+15000
 while not saved[0] and Time.get_ticks_msec()<deadline:await process_frame
 print("PREPARED_WATER_WORLD ",JSON.stringify({"saved":saved[0],"water":game.lakes.statistics(),"path":game.terrain.backend.save_path}))
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 quit(0 if saved[0] else 1)

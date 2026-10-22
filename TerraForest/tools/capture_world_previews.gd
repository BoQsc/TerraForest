# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func ready_world(game:Node)->bool:
 var deadline:=Time.get_ticks_msec()+90000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 return not game.loading_active
func run()->void:
 if not "--snapshot-readonly" in OS.get_cmdline_user_args():quit(2);return
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
 if not await ready_world(game):quit(1);return
 var plan:Dictionary=game.generated_region.store.get_plan()
 var places:Array=plan.get("places",[])
 if places.is_empty():game.free();quit(1);return
 var directory:String="user://worlds/"+game.terrain.save_slot+".preview"
 DirAccess.make_dir_recursive_absolute(directory)
 var failures:=0
 var rng:=RandomNumberGenerator.new();rng.seed=game.terrain.backend.world_seed
 for i in 3:
  var place:Dictionary=places[i%places.size()]
  var target:Vector3=place.position
  game.teleport(target)
  if not await ready_world(game):failures+=1;break
  game.set_physics_process(false);game._clear_motion()
  var angle:=rng.randf_range(0,TAU)
  game.camera.global_position=target+Vector3(cos(angle)*28,18,sin(angle)*28)
  game.camera.look_at(target+Vector3.UP*2)
  for frame in 45:await process_frame
  var path:=directory.path_join(["north","road","market"][i]+".png")
  if await preload("res://addons/world_runtime/world_presentation.gd").capture(game,root,path)!=OK:failures+=1
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
 print("WORLD_PREVIEWS failures=",failures);quit(1 if failures else 0)

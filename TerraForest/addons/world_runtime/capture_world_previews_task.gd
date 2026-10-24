# SPDX-License-Identifier: 0BSD
extends "res://addons/world_runtime/scene_task.gd"
var game:Node
var completed_views:=0
func diagnostics()->Dictionary:
 return preload("res://addons/world_runtime/loading_diagnostics.gd").snapshot(game) if is_instance_valid(game) else {}
func _initialize()->void:run.call_deferred()
func ready_world(game:Node)->bool:
 var deadline:=Time.get_ticks_msec()+90000;var next_poll:=0
 while game.loading_active and Time.get_ticks_msec()<deadline and not cancelled():
  if Time.get_ticks_msec()>=next_poll:
   next_poll=Time.get_ticks_msec()+250
   progress_changed.emit("Photographing the generated world",completed_views,3,{"activity":"Photograph %d / 3 · %s"%[completed_views+1,game.loading_stage_text],"work":game.loading_work_text,"stage_fraction":(completed_views+.7*game.loading_stage_percent/100.0)/3.0})
  await process_frame
 return not game.loading_active
func run()->void:
 if not "--snapshot-readonly" in PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args())):quit(2);return
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await ready_world(game):quit(1);return
 var plan:Dictionary=game.generated_region.store.get_plan()
 var places:Array=plan.get("places",[])
 if places.is_empty():
  # Older worlds have no generated-place catalog. Photograph their saved arrival
  # from three angles rather than inventing unrelated locations.
  places=[{"position":game.player.global_position}]
 var directory:String="user://worlds/"+game.terrain.save_slot+".preview"
 DirAccess.make_dir_recursive_absolute(directory)
 var failures:=0
 var rng:=RandomNumberGenerator.new();rng.seed=game.terrain.backend.world_seed
 for i in 3:
  completed_views=i
  if cancelled():break
  progress_changed.emit("Loading photograph destination",i,3,{"activity":"Photograph %d / 3 · Loading terrain and landscape"%(i+1)})
  var place:Dictionary=places[i%places.size()]
  var target:Vector3=place.position
  game.teleport(target)
  if not await ready_world(game):failures+=1;break
  game.set_physics_process(false);game._clear_motion()
  var angle:=rng.randf_range(0,TAU)
  game.camera.global_position=target+Vector3(cos(angle)*28,18,sin(angle)*28)
  game.camera.look_at(target+Vector3.UP*2)
  for frame in 45:await process_frame
  if cancelled():break
  progress_changed.emit("Saving world photograph",i,3,{"activity":"Photograph %d / 3 · Capturing and encoding image"%(i+1)})
  var path:=directory.path_join(["north","road","market"][i]+".png")
  if await preload("res://addons/world_runtime/world_presentation.gd").capture(game,root,path)!=OK:failures+=1
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();game=null
 if cancelled():print("WORLD_PREVIEWS cancelled");quit(2);return
 progress_changed.emit("World photographs ready",3,3,{})
 print("WORLD_PREVIEWS failures=",failures);quit(1 if failures else 0)

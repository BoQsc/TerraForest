extends SceneTree
var failures:=0
func check(condition:bool,message:String)->void:
 if not condition:failures+=1
 print("PASS " if condition else "FAIL ",message)
func _initialize()->void:run.call_deferred()
func wait_for(condition:Callable,seconds:int)->bool:
 var deadline:=Time.get_ticks_msec()+seconds*1000
 while not condition.call() and Time.get_ticks_msec()<deadline:await process_frame
 return condition.call()
func run()->void:
 var slot:=""
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--world-slot="):slot=argument.trim_prefix("--world-slot=")
 if not preload("res://demo/world_launch.gd").valid_slot(slot) or not "--snapshot-readonly" in OS.get_cmdline_user_args():quit(2);return
 var path:="user://worlds/"+slot+".trw";var before:=FileAccess.get_sha256(path)
 var options:Dictionary={"biome":1,"settlements":3,"districts":2,"network":1,"trails":2}
 var expected:=preload("res://addons/world_runtime/world_recipe.gd").encode(options)
 var rows:Array=[]
 for pass_index in 2:
  var started:=Time.get_ticks_msec()
  var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
  var ready:=await wait_for(func():return not game.loading_active,120)
  check(ready,"custom world becomes playable")
  if not ready:game.free();break
  game.set_physics_process(false);game._clear_motion()
  check(game.world_recipe.store.capture_snapshot()==expected and game.ecosystem.biome_profile==1,"saved custom biome restores in packaged runtime")
  check(game.generated_region.describe(1703,21).get("places",[]).size()==6,"all custom districts restore")
  game.world_map.set_open(true)
  var atlas:Node=game.world_map
  var observation:Dictionary={"next":Time.get_ticks_msec()+5000}
  var complete:=await wait_for(func():
   if Time.get_ticks_msec()>=observation.next:
    observation.next=Time.get_ticks_msec()+5000
    print("MAP_REOPEN_PROGRESS ",{"opened":atlas.opened,"terrain_dirty":atlas.updates.dirty.size(),"terrain_pending":atlas.updates.pending,"terrain_identity":atlas.updates.cache_identity,"terrain_patches":atlas.updates.patches,"blocks_complete":atlas.block_survey.complete,"blocks_pending":atlas.block_survey.pending,"blocks_offset":atlas.block_survey.offset,"models_complete":atlas.model_survey.complete,"models_pending":atlas.model_survey.pending,"water_complete":atlas.water_survey.complete,"water_pending":atlas.water_survey.pending})
   if atlas.updates.image==null or not atlas.updates.dirty.is_empty() or not atlas.updates.pending.is_empty() or atlas.updates.io!=null:return false
   for layer:Node in [atlas.water_survey,atlas.block_survey,atlas.model_survey]:
    if not layer.complete or layer.io!=null:return false
   return true,180)
  check(complete,"all world map layers finish")
  var metrics:Dictionary={"pass":pass_index,"complete":complete,"milliseconds":Time.get_ticks_msec()-started,"terrain_hits":atlas.updates.cache_hits,"terrain_writes":atlas.updates.cache_writes,"terrain_patches":atlas.updates.patches,"water_hits":atlas.water_survey.cache_hits,"blocks_hits":atlas.block_survey.cache_hits,"models_hits":atlas.model_survey.cache_hits}
  if pass_index==1:check(metrics.terrain_hits>0 and metrics.water_hits>0 and metrics.blocks_hits>0 and metrics.models_hits>0,"warm packaged reload reuses all four world map layers")
  rows.append(metrics)
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/world_recipe_reopen_%d.png"%pass_index)
  game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
 check(FileAccess.get_sha256(path)==before,"read-only checks leave canonical world unchanged")
 FileAccess.open("res://reports/world_recipe_reopen.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"slot":slot,"passes":rows},"  "))
 print("WORLD_RECIPE_REOPEN failures=",failures);quit(1 if failures else 0)

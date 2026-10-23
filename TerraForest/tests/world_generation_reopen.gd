# SPDX-License-Identifier: 0BSD
extends SceneTree
const Launch=preload("res://demo/world_launch.gd")
func _initialize()->void:run.call_deferred()
func wait_until(condition:Callable,seconds:int)->bool:
 var deadline:=Time.get_ticks_msec()+seconds*1000
 while not condition.call() and Time.get_ticks_msec()<deadline:await process_frame
 return condition.call()
func run()->void:
 var slot:=""
 var expected_seed:=1703;var expected_generator:=19
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--review-world="):slot=arg.trim_prefix("--review-world=")
  if arg.begins_with("--case-seed="):expected_seed=int(arg.trim_prefix("--case-seed="))
  if arg.begins_with("--case-generator="):expected_generator=int(arg.trim_prefix("--case-generator="))
 if not Launch.valid_slot(slot):quit(2);return
 if not "--reopen-child" in OS.get_cmdline_user_args():
  var path:="user://worlds/"+slot+".trw";var before:=FileAccess.get_sha256(path)
  var args:=Launch.engine_prefix()+PackedStringArray(["--fullscreen","--resolution","1920x1080","--max-fps","60","--log-file",ProjectSettings.globalize_path("res://reports/world_generation_reopen.log"),"--script","res://tests/world_generation_reopen.gd","--","--reopen-child","--review-world="+slot,"--world-slot="+slot,"--case-seed="+str(expected_seed),"--case-generator="+str(expected_generator),"--snapshot-readonly","--ground-cover","--actors","--vehicle-fleet","--gameplay-construction"])
  var pid:=OS.create_process(OS.get_executable_path(),args,false)
  var finished:bool=pid>=0 and await wait_until(func():return not OS.is_process_running(pid),90)
  if not finished and pid>=0:OS.kill(pid)
  var code:=OS.get_process_exit_code(pid) if finished else -1
  var ok:=finished and code==0 and FileAccess.get_sha256(path)==before
  print("WORLD_GENERATION_REOPEN failures=",0 if ok else 1);quit(0 if ok else 1);return
 var began:=Time.get_ticks_msec()
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 var ready:bool=await wait_until(func():return not game.loading_active,70)
 var failures:=0
 var map_profile:Dictionary={}
 if not ready or root.size!=Vector2i(1920,1080):failures+=1
 if ready:
  game.set_physics_process(false);game._clear_motion()
  if game.generated_region.describe(expected_seed,expected_generator).get("places",[]).size()!=2 or not game.construction_inventory.gameplay:failures+=1
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/world_generation_reopen.png")
  game.world_map.set_open(true)
  var atlas:Node=game.world_map
  var cached:bool=await wait_until(func():
   if atlas.updates.image==null or not atlas.updates.dirty.is_empty() or not atlas.updates.pending.is_empty() or atlas.updates.io!=null:return false
   for layer:Node in [atlas.water_survey,atlas.block_survey,atlas.model_survey]:
    if not layer.complete or layer.io!=null:return false
   return true,20)
  map_profile={"ready":cached,"terrain_hits":atlas.updates.cache_hits,"terrain_patches":atlas.updates.patches,"water_hits":atlas.water_survey.cache_hits,"blocks_hits":atlas.block_survey.cache_hits,"models_hits":atlas.model_survey.cache_hits}
  if not cached or map_profile.terrain_hits==0 or map_profile.water_hits==0 or map_profile.blocks_hits==0 or map_profile.models_hits==0:failures+=1
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/world_generation_reopen_map.png")
 var result:={"failures":failures,"slot":slot,"ready":ready,"map":map_profile,"load_milliseconds":Time.get_ticks_msec()-began,"root_size":str(root.size),"scope":"Fresh full game opens a generated published world read-only, with normal paid gameplay, native region restore and all baked map layers hitting cache. Not sustained performance qualification."}
 FileAccess.open("res://reports/world_generation_reopen.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 game.shutdown_requested=true;game.terrain.backend.disable_snapshot_writes();await game.terrain.shutdown_after_edits();game.free()
 print("WORLD_GENERATION_REOPEN_CHILD failures=",failures);quit(1 if failures else 0)

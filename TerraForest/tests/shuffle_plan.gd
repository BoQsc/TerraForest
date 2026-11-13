# SPDX-License-Identifier: 0BSD
extends SceneTree
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const Launch=preload("res://demo/world_launch.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
 var failures:=0
 var generator:int=Launch.terrain_generator(not "--inland" in OS.get_cmdline_user_args(),not "--natural-ground" in OS.get_cmdline_user_args())
 var native=ClassDB.instantiate("TerrainCore")
 print("SHUFFLE_NATIVE_VARIANT ",native.build_variant());native=null
 var seeds:Array=[1729662740,1253652533,2147483647,987654321,474546765,42,123456789,1703,0,1]
 if "--sweep" in OS.get_cmdline_user_args():
  var random:=RandomNumberGenerator.new();random.seed=20261113
  for index in 23:
   var candidate:=random.randi_range(0,2147483647)
   if not seeds.has(candidate):seeds.append(candidate)
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--seed="):seeds=[int(argument.get_slice("=",1))]
  if argument.begins_with("--range="):
   var bounds:=argument.get_slice("=",1).split(":")
   if bounds.size()!=2 or int(bounds[0])<0 or int(bounds[1])>seeds.size() or int(bounds[0])>=int(bounds[1]):quit(2);return
   seeds=seeds.slice(int(bounds[0]),int(bounds[1]))
 print("SHUFFLE_CASES generator=",generator," seeds=",seeds)
 for seed_value:int in seeds:
  var started:=Time.get_ticks_msec()
  var result:=Plan.preview(seed_value,generator,true,true,true,"user://cartography/generation",Recipe.DEFAULTS)
  print("SHUFFLE_PLAN seed=",seed_value," generator=",generator," ok=",result.get("ok",false)," milliseconds=",Time.get_ticks_msec()-started," reason=",result.get("reason",""))
  if not result.get("ok",false):print("SHUFFLE_DIAGNOSTIC ",{"packet_bytes":result.get("packet_bytes"),"segments":result.get("segments"),"packets":result.get("packets"),"completed":result.get("completed"),"position":result.get("position"),"low":result.get("low"),"high":result.get("high"),"attempts":result.get("attempts"),"road_rejections":result.get("road_rejections"),"best_missing":result.get("best_missing"),"grid_rejections":result.get("grid_rejections"),"street_candidates":result.get("street_candidates")})
  if not result.get("ok",false):failures+=1
  else:
   var cached:=Plan.build(seed_value,generator,true,true,"user://generation_plans",Recipe.DEFAULTS)
   var spawn:=preload("res://addons/world_runtime/introduction_spawn.gd").select(cached.sites)
   var valid:bool=cached.get("cache_hit",false) and cached.plan_digest==result.plan_digest and spawn.get("ok",false) and spawn.distance<200
   for link:Dictionary in cached.network.links:
    if link.trail:continue
    var points:PackedVector3Array=link.points
    for index in range(1,points.size()-1):
     var incoming:Vector3=points[index]-points[index-1];incoming.y=0
     var outgoing:Vector3=points[index+1]-points[index];outgoing.y=0
     valid=valid and incoming.normalized().dot(outgoing.normalized())>=-.10001
   var buildings:=0
   var districts:Dictionary={}
   for site:Dictionary in cached.sites:
    buildings+=site.lots.size()
    districts[Vector2i(site.town,site.district)]=true
   # The recipe requires 50 settlement buildings. Wilderness lookouts are
   # independently terrain-fitted, with an existing maximum of two sites.
   var towers:int=cached.get("watchtowers",{}).get("sites",[]).size()
   valid=valid and cached.options==Recipe.DEFAULTS and districts.size()==6 and buildings==50 and towers<=2 and cached.building_count==buildings+towers
   print("SHUFFLE_CACHE_AND_SPAWN seed=",seed_value," ok=",valid," districts=",districts.size()," buildings=",buildings," lookouts=",towers)
   if not valid:failures+=1
 print("SHUFFLE_PLAN failures=",failures)
 quit(1 if failures else 0)

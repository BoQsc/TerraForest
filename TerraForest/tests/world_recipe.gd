extends SceneTree
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
var failures:=0
func check(condition:bool,message:String)->void:
 if not condition:failures+=1
 print("PASS " if condition else "FAIL ",message)
func _initialize()->void:run.call_deferred()
func run()->void:
 check(load("res://addons/world_runtime/generate_world_task.gd").can_instantiate(),"production task parses")
 check(load("res://demo/worlds.gd").can_instantiate(),"world browser parses")
 var codec:=Recipe.codec();var options:Dictionary=Recipe.DEFAULTS.duplicate()
 var bytes:=Recipe.encode(options)
 check(bytes.size()==28 and codec.decode(bytes)==options,"bounded binary recipe round trip")
 check(codec.restore_snapshot(bytes) and codec.capture_snapshot()==bytes,"recipe durable storage restores exactly")
 for field:String in options:
  var invalid:=options.duplicate();invalid[field]=-1
  check(Recipe.encode(invalid).is_empty(),"reject invalid "+field)
 var corrupt:=bytes.duplicate();corrupt[4]=255
 check(not codec.restore_snapshot(corrupt) and codec.capture_snapshot()==bytes,"invalid recipe cannot mutate live state")
 check(codec.restore_snapshot(PackedByteArray()) and codec.capture_snapshot().is_empty(),"old worlds retain empty legacy recipe")
 var trees=ClassDB.instantiate("NativeVegetationScatter")
 var populations:=[0,0,0]
 var stable_ids:=true
 for row in 32:
  for column in 32:
   var previous:=PackedInt64Array()
   for profile in 3:
    var candidates:Dictionary=trees.candidates(Vector2i(column,row),1703,.82,true,profile)
    populations[profile]+=candidates.ids.size()
    if profile>0:
     for identity:int in candidates.ids:stable_ids=stable_ids and identity in previous
    previous=candidates.ids
 check(populations[0]>populations[1] and populations[1]>populations[2] and populations[2]>0,"three native woodland profiles change actual coverage")
 check(stable_ids,"biome retains stable tree identities across profiles")
 var folder:="user://recipe_checks_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
 var cases:Array=[{"biome":0,"settlements":1,"districts":1,"network":0,"trails":0},Recipe.DEFAULTS.duplicate(),{"biome":1,"settlements":2,"districts":2,"network":1,"trails":1},{"biome":2,"settlements":3,"districts":2,"network":1,"trails":2}]
 var reports:Array=[]
 for settings:Dictionary in cases:
  var worker:=Thread.new();worker.start(Plan.build.bind(1703,21,true,true,folder,settings))
  var frames:=0
  while worker.is_alive():await process_frame;frames+=1
  var result:Dictionary=worker.wait_to_finish()
  print("RECIPE_CASE ",settings," result=",result.get("reason","ok")," ms=",result.get("worker_ms",-1))
  check(result.get("ok",false),"custom plan fits "+str(settings))
  if not result.get("ok",false):reports.append({"options":settings,"result":result});continue
  check(result.sites.size()==settings.settlements*settings.districts,"all requested districts generated")
  var warm:=Plan.build(1703,21,true,true,folder,settings)
  check(warm.get("cache_hit",false) and warm.plan_digest==result.plan_digest,"binary plan cache reconstructs same prefab layout")
  var owners:Array=[]
  for index in result.sites.size():owners.append(index)
  for link:Dictionary in result.network.links:
   if link.trail:continue
   var previous:int=owners[link.target];var replacement:int=owners[link.source]
   for index in owners.size():
    if owners[index]==previous:owners[index]=replacement
  check(owners.all(func(owner:int):return owner==owners[0]),"every district belongs to connected native road network")
  check(frames>0,"native worker keeps main loop running")
  for site:Dictionary in result.sites:
   check(site.block_paving.get("ok",false),"district retains native flat sidewalk plate plan")
  reports.append({"options":settings,"buildings":result.building_count,"network":result.network,"ms":result.worker_ms,"digest":result.plan_digest})
 FileAccess.open("res://reports/world_recipe.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"tree_counts":populations,"cases":reports},"  "))
 print("WORLD_RECIPE failures=",failures)
 quit(1 if failures else 0)

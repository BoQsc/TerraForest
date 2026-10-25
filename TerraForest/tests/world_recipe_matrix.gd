extends SceneTree
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
 var failures:=0;var rows:Array=[]
 var folder:="user://recipe_matrix_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
 for generator in [19,20,21]:
  for seed_value in [0,42,1703]:
   var options:Dictionary={"biome":1,"settlements":3,"districts":2,"network":1,"trails":2}
   var worker:=Thread.new();worker.start(Plan.build.bind(seed_value,generator,true,true,folder,options))
   while worker.is_alive():await process_frame
   var result:Dictionary=worker.wait_to_finish()
   var passed:bool=result.get("ok",false) and result.get("building_count",0)==68
   if not passed:failures+=1
   var network:Dictionary=result.get("network",{})
   var row:Dictionary={"seed":seed_value,"generator":generator,"ok":passed,"reason":result.get("reason",""),"ms":result.get("worker_ms",0),"roads_m":network.get("road_length_m",0),"trails_m":network.get("trail_length_m",0),"trails":network.get("trail_count",0),"loops":network.get("loop_count",0),"crossing_rejections":network.get("crossing_rejections",0)}
   rows.append(row);print("RECIPE_MATRIX ",row)
   if not passed:print("RECIPE_MATRIX_DIAGNOSTIC ",result)
 FileAccess.open("res://reports/world_recipe_matrix.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rows":rows},"  "))
 print("WORLD_RECIPE_MATRIX failures=",failures);quit(1 if failures else 0)

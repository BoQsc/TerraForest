# SPDX-License-Identifier: 0BSD
extends SceneTree
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
func _initialize()->void:
 var output:="res://reports/generation_plan_matrix.json"
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--matrix-output="):output=arg.trim_prefix("--matrix-output=")
 var folder:="user://generation_matrix_"+Crypto.new().generate_random_bytes(8).hex_encode()
 var rows:=[]
 var failures:=0
 for generator in [19,20,21]:
  for seed_value in [0,42,1703]:
   var plan:=Plan.build(seed_value,generator,true,true,folder)
   var cached:=Plan.build(seed_value,generator,true,true,folder)
   var same:bool=plan.get("ok",false) and cached.get("cache_hit",false) and cached.get("plan_digest")==plan.get("plan_digest")
   if same:
    for site in ["plan","market"]:
     same=same and plan[site].block_paving.tiles>0 and plan[site].block_paving.records==cached[site].block_paving.records
   rows.append({"seed":seed_value,"generator":generator,"ok":plan.get("ok",false),"cache_equal":same,"digest":plan.get("plan_digest",""),"reason":plan.get("reason",""),"ms":plan.get("worker_ms",0)})
   print("MATRIX ",rows[-1])
   if not same:failures+=1
 var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(rows,"  "));file.close()
 print("GENERATION_PLAN_MATRIX failures=",failures)
 quit(1 if failures else 0)

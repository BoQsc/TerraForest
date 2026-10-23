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
 for seed_value in [0,42,1703]:
  var plan:=Plan.build(seed_value,19,true,true,folder)
  rows.append({"seed":seed_value,"ok":plan.get("ok",false),"digest":plan.get("plan_digest",""),"reason":plan.get("reason",""),"ms":plan.get("worker_ms",0)})
  print("MATRIX ",rows[-1])
  if not plan.get("ok",false):failures+=1
 var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(rows,"  "));file.close()
 print("GENERATION_PLAN_MATRIX failures=",failures)
 quit(1 if failures else 0)

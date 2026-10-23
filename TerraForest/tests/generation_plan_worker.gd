# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
func run()->void:
 var folder:="user://plan_worker_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
 var expected:Dictionary=Plan.build(0,19,true,true,folder+"/reference")
 check(expected.get("ok",false) and not expected.get("cache_hit",true),"independent cold native plan establishes reference")
 var worker:=Thread.new();check(worker.start(Plan.build.bind(0,19,true,true,folder+"/worker"))==OK,"real plan computation starts on worker")
 var frames:=0
 while worker.is_alive():await process_frame;frames+=1
 var result:Dictionary=worker.wait_to_finish()
 check(result.get("ok",false) and not result.get("cache_hit",true) and result.get("plan_digest")==expected.get("plan_digest") and frames>0,"cold worker preserves exact shared plan while main loop remains live")
 check(worker.start(Plan.build.bind(0,19,true,true,folder+"/worker"))==OK,"cached plan also runs through worker")
 while worker.is_alive():await process_frame
 var cached:Dictionary=worker.wait_to_finish()
 check(cached.get("ok",false) and cached.get("cache_hit",false) and cached.get("plan_digest")==result.get("plan_digest"),"worker cache/recipe restoration preserves the same plan identity")
 FileAccess.open("res://reports/generation_plan_worker.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"cold_ms":result.get("worker_ms"),"main_loop_frames":frames,"digest":result.get("plan_digest"),"scope":"Actual shared native-backed plan and resource recipes from cold and cached worker calls; exact plan identity and headless main-loop liveness, not graphical FPS proof."},"  "))
 for name:String in ["reference","worker"]:
  var path:=folder.path_join(name)
  for file:String in DirAccess.get_files_at(path):DirAccess.remove_absolute(path.path_join(file))
  DirAccess.remove_absolute(path)
 DirAccess.remove_absolute(folder)
 print("GENERATION_PLAN_WORKER failures=",failures);quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends "res://tests/terrain_generation_staging.gd"
func run()->void:
 var path:=ProjectSettings.globalize_path("user://bake_progress_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
 var packets:Array=[]
 for i in 2112:
  var p:=Vector3(64+(i%60)*32,128,64+(i/60)*32);packets.append(Codec.graded_bed(p,p+Vector3(4,0,0),1,1,0,1))
 var core:=fresh();check(core.generation_bake_progress().state==0,"new native owner reports idle progress")
 var worker:=Thread.new();check(worker.start(func():return core.bake_generated_earthworks_staged(packets,path,256,24))==OK,"native bake owns its worker")
 var previous:=0;var checkpoints:=0;var valid:=true;var active_samples:=0;var max_us:=0;var samples:Array=[]
 while worker.is_alive():
  var began:=Time.get_ticks_usec();var state:Dictionary=core.generation_bake_progress();max_us=maxi(max_us,Time.get_ticks_usec()-began)
  if state.state==1:
   valid=valid and state.total==2112 and state.completed>=previous and state.completed<=state.total and state.checkpoints>=checkpoints and state.phase in [1,2]
   previous=state.completed;checkpoints=state.checkpoints;active_samples+=1
   if samples.size()<512:samples.append(state)
  await process_frame
 var result:Dictionary=worker.wait_to_finish();var final:Dictionary=core.generation_bake_progress()
 check(result.get("ok",false) and final.state==2 and final.completed==2112 and final.total==2112 and final.checkpoints==result.checkpoints,"complete observation follows the final verified checkpoint")
 check(valid and active_samples>=3 and max_us<50000,"coherent monotonic progress stays nonblocking while the terrain mutex is held")
 core.execute(Codec.command(6,[1703,5]));check(core.generation_bake_progress().state==0,"world reset clears stale job observations")
 result.erase("checkpoint")
 FileAccess.open("res://reports/generation_bake_progress.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"result":result,"active_samples":active_samples,"getter_max_us":max_us,"samples":samples,"scope":"Live native command/checkpoint observation during one staged bake; coherent counters, bounded polling and final/reset states. No rendered FPS or thermal claim."},"  "))
 core=null;clear_store(path)
 print("GENERATION_BAKE_PROGRESS failures=",failures);quit(1 if failures else 0)

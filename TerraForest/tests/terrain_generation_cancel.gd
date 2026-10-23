# SPDX-License-Identifier: 0BSD
extends "res://tests/terrain_generation_staging.gd"
const Backend=preload("res://addons/volumetric_terrain/terrain_backend.gd")
func checkpoint_files(path:String)->int:
 if not DirAccess.dir_exists_absolute(path):return 0
 var count:=0
 for name:String in DirAccess.get_files_at(path):
  if name.ends_with(".tindex"):count+=1
 return count
func run()->void:
 var path:=ProjectSettings.globalize_path("user://generation_cancel_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
 var packets:Array=[]
 for i in 2112:
  var p:=Vector3(64+(i%60)*32,128,64+(i/60)*32);packets.append(Codec.graded_bed(p,p+Vector3(4,0,0),1,1,0,1))
 var core:=fresh();var worker:=Thread.new()
 check(worker.start(func():return core.bake_generated_earthworks_staged(packets,path,256,24,0))==OK,"native staged bake starts on its owner")
 var deadline:=Time.get_ticks_msec()+2000
 while checkpoint_files(path)<3 and worker.is_alive() and Time.get_ticks_msec()<deadline:await process_frame
 var private_checkpoints:=checkpoint_files(path)
 check(core.executing_command()==28 and worker.is_alive() and private_checkpoints>=3,"confirmed live bake after intermediate private checkpoints before cancellation")
 var began:=Time.get_ticks_usec();core.execute(Codec.command(12));var signal_us:=Time.get_ticks_usec()-began
 var result:Dictionary=worker.wait_to_finish();var joined_us:=Time.get_ticks_usec()-began
 check(signal_us<50000 and joined_us<1000000,"cancellation is nonblocking and owner joins within one second")
 check(not result.get("ok",false) and not result.has("checkpoint") and raw(core)==raw(fresh()),"in-flight cancellation discards unpublished world and exposes no final reference")
 result["cancel_signal_us"]=signal_us;result["cancel_join_us"]=joined_us
 result["observed_private_checkpoints"]=private_checkpoints
 core=null;clear_store(path)
 var folder:=path+"_backend";DirAccess.make_dir_recursive_absolute(folder)
 var backend:=Backend.new();backend.world_generator=5;backend.disk_cache.enabled=false;backend.save_path=folder.path_join("world.trw");backend.snapshot_codec=ClassDB.instantiate("NativeWorldArchive")
 check(backend.configure_initial_earthworks(packets,"f".repeat(64)) and backend.start(false)==OK,"production worker begins unpublished staged bake")
 deadline=Time.get_ticks_msec()+2000
 while checkpoint_files(backend.save_path+".terrain")<2 and backend.thread.is_alive() and Time.get_ticks_msec()<deadline:await process_frame
 var production_checkpoints:=checkpoint_files(backend.save_path+".terrain")
 check(backend.native.executing_command()==28 and production_checkpoints>=2,"confirmed live production bake after private checkpoint before stop")
 began=Time.get_ticks_usec();backend.stop();joined_us=Time.get_ticks_usec()-began
 check(joined_us<1000000 and not backend.initial_earthworks_result.get("ok",false) and not FileAccess.file_exists(backend.save_path),"production stop cancels and joins without publishing partial world")
 FileAccess.open("res://reports/terrain_generation_cancel.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"native_result":result,"production_private_checkpoints":production_checkpoints,"production_stop_us":joined_us,"scope":"Confirmed live native and production-owner cancellation after intermediate private checkpoints, bounded stop/join and no final reference or canonical root. Not a crash/power-loss test."},"  "))
 backend=null;clear_store(folder.path_join("world.trw.terrain"));clear_store(folder)
 print("TERRAIN_GENERATION_CANCEL failures=",failures);quit(1 if failures else 0)

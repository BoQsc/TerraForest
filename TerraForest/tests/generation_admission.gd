# SPDX-License-Identifier: 0BSD
extends "res://tests/terrain_generation_staging.gd"
const Backend=preload("res://addons/volumetric_terrain/terrain_backend.gd")
func configured(path:String)->RefCounted:
 var backend:=Backend.new();backend.world_generator=5;backend.disk_cache.enabled=false;backend.save_path=path;backend.snapshot_codec=ClassDB.instantiate("NativeWorldArchive")
 var a:=Vector3(64,128,64)
 check(backend.configure_initial_earthworks([Codec.graded_bed(a,a+Vector3(4,0,0),1,1,0,1)],"f".repeat(64),true),"offline job configures explicit admission")
 return backend
func waiting(backend:RefCounted)->bool:
 var deadline:=Time.get_ticks_msec()+3000
 while backend.startup_diagnostics().phase!="awaiting_generation_admission" and Time.get_ticks_msec()<deadline:await process_frame
 return backend.startup_diagnostics().phase=="awaiting_generation_admission"
func run()->void:
 var folder:=ProjectSettings.globalize_path("user://generation_admission_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(folder)
 var path:=folder.path_join("world.trw");var backend:=configured(path)
 check(backend.start(false)==OK and await waiting(backend),"worker is live and waiting at the admission barrier")
 check(not DirAccess.dir_exists_absolute(path+".terrain") and backend.native.generation_bake_progress().state==0,"no native bake or storage work occurs before UI admission")
 check(backend.admit_initial_generation() and not backend.admit_initial_generation(),"main owner admits the generation job exactly once")
 var ready:=false;var deadline:=Time.get_ticks_msec()+5000
 while not ready and Time.get_ticks_msec()<deadline:
  for row:Dictionary in backend.poll():
   if row.kind=="startup":ready=not str(row.message).begins_with("ERROR:")
  await process_frame
 check(ready and backend.initial_earthworks_result.get("ok",false) and backend.native.generation_bake_progress().state==2,"admitted job reaches native verified completion")
 backend.stop();backend=null
 var other:=configured(folder.path_join("cancelled.trw"));check(other.start(false)==OK and await waiting(other),"second live worker reaches the same admission barrier")
 var began:=Time.get_ticks_usec();other.stop();var joined:=Time.get_ticks_usec()-began
 check(joined<1000000 and not FileAccess.file_exists(other.save_path) and not DirAccess.dir_exists_absolute(other.save_path+".terrain"),"stop releases a waiting worker promptly without starting or publishing generation")
 other=null;clear_store(path+".terrain")
 for file:String in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(file))
 DirAccess.remove_absolute(folder)
 print("GENERATION_ADMISSION failures=",failures);quit(1 if failures else 0)

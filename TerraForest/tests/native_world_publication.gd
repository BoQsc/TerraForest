# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(value:bool,label:String)->void:
 if not value:failures+=1;print("FAIL ",label)
func _initialize()->void:
 var folder:=ProjectSettings.globalize_path("user://publication_test_%d"%Time.get_ticks_usec())
 DirAccess.make_dir_recursive_absolute(folder)
 var archive=ClassDB.instantiate("NativeWorldArchive")
 var bytes:PackedByteArray=archive.encode({"terrain":PackedByteArray([1,2,3])})
 var source:=folder.path_join("source.trw")
 check(archive.acquire(source),"acquire source")
 check(archive.publish(source,bytes)==OK,"publish valid root")
 var copier=ClassDB.instantiate("NativeWorldArchive")
 check(not copier.clone_world(folder,"source","copy").ok,"live writer exclusion")
 archive.release()
 for suffix:String in ["regions","models","water","terrain"]:
  var path:=source+"."+suffix+"/nested";DirAccess.make_dir_recursive_absolute(path)
  var file:=FileAccess.open(path.path_join("data.bin"),FileAccess.WRITE);file.store_buffer(PackedByteArray([9,8,7]));file.close()
 var result:Dictionary=copier.clone_world(folder,"source","copy")
 check(result.ok and result.get("files",0)==4 and result.get("bytes",0)==12,"native store copy")
 check(FileAccess.get_file_as_bytes(folder.path_join("copy.trw"))==bytes,"canonical equality")
 for suffix:String in ["regions","models","water","terrain"]:check(FileAccess.get_file_as_bytes(folder.path_join("copy.trw."+suffix+"/nested/data.bin"))==PackedByteArray([9,8,7]),"store equality")
 check(not copier.clone_world(folder,"source","copy").ok,"no overwrite")
 DirAccess.make_dir_recursive_absolute(folder.path_join("orphan.trw.water"))
 check(not copier.clone_world(folder,"source","orphan").ok,"orphan store rejection")
 check(not copier.clone_world(folder,"../source","escape").ok,"path escape rejection")
 for phase in 5:
  var destination:="interrupted_%d"%phase
  var stopped:Dictionary=copier.clone_world(folder,"source",destination,phase)
  check(not stopped.ok and stopped.has("staging"),"injected publication interruption")
  check(not FileAccess.file_exists(folder.path_join(destination+".trw")),"interrupted canonical root absent")
  var recovered:Dictionary=copier.recover_world(folder,destination)
  check(recovered.ok and recovered.get("recovered",false),"interrupted stores recover")
  check(FileAccess.get_file_as_bytes(folder.path_join(destination+".trw"))==bytes,"recovered root equals source")
  for suffix:String in ["regions","models","water","terrain"]:check(FileAccess.get_file_as_bytes(folder.path_join(destination+".trw."+suffix+"/nested/data.bin"))==PackedByteArray([9,8,7]),"recovered store equals source")
 var damaged:Dictionary=copier.clone_world(folder,"source","damaged",1)
 var modified:=FileAccess.open(folder.path_join("damaged.trw.regions/nested/data.bin"),FileAccess.WRITE);modified.store_buffer(PackedByteArray([9,8,6]));modified.close()
 var recovery:Dictionary=copier.recover_world(folder,"damaged")
 check(not recovery.ok and recovery.found,"changed regional bytes reject recovery")
 check(not FileAccess.file_exists(folder.path_join("damaged.trw")) and DirAccess.dir_exists_absolute(str(damaged.staging).path_join("models")),"failed recovery leaves stores and root unpromoted")
 check(copier.recover_world(folder,"unknown").ok and not copier.recover_world(folder,"unknown").found,"no interrupted publication is a no-op")
 check(FileAccess.get_file_as_bytes(source)==bytes,"source retained")
 check(not copier.clone_world(folder,"source","unsafe_retirement",-1,true).ok,"ordinary worlds cannot be retired")
 for index in 3:
  var generated:="combined_stage_"+str(index).repeat(32)
  var generated_path:=folder.path_join(generated+".trw")
  check(copier.clone_world(folder,"source",generated).ok,"create isolated generation fixture")
  var backup:=FileAccess.open(generated_path+".bak",FileAccess.WRITE);backup.store_buffer(bytes);backup.close()
  if index==2:
   var pending:=FileAccess.open(generated_path+".tmp",FileAccess.WRITE);pending.store_buffer(bytes);pending.close()
  var published:Dictionary=copier.clone_world(folder,generated,"published_%d"%index,1 if index==1 else -1,true)
  if index==1:
   check(not published.ok and FileAccess.file_exists(generated_path),"interrupted generation retains source")
   check(DirAccess.dir_exists_absolute(generated_path+".terrain"),"interrupted generation retains source stores")
  else:
   check(published.ok,"generation publication succeeds")
   check(published.get("source_retired",false)==(index==0),"only finished work copy retired")
   check(FileAccess.get_file_as_bytes(folder.path_join("published_%d.trw"%index))==bytes,"retirement preserves published root")
   for suffix:String in ["regions","models","water","terrain"]:
    check(FileAccess.get_file_as_bytes(folder.path_join("published_%d.trw."%index+suffix+"/nested/data.bin"))==PackedByteArray([9,8,7]),"retirement preserves published stores")
    check(DirAccess.dir_exists_absolute(generated_path+"."+suffix)==(index==2),"source store lifetime")
   check(FileAccess.file_exists(generated_path)==(index==2) and FileAccess.file_exists(generated_path+".bak")==(index==2),"source root and backup lifetime")
   if index==2:check(published.has("retention_reason") and FileAccess.file_exists(generated_path+".tmp"),"unfinished source retained explicitly")
 var script=load("res://addons/world_runtime/generation_job.gd")
 check(script!=null and script.can_instantiate(),"generation coordinator parses")
 print("NATIVE_PUBLICATION failures=",failures," fixture=",folder)
 quit(1 if failures else 0)

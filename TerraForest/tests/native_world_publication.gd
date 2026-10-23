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
 for suffix:String in ["regions","models","water"]:
  var path:=source+"."+suffix+"/nested";DirAccess.make_dir_recursive_absolute(path)
  var file:=FileAccess.open(path.path_join("data.bin"),FileAccess.WRITE);file.store_buffer(PackedByteArray([9,8,7]));file.close()
 var result:Dictionary=copier.clone_world(folder,"source","copy")
 check(result.ok and result.get("files",0)==3 and result.get("bytes",0)==9,"native store copy")
 check(FileAccess.get_file_as_bytes(folder.path_join("copy.trw"))==bytes,"canonical equality")
 for suffix:String in ["regions","models","water"]:check(FileAccess.get_file_as_bytes(folder.path_join("copy.trw."+suffix+"/nested/data.bin"))==PackedByteArray([9,8,7]),"store equality")
 check(not copier.clone_world(folder,"source","copy").ok,"no overwrite")
 DirAccess.make_dir_recursive_absolute(folder.path_join("orphan.trw.water"))
 check(not copier.clone_world(folder,"source","orphan").ok,"orphan store rejection")
 check(not copier.clone_world(folder,"../source","escape").ok,"path escape rejection")
 check(FileAccess.get_file_as_bytes(source)==bytes,"source retained")
 var script=load("res://addons/world_runtime/generation_job.gd")
 check(script!=null and script.can_instantiate(),"generation coordinator parses")
 print("NATIVE_PUBLICATION failures=",failures," fixture=",folder)
 quit(1 if failures else 0)

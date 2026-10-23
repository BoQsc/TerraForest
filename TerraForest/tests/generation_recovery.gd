# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func _initialize():run.call_deferred()
func run():
 var id=Crypto.new().generate_random_bytes(16).hex_encode()
 var source="combined_stage_"+id
 var destination="recovery_"+id
 var folder=ProjectSettings.globalize_path("user://worlds")
 DirAccess.make_dir_recursive_absolute(folder)
 var archive=ClassDB.instantiate("NativeWorldArchive")
 var bytes:PackedByteArray=archive.encode({"terrain":PackedByteArray([1,2,3])})
 archive.acquire(folder.path_join(source+".trw"));archive.publish(folder.path_join(source+".trw"),bytes);archive.release()
 for suffix in ["regions","models","water","terrain"]:
  DirAccess.make_dir_recursive_absolute(folder.path_join(source+".trw."+suffix))
  var file=FileAccess.open(folder.path_join(source+".trw."+suffix+"/part"),FileAccess.WRITE);file.store_8(12);file.close()
 var interrupted:Dictionary=archive.clone_world(folder,source,destination,1)
 if interrupted.ok:failures+=1
 var command=preload("res://demo/world_launch.gd").recovery_command(destination)
 var status="user://generation_recovery_"+id+".json"
 command.args.append("--status-file="+status)
 var pid=OS.create_process(OS.get_executable_path(),command.args,false)
 var deadline=Time.get_ticks_msec()+10000
 while OS.is_process_running(pid) and Time.get_ticks_msec()<deadline:await process_frame
 if OS.is_process_running(pid):OS.kill(pid);failures+=1
 var result=JSON.parse_string(FileAccess.get_file_as_string(status))
 if not result is Dictionary or result.get("state")!="ready":failures+=1;print("RECOVERY_RESULT ",result)
 if FileAccess.get_file_as_bytes(folder.path_join(destination+".trw"))!=bytes:failures+=1
 # Remove only this test's explicitly named dummy files, never real worlds.
 for slot in [source,destination]:
  for suffix in ["regions","models","water","terrain"]:
   var path=folder.path_join(slot+".trw."+suffix)
   DirAccess.remove_absolute(path+"/part");DirAccess.remove_absolute(path)
  for suffix in [".trw",".trw.lock",".prepare.lock",".presentation.json"]:
   if FileAccess.file_exists(folder.path_join(slot+suffix)):DirAccess.remove_absolute(folder.path_join(slot+suffix))
  if DirAccess.dir_exists_absolute(folder.path_join(slot+".preview")):DirAccess.remove_absolute(folder.path_join(slot+".preview"))
 print("GENERATION_RECOVERY failures=",failures);quit(1 if failures else 0)

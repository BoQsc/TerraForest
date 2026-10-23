# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func invoke(slot:String,folder:String,cancel:String="")->Dictionary:
 var status_path:=folder.path_join("status.json")
 var args:=PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://addons/world_runtime/generation_job.gd","--","--destination="+slot,"--status-file="+status_path])
 if not cancel.is_empty():args.append("--cancel-file="+cancel)
 var pid:=OS.create_process(OS.get_executable_path(),args,false)
 var deadline:=Time.get_ticks_msec()+10000
 while pid>=0 and OS.is_process_running(pid) and Time.get_ticks_msec()<deadline:await process_frame
 if pid>=0 and OS.is_process_running(pid):OS.kill(pid);check(false,"coordinator exits within bound")
 if not FileAccess.file_exists(status_path):return {}
 var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(status_path))
 return parsed if parsed is Dictionary else {}
func run()->void:
 var slot:="jobcheck_"+Crypto.new().generate_random_bytes(8).hex_encode()
 var folder:="user://generation_failure_checks/"+slot
 DirAccess.make_dir_recursive_absolute(folder)
 var cancel:=folder.path_join("cancel")
 var file:=FileAccess.open(cancel,FileAccess.WRITE);file.store_string("cancel");file.close()
 var result:Dictionary=await invoke(slot,folder,cancel)
 check(result.get("state","")=="cancelled","pre-cancelled request never starts a bake")
 var run_path:String=str(result.get("report","" )).path_join("run.json")
 var run:Variant=JSON.parse_string(FileAccess.get_file_as_string(run_path))
 check(run is Dictionary and run.get("phases",[1]).is_empty(),"cancel before launch creates no child process")
 check(not FileAccess.file_exists("user://worlds/"+slot+".trw"),"cancelled world not published")
 var lease=ClassDB.instantiate("NativeWorldArchive")
 var path:=ProjectSettings.globalize_path("user://worlds/"+slot+".prepare")
 check(lease.acquire(path),"cancel releases destination lease")
 result=await invoke(slot,folder)
 check(result.get("state","")=="failed" and str(result.get("reason","")).contains("Another generation"),"concurrent destination request rejected")
 lease.release()
 var orphan:="user://worlds/"+slot+".trw.water"
 DirAccess.make_dir_recursive_absolute(orphan)
 file=FileAccess.open(orphan.path_join("sentinel"),FileAccess.WRITE);file.store_string("preserve");file.close()
 result=await invoke(slot,folder)
 check(result.get("state","")=="failed" and str(result.get("reason","")).contains("contains world data"),"orphan store requires recovery rather than overwrite")
 check(FileAccess.get_file_as_string(orphan.path_join("sentinel"))=="preserve","failed generation preserves orphan data")
 print("GENERATION_JOB_FAILURES failures=",failures)
 quit(1 if failures else 0)

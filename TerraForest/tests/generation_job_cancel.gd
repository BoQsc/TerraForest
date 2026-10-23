# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(value:bool,label:String):
 if not value:failures+=1
 print("PASS " if value else "FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var slot="cancel_live_"+Crypto.new().generate_random_bytes(8).hex_encode()
 var folder="user://generation_failure_checks/"+slot
 DirAccess.make_dir_recursive_absolute(folder)
 var status=folder.path_join("status.json");var cancel=folder.path_join("cancel")
 var args=PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://addons/world_runtime/generation_job.gd","--","--destination="+slot,"--status-file="+status,"--cancel-file="+cancel])
 var pid=OS.create_process(OS.get_executable_path(),args,false)
 var end=Time.get_ticks_msec()+10000
 while not FileAccess.file_exists(status) and Time.get_ticks_msec()<end:await process_frame
 await create_timer(1.5).timeout
 var file=FileAccess.open(cancel,FileAccess.WRITE);file.store_string("cancel");file.close()
 end=Time.get_ticks_msec()+10000
 while OS.is_process_running(pid) and Time.get_ticks_msec()<end:await process_frame
 check(not OS.is_process_running(pid),"active coordinator exits promptly after cancellation")
 if OS.is_process_running(pid):OS.kill(pid)
 var value=JSON.parse_string(FileAccess.get_file_as_string(status))
 check(value is Dictionary and value.get("state")=="cancelled","cancelled terminal status published")
 if value is Dictionary:
  var report=JSON.parse_string(FileAccess.get_file_as_string(str(value.report).path_join("run.json")))
  check(report is Dictionary and report.phases.size()==1,"one actual bake process was started")
  if report is Dictionary:
   for phase in report.phases:check(not OS.is_process_running(int(phase.pid)),"owned bake process terminated")
 check(not FileAccess.file_exists("user://worlds/"+slot+".trw"),"partial world never becomes selectable canonical data")
 var lease=ClassDB.instantiate("NativeWorldArchive")
 check(lease.acquire(ProjectSettings.globalize_path("user://worlds/"+slot+".prepare")),"retry can acquire released preparation lease")
 lease.release()
 print("GENERATION_JOB_CANCEL failures=",failures);quit(1 if failures else 0)

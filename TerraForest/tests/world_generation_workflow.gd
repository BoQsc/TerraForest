# SPDX-License-Identifier: 0BSD
extends SceneTree
const Launch=preload("res://demo/world_launch.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
 var seed_value:=1703;var generator:=19;var layout:="connected"
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--case-seed="):seed_value=int(arg.trim_prefix("--case-seed="))
  if arg.begins_with("--case-generator="):generator=int(arg.trim_prefix("--case-generator="))
  if arg.begins_with("--case-layout="):layout=arg.trim_prefix("--case-layout=")
 var slot:="workflow_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
 var folder:=ProjectSettings.globalize_path("res://reports/world_generation_workflow")
 DirAccess.make_dir_recursive_absolute(folder)
 var status:=folder.path_join("status.json")
 var args:=Launch.engine_prefix()+PackedStringArray(["--headless","--script","res://addons/world_runtime/generation_job.gd","--","--destination="+slot,"--seed="+str(seed_value),"--generator="+str(generator),"--settlement-layout="+layout,"--status-file="+status,"--cancel-file="+folder.path_join(slot+".cancel"),"--capture-generation-ui"])
 var began:=Time.get_ticks_msec();var pid:=OS.create_process(OS.get_executable_path(),args,false)
 var deadline:=began+180000
 while pid>=0 and OS.is_process_running(pid) and Time.get_ticks_msec()<deadline:await process_frame
 var failures:=0
 if pid<0 or OS.is_process_running(pid):
  failures+=1
  if pid>=0:OS.kill(pid)
 var result=JSON.parse_string(FileAccess.get_file_as_string(status)) if FileAccess.file_exists(status) else null
 if not result is Dictionary or result.get("state")!="ready":failures+=1
 var run:Dictionary={}
 if result is Dictionary:
  var parsed=JSON.parse_string(FileAccess.get_file_as_string(str(result.report).path_join("run.json")))
  if parsed is Dictionary:run=parsed
 if run.get("phases",[]).size()!=1 or not run.get("validation",{}).get("ok",false):failures+=1;print("FAIL native verification did not replace second game boot")
 if not run.is_empty():
  var child_args:PackedStringArray=run.phases[0].arguments
  if not "res://addons/world_runtime/generate_world.gd" in child_args:failures+=1
  var baked_path:String=str(result.report).path_join("generated_lakes_bake.json")
  var baked=JSON.parse_string(FileAccess.get_file_as_string(baked_path)) if FileAccess.file_exists(baked_path) else null
  if not baked is Dictionary or not baked.get("ok",false):failures+=1;print("FAIL offline native lake job did not complete")
 var photograph_names:Array=["north","road","market"] if layout=="connected" else ["north","road"] if layout=="road" else ["north"]
 if result is Dictionary and result.get("state")=="ready":
  for name:String in photograph_names:
   var image:=Image.load_from_file("user://worlds/"+slot+".preview/"+name+".png")
   if image==null or image.get_size()!=Vector2i(1280,720):failures+=1;print("FAIL world photograph ",name)
 var report:={"failures":failures,"slot":slot,"milliseconds":Time.get_ticks_msec()-began,"result":result,"run":run,"scope":"Actual player generation flow, native binary validation and published cached photographs. Fresh playable reopen/visual inspection are separate checks."}
 FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("WORLD_GENERATION_WORKFLOW failures=",failures," slot=",slot," milliseconds=",report.milliseconds)
 quit(1 if failures else 0)

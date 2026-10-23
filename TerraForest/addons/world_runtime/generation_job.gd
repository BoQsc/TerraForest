# SPDX-License-Identifier: 0BSD
extends SceneTree
# Engine-owned coordinator. Generation/persistence work runs in native APIs;
# this script manages isolated stages and user-visible status only.
const Launch=preload("res://demo/world_launch.gd")
var destination:=""
var recovery_mode:=false
var presentation_report:=""
var seed_value:=42
var generator:=19
var settlement_layout:="connected"
var status_path:=""
var cancel_path:=""
var report:=""
var stage:=""
var child:=-1
var phase:=""
var deadline:=0
var lease:RefCounted
var lease_owned:=false
var publish_worker:Thread
var metadata:Dictionary={}
var progress_detail:Dictionary={}
var next_progress_poll:=0
func _initialize()->void:
 Engine.max_fps=10
 for arg:String in OS.get_cmdline_user_args():
  if arg=="--recover-publication":recovery_mode=true
  if arg.begins_with("--destination="):destination=arg.trim_prefix("--destination=")
  if arg.begins_with("--seed="):seed_value=int(arg.trim_prefix("--seed="))
  if arg.begins_with("--settlement-layout="):settlement_layout=arg.trim_prefix("--settlement-layout=")
  if arg.begins_with("--generator="):generator=int(arg.trim_prefix("--generator="))
  if arg.begins_with("--status-file="):status_path=arg.trim_prefix("--status-file=")
  if arg.begins_with("--cancel-file="):cancel_path=arg.trim_prefix("--cancel-file=")
 if not Launch.valid_slot(destination) or seed_value<0 or seed_value>2147483647 or generator not in [13,17,19] or settlement_layout not in ["connected","road","settlement"]:finish("failed","Invalid generation settings");return
 var worlds:=ProjectSettings.globalize_path("user://worlds")
 DirAccess.make_dir_recursive_absolute(worlds)
 lease=ClassDB.instantiate("NativeWorldArchive")
 if not lease.acquire(worlds.path_join(destination+".prepare")):finish("failed","Another generation owns this destination");return
 lease_owned=true
 var identity:=Crypto.new().generate_random_bytes(16).hex_encode()
 stage="combined_stage_"+identity
 report="user://generation_reports/"+identity
 DirAccess.make_dir_recursive_absolute(report)
 metadata={"version":1,"destination":destination,"stage":stage,"seed":seed_value,"generator":generator,"settlement_layout":settlement_layout,"phases":[]}
 if not cancel_path.is_empty() and FileAccess.file_exists(cancel_path):finish("cancelled","Cancelled before generation started");return
 if recovery_mode:
  status("recovering");publish_worker=Thread.new()
  if publish_worker.start(recover_world)!=OK:publish_worker=null;finish("failed","Cannot start recovery worker")
  return
 for suffix in [".trw",".trw.regions",".trw.models",".trw.water"]:
  if FileAccess.file_exists(worlds.path_join(destination+suffix)) or DirAccess.dir_exists_absolute(worlds.path_join(destination+suffix)):
   finish("failed","Destination already contains world data");return
 start_stage("creating")
func status(state:String,reason:String="")->void:
 if state not in ["creating","verifying"]:progress_detail={}
 phase=state
 if status_path.is_empty():return
 var value:Dictionary={"state":state,"slot":destination,"report":ProjectSettings.globalize_path(report),"reason":reason,"progress":progress_detail}
 var pending:=status_path+".pending"
 var file:=FileAccess.open(pending,FileAccess.WRITE)
 if file!=null:
  file.store_string(JSON.stringify(value));file.close();DirAccess.rename_absolute(pending,status_path)
func start_stage(state:String)->void:
 progress_detail={}
 status(state)
 var folder:=report.path_join(state);DirAccess.make_dir_recursive_absolute(folder)
 var fitted:=generator in [17,19]
 var args:=Launch.engine_prefix()+PackedStringArray(["--fullscreen","--resolution","1920x1080","--max-fps","60","--log-file",ProjectSettings.globalize_path(folder.path_join("engine.log")),"--script","res://addons/world_runtime/prepare_terrain_world.gd" if fitted else "res://addons/world_runtime/prepare_combined_world.gd","--","--world-slot="+stage,"--world-generator="+str(generator),"--world-seed="+str(seed_value),"--progress-file="+ProjectSettings.globalize_path(report.path_join(state+"_progress.json")),"--ground-cover","--actors","--vehicle-fleet","--checkpoint-layout=districts","--checkpoint-report="+ProjectSettings.globalize_path(report.path_join("checkpoint.json")),"--derived-cache=user://derived_046"])
 if fitted:
  if settlement_layout=="connected":args.append("--central-market")
  if settlement_layout!="settlement":args.append("--regional-connection")
  args.append_array(PackedStringArray(["--preparation-output="+ProjectSettings.globalize_path(report),"--save-terrain-lots" if state=="creating" else "--reopen-terrain-lots"]))
 if state=="verifying":args.append_array(PackedStringArray(["--reopen-checkpoint","--gameplay-construction","--snapshot-readonly"]))
 child=OS.create_process(OS.get_executable_path(),args,false)
 if child<0:finish("failed","Could not start generation stage");return
 metadata.phases.append({"stage":state,"pid":child,"arguments":args,"started_usec":Time.get_ticks_usec()})
 deadline=Time.get_ticks_msec()+(540000 if state=="creating" else 270000)
 persist_metadata()
func _process(_delta:float)->bool:
 if publish_worker!=null:
  if publish_worker.is_alive():return false
  var result:Dictionary=publish_worker.wait_to_finish();publish_worker=null
  metadata["publication"]=result
  if not result.get("ok",false):finish("failed",str(result.get("reason","Publication failed")));return false
  if recovery_mode:
   if not result.get("recovered",false):finish("failed","No completed interrupted publication exists for this world name");return false
   var source:String=result.get("source","")
   if Launch.preparation_slot(source):
    presentation_report="user://generation_reports/"+source.trim_prefix("combined_stage_")
    var previous=JSON.parse_string(FileAccess.get_file_as_string(presentation_report.path_join("generation_plan_identity.json"))) if FileAccess.file_exists(presentation_report.path_join("generation_plan_identity.json")) else null
    if previous is Dictionary:seed_value=int(previous.get("seed",seed_value));generator=int(previous.get("generator",generator))
    var prior_run=JSON.parse_string(FileAccess.get_file_as_string(presentation_report.path_join("run.json"))) if FileAccess.file_exists(presentation_report.path_join("run.json")) else null
    if prior_run is Dictionary:settlement_layout=str(prior_run.get("settlement_layout","unknown"))
    else:settlement_layout="unknown"
   metadata["seed"]=seed_value;metadata["generator"]=generator;metadata["settlement_layout"]=settlement_layout
   metadata["recovered_source"]=source
  publish_presentation()
  finish("ready");return false
 if child<0:return false
 if not cancel_path.is_empty() and FileAccess.file_exists(cancel_path):
  OS.kill(child);child=-1;finish("cancelled","Unpublished staging retained for diagnosis");return false
 if Time.get_ticks_msec()>deadline:
  OS.kill(child);child=-1;finish("failed","Generation stage timed out; staging retained");return false
 if OS.is_process_running(child):
  if Time.get_ticks_msec()>=next_progress_poll:
   next_progress_poll=Time.get_ticks_msec()+500
   var observed:=preload("res://addons/world_runtime/generation_progress.gd").read(report.path_join(phase+"_progress.json"))
   if observed!=progress_detail:progress_detail=observed;status(phase)
  return false
 var exit_code:=OS.get_process_exit_code(child);child=-1
 var log:=FileAccess.get_file_as_string(report.path_join(phase).path_join("engine.log"))
 var token:="TERRAIN_LOT_WORLD_REVIEW failures=0" if phase=="creating" else "TERRAIN_LOT_REOPEN failures=0"
 if generator==13:token="COMBINED_PREPARATION failures=0"
 metadata.phases[-1]["exit_code"]=exit_code
 if exit_code!=0 or not token in log or "SCRIPT ERROR:" in log or "ERROR:" in log:
  finish("failed","Generation or restoration check failed; see stage log");return false
 if phase=="creating":start_stage("verifying");return false
 status("publishing");persist_metadata()
 publish_worker=Thread.new()
 if publish_worker.start(publish_world)!=OK:publish_worker=null;finish("failed","Cannot start publication worker")
 return false
func persist_metadata()->void:
 if report.is_empty():return
 var file:=FileAccess.open(report.path_join("run.json"),FileAccess.WRITE)
 if file!=null:file.store_string(JSON.stringify(metadata,"  "));file.close()
func recover_world()->Dictionary:
 var archive=ClassDB.instantiate("NativeWorldArchive")
 return archive.recover_world(ProjectSettings.globalize_path("user://worlds"),destination)
func publish_world()->Dictionary:
 var archive=ClassDB.instantiate("NativeWorldArchive")
 return archive.clone_world(ProjectSettings.globalize_path("user://worlds"),stage,destination)
func publish_presentation()->void:
 var cache_source:String=str(metadata.get("recovered_source",stage))
 metadata["terrain_map_cache"]=preload("res://addons/world_runtime/survey_patch_cache.gd").promote(cache_source,destination)
 var source_report:=report if presentation_report.is_empty() else presentation_report
 var prefix:="user://worlds/"+destination
 var count:=0
 DirAccess.make_dir_recursive_absolute(prefix+".preview")
 for name:String in ["north","road","market"]:
  var image:=source_report.path_join("loading_"+name+".png")
  if FileAccess.file_exists(image) and DirAccess.copy_absolute(image,prefix+".preview/"+name+".png")==OK:count+=1
 var file:=FileAccess.open(prefix+".presentation.json",FileAccess.WRITE)
 if file!=null:file.store_string(JSON.stringify({"created":int(Time.get_unix_time_from_system()),"seed":seed_value,"generator":generator,"settlement_layout":settlement_layout,"preview_count":count}));file.close()
 var identity:=source_report.path_join("generation_plan_identity.json")
 if FileAccess.file_exists(identity):DirAccess.copy_absolute(identity,prefix+".generation.json")
func finish(state:String,reason:String="")->void:
 if not report.is_empty():
  var file:=FileAccess.open(report.path_join("run.json"),FileAccess.WRITE)
  if file!=null:file.store_string(JSON.stringify(metadata,"  "));file.close()
 status(state,reason)
 if lease_owned and lease!=null:
  lease.release();lease=null;lease_owned=false
  DirAccess.remove_absolute("user://worlds/"+destination+".prepare.lock")
 print("GENERATION_JOB state=",state," reason=",reason)
 quit(0 if state=="ready" else 2 if state=="cancelled" else 1)
func _finalize()->void:
 if child>=0 and OS.is_process_running(child):OS.kill(child)
 if publish_worker!=null:publish_worker.wait_to_finish()

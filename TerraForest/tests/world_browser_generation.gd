# SPDX-License-Identifier: 0BSD
extends SceneTree
class ReviewBrowser extends "res://demo/worlds.gd":
 var opened:=PackedStringArray()
 func _open_game(args:PackedStringArray)->void:opened=args
 func start_preparation(result:Dictionary,slot:String)->void:
  if "--capture-generation-ui" in OS.get_cmdline_user_args():result.args.append("--capture-generation-ui")
  super.start_preparation(result,slot)
func _initialize()->void:run.call_deferred()
func run()->void:
 var browser:=ReviewBrowser.new();root.add_child(browser)
 var slot:="browser_seed50_%d"%Time.get_ticks_usec()
 browser.name_field.text=slot;browser.seed_field.value=50;browser.preset.select(0)
 var completed:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--completed-preparation="):completed=arg.trim_prefix("--completed-preparation=")
 if completed.is_empty():
  browser.world_tabs.current_tab=1;browser.start_preview();browser.launch_selected(true)
 else:
  var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(completed))
  slot=saved.slot;browser.preparation_slot=slot;browser.preparation_status=completed
  browser.preparation_gameplay=true;browser.preparation_pid=2147483647
  browser.preparation_job=preload("res://addons/world_runtime/scene_job.gd").new();browser.preparation_job.done=true;browser.add_child(browser.preparation_job)
 var deadline:=Time.get_ticks_msec()+560000
 var stayed_in_create:=true;var saw_progress:=false
 while browser.preparation_pid>=0 and Time.get_ticks_msec()<deadline:
  stayed_in_create=stayed_in_create and browser.world_tabs.current_tab==1 and browser.generation_screen==null and browser.preparation_panel.is_visible_in_tree()
  if browser.preparation_panel.bar.value>5:saw_progress=true
  await process_frame
 var ok:bool=browser.preparation_pid<0 and "--world-slot="+slot in browser.opened and "--gameplay-construction" in browser.opened and "--generation-handoff" in browser.opened
 ok=ok and FileAccess.file_exists("user://worlds/"+slot+".trw")
 ok=ok and (not completed.is_empty() or (stayed_in_create and saw_progress))
 var status:Variant=JSON.parse_string(FileAccess.get_file_as_string(browser.preparation_status)) if FileAccess.file_exists(browser.preparation_status) else null
 ok=ok and status is Dictionary and status.get("state","")=="ready"
 var timing_argument:="--loading-started-ms="+str(browser.preparation_started_unix_ms)
 ok=ok and browser.preparation_started_unix_ms>0 and timing_argument in browser.opened
 ok=ok and int(status.get("loading_started_ms",0))==browser.preparation_started_unix_ms
 var run_metadata:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(status.report).path_join("run.json")))
 ok=ok and timing_argument in run_metadata.phases[0].arguments
 var handoff:=browser.opened.duplicate()
 browser.opened.clear();browser.preparation_pid=OS.get_process_id()
 browser.launch_selected(true)
 ok=ok and browser.preparation_pid==OS.get_process_id()
 var failed_path:="user://browser_failure_%d.json"%Time.get_ticks_usec()
 var failed:=FileAccess.open(failed_path,FileAccess.WRITE);failed.store_string(JSON.stringify({"state":"failed","reason":"test verification rejection","report":"test report"}));failed.close()
 browser.preparation_status=failed_path;browser.preparation_pid=2147483647;browser.preparation_poll=0
 browser.preparation_job=preload("res://addons/world_runtime/scene_job.gd").new();browser.preparation_job.done=true;browser.add_child(browser.preparation_job)
 browser._process(1)
 ok=ok and browser.opened.is_empty() and browser.notice.text.contains("test verification rejection")
 browser.opened=handoff
 var notice:String=browser.notice.text
 var host:Node=browser.session;browser.free()
 var saw_regular_loading:=false
 if not handoff.is_empty():
  host.open_world(handoff)
  deadline=Time.get_ticks_msec()+90000
  while Time.get_ticks_msec()<deadline:
   if current_scene!=null and current_scene.scene_file_path=="res://demo/world.tscn":
    if not current_scene.loading_active:break
    saw_regular_loading=saw_regular_loading or (not current_scene.loading_panel.embedded and current_scene.loading_from_generation and current_scene.loading_panel.bar.custom_minimum_size.y==18)
   await process_frame
  ok=ok and saw_regular_loading and current_scene!=null and not current_scene.loading_active
  if current_scene!=null:
   current_scene.shutdown_requested=true;await current_scene.terrain.shutdown_after_edits();current_scene.free()
 else:ok=false
 var file:=FileAccess.open("res://reports/world_browser_generation.json",FileAccess.WRITE);file.store_string(JSON.stringify({"ok":ok,"slot":slot,"opened":handoff,"status":status,"notice":notice,"stayed_in_create":stayed_in_create,"saw_progress":saw_progress,"regular_loading_handoff":saw_regular_loading},"  "));file.close()
 print("WORLD_BROWSER_GENERATION failures=",0 if ok else 1," slot=",slot)
 quit(0 if ok else 1)

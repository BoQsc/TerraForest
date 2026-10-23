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
 if completed.is_empty():browser.launch_selected(true)
 else:
  var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(completed))
  slot=saved.slot;browser.preparation_slot=slot;browser.preparation_status=completed
  browser.preparation_gameplay=true;browser.preparation_pid=2147483647
 var deadline:=Time.get_ticks_msec()+560000
 while browser.preparation_pid>=0 and Time.get_ticks_msec()<deadline:await process_frame
 var ok:bool=browser.preparation_pid<0 and "--world-slot="+slot in browser.opened and "--gameplay-construction" in browser.opened and "--generation-handoff" in browser.opened
 ok=ok and FileAccess.file_exists("user://worlds/"+slot+".trw")
 var status:Variant=JSON.parse_string(FileAccess.get_file_as_string(browser.preparation_status)) if FileAccess.file_exists(browser.preparation_status) else null
 ok=ok and status is Dictionary and status.get("state","")=="ready"
 var handoff:=browser.opened.duplicate()
 browser.opened.clear();browser.preparation_pid=OS.get_process_id()
 browser.launch_selected(true)
 ok=ok and browser.preparation_pid==OS.get_process_id()
 var failed_path:="user://browser_failure_%d.json"%Time.get_ticks_usec()
 var failed:=FileAccess.open(failed_path,FileAccess.WRITE);failed.store_string(JSON.stringify({"state":"failed","reason":"test verification rejection","report":"test report"}));failed.close()
 browser.preparation_status=failed_path;browser.preparation_pid=2147483647;browser.preparation_poll=0
 browser._process(1)
 ok=ok and browser.opened.is_empty() and browser.notice.text.contains("test verification rejection")
 browser.opened=handoff
 var file:=FileAccess.open("res://reports/world_browser_generation.json",FileAccess.WRITE);file.store_string(JSON.stringify({"ok":ok,"slot":slot,"opened":browser.opened,"status":status,"notice":browser.notice.text},"  "));file.close()
 print("WORLD_BROWSER_GENERATION failures=",0 if ok else 1," slot=",slot)
 browser.free();quit(0 if ok else 1)

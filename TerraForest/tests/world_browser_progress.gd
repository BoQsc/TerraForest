# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
 var browser=load("res://demo/worlds.gd").new();root.add_child(browser)
 browser.preparation_pid=OS.get_process_id();browser.preparation_slot="woodland_home"
 browser.preparation_status="user://progress_ui_%d.json"%Time.get_ticks_usec()
 browser.preparation_started_msec=Time.get_ticks_msec()
 var failures:=0
 var messages:Array=[]
 for stage in ["creating","verifying","publishing","ready"]:
  var file:=FileAccess.open(browser.preparation_status,FileAccess.WRITE);file.store_string(JSON.stringify({"state":stage}));file.close()
  browser.preparation_poll=0;browser._process(0.5)
  messages.append(browser.notice.text)
  if browser.preparation_pid!=OS.get_process_id() or not browser.notice.text.contains("Elapsed") or not browser.notice.text.contains("woodland_home"):failures+=1
  for frame in 3:await RenderingServer.frame_post_draw
  if stage=="verifying":root.get_texture().get_image().save_png("res://reports/world_browser_progress.png")
 if not messages[0].contains("Generating") or not messages[1].contains("Reopening") or not messages[2].contains("Publishing") or not messages[3].contains("World ready"):failures+=1
 var detailed:={"state":"creating","progress":{"stage":"Grading roads and foundations","completed":12,"total":240}}
 FileAccess.open(browser.preparation_status,FileAccess.WRITE).store_string(JSON.stringify(detailed))
 browser._update_preparation_notice()
 if not browser.notice.text.contains("Grading roads and foundations · 12 / 240"):failures+=1
 browser.preparation_pid=-1
 DirAccess.remove_absolute(ProjectSettings.globalize_path(browser.preparation_status))
 FileAccess.open("res://reports/world_browser_progress.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"messages":messages,"scope":"Actual browser polling/UI with controlled status records and live own-process sentinel; no world generation."},"  "))
 browser.free();print("WORLD_BROWSER_PROGRESS failures=",failures);quit(1 if failures else 0)

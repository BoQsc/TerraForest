# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
 var browser=load("res://demo/worlds.gd").new();root.add_child(browser)
 browser.preparation_pid=OS.get_process_id();browser.preparation_slot="woodland_home"
 browser.preparation_status="user://progress_ui_%d.json"%Time.get_ticks_usec()
 browser.preparation_started_msec=Time.get_ticks_msec()
 browser.preparation_job=preload("res://addons/world_runtime/scene_job.gd").new();browser.add_child(browser.preparation_job)
 browser.world_tabs.current_tab=1;browser._set_creation_busy(true);browser.preparation_panel.show();browser.preparation_panel.reset()
 var failures:=0
 var messages:Array=[]
 for stage in ["creating","verifying","publishing","ready"]:
  var file:=FileAccess.open(browser.preparation_status,FileAccess.WRITE);file.store_string(JSON.stringify({"state":stage}));file.close()
  browser.preparation_poll=0;browser._process(0.5)
  messages.append(browser.notice.text)
  if browser.preparation_pid!=OS.get_process_id() or not ":" in browser.notice.text or not browser.notice.text.contains("woodland_home"):failures+=1
  if browser.generation_screen!=null or not browser.preparation_panel.is_visible_in_tree() or browser.preparation_panel.bar.value>=100:failures+=1
  for frame in 3:await RenderingServer.frame_post_draw
  if stage=="verifying":root.get_texture().get_image().save_png("res://reports/world_browser_progress.png")
 if not messages[0].contains("Generating") or not messages[1].contains("Verifying") or not messages[2].contains("Publishing") or not messages[3].contains("Loading your world"):failures+=1
 browser.preparation_panel.reset()
 var detailed:={"state":"creating","progress":{"stage":"Grading roads and foundations","completed":12,"total":240,"details":{"work":"12 terrain segments finished"}}}
 FileAccess.open(browser.preparation_status,FileAccess.WRITE).store_string(JSON.stringify(detailed))
 browser._update_preparation_notice()
 if not browser.notice.text.contains("Grading roads and foundations · 12 / 240"):failures+=1
 if not is_equal_approx(browser.preparation_panel.bar.value,9.1) or not browser.preparation_panel.work.text.contains("12 terrain segments"):failures+=1
 for resolution:Vector2i in [Vector2i(1920,1080),Vector2i(1280,720)]:
  root.content_scale_size=resolution
  for frame in 8:await process_frame
  var bounds:=Rect2(Vector2.ZERO,Vector2(resolution))
  if not bounds.encloses(browser.preparation_panel.get_global_rect()) or not bounds.encloses(browser.cancel_button.get_global_rect()):failures+=1
  if browser.preparation_panel.bar.size.y!=6 or not browser.preparation_panel.clock_label.text.contains("Elapsed"):failures+=1
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/world_creation_progress_%dx%d.png"%[resolution.x,resolution.y])
 var stale:={"state":"verifying","progress":{"stage":"World generation complete","completed":0,"total":0}}
 FileAccess.open(browser.preparation_status,FileAccess.WRITE).store_string(JSON.stringify(stale));browser._update_preparation_notice()
 if not browser.notice.text.contains("Verifying saved") or browser.notice.text.contains("generation complete"):failures+=1
 browser.preparation_pid=-1
 DirAccess.remove_absolute(ProjectSettings.globalize_path(browser.preparation_status))
 FileAccess.open("res://reports/world_browser_progress.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"messages":messages,"scope":"Actual browser polling/UI with controlled status records and live own-process sentinel; no world generation."},"  "))
 browser.free();print("WORLD_BROWSER_PROGRESS failures=",failures);quit(1 if failures else 0)

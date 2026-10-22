# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
 var browser=load("res://demo/worlds.tscn").instantiate();root.add_child(browser)
 var tabs:TabContainer=browser.find_children("*","TabContainer",true,false)[0]
 tabs.current_tab=1
 browser.seed_field.value=42;browser.start_preview()
 var deadline:=Time.get_ticks_msec()+30000
 while browser.preview_worker!=null and Time.get_ticks_msec()<deadline:await process_frame
 var failures:=0
 if browser.preview_worker!=null or browser.preview_view.texture==null:failures+=1
 for i in 3:await process_frame
 var screen:=Rect2(Vector2.ZERO,Vector2(root.size))
 for control:Control in [browser.preview_view,browser.seed_field,browser.notice,browser.preview_button]:
  if not screen.encloses(control.get_global_rect()):failures+=1;print("OUTSIDE_SCREEN ",control.get_global_rect())
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/world_creation_ui.png")
  tabs.current_tab=0
  for i in 3:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/world_selector_ui.png")
 browser.free();print("WORLD_ENTRY_REVIEW failures=",failures);quit(1 if failures else 0)

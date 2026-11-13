# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,message:String)->void:
 print("PASS " if value else "FAIL ",message)
 if not value:failures+=1
func run()->void:
 var capture_dir:="res://reports"
 var world_seed:=1729662740
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--capture-dir="):capture_dir=argument.get_slice("=",1)
  if argument.begins_with("--seed="):world_seed=int(argument.get_slice("=",1))
 var registry=preload("res://addons/ui_sets/registry.gd")
 registry.session_id="survey"
 var browser=load("res://demo/worlds.tscn").instantiate()
 root.add_child(browser)
 browser.world_tabs.current_tab=1
 browser.seed_field.value=world_seed;browser.preview_due_ms=-1
 var reason:="Settlement 1 district 2: No complete terrain-fitting layout in bounded search" if world_seed==1729662740 else "No terrain-fitted coal mine with a connected trader round trip"
 browser.show_preview_failure(reason)
 for frame in 8:await process_frame
 check(browser.preview_empty.is_visible_in_tree() and browser.preview_empty.text.contains(reason) and browser.preview_empty.text.contains(str(world_seed)),"failure overlay contains the reason and reproducible seed")
 check(browser.preview_metrics.get_theme_color("font_color")==Color("f0a28f"),"failure heading uses error color")
 check(browser.preview_view.texture==null,"failed plan cannot retain a stale map")
 check(Rect2(Vector2.ZERO,Vector2(root.content_scale_size)).encloses(browser.preview_empty.get_global_rect()),"error overlay fits the visible viewport")
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(capture_dir.path_join("shuffle_preview_failure.png"))
 browser.invalidate_preview();browser.preview_due_ms=-1
 check(not browser.preview_empty.text.contains(reason) and browser.preview_metrics.get_theme_color("font_color")==preload("res://demo/world_creation_panel.gd").ACCENT,"changing recipe clears stale errors and restores neutral planning presentation")
 browser.show_preview_failure("")
 check(browser.preview_empty.text.contains("no error details"),"missing planner reason still produces an explicit message")
 browser.invalidate_preview()
 print("PREVIEW_UI_SETTINGS ",browser.selected_preview_key())
 var deadline:=Time.get_ticks_msec()+180000
 while (browser.preview_due_ms>=0 or browser.preview_loading or browser.preview_worker!=null) and Time.get_ticks_msec()<deadline:await process_frame
 check(browser.preview_view.texture!=null and not browser.preview_empty.visible,"reported seed recovers through the ordinary automatic preview worker")
 check(browser.preview_metrics.get_theme_color("font_color")==preload("res://demo/world_creation_panel.gd").ACCENT,"successful plan restores success presentation")
 for frame in 8:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(capture_dir.path_join("shuffle_preview_success.png"))
 print("PREVIEW_FAILURE_UI failures=",failures)
 quit(1 if failures else 0)

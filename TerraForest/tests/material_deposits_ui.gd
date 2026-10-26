extends SceneTree
var checks:=0
var failures:=0
var folder:="res://reports/material_deposits/ui"
func _initialize()->void:run.call_deferred()
func check(condition:bool,title:String)->void:
 checks+=1;print("PASS " if condition else "FAIL ",title)
 if not condition:failures+=1
func run()->void:
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--mineral-evidence="):folder=argument.trim_prefix("--mineral-evidence=")
 folder=ProjectSettings.globalize_path(folder);DirAccess.make_dir_recursive_absolute(folder)
 change_scene_to_file("res://demo/worlds.tscn");await scene_changed
 var browser=current_scene;browser.world_tabs.current_tab=1
 var deadline:=Time.get_ticks_msec()+60000
 while browser.preview_view.texture==null and Time.get_ticks_msec()<deadline:await process_frame
 check(browser.material_veins.button_pressed and browser.selected_options().material_veins==1,"Landscape mineral option defaults on")
 check(browser.material_veins.is_visible_in_tree() and Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(browser.material_veins.get_global_rect()),"mineral generation toggle is visible within the window")
 check(browser.preview_view.texture!=null,"actual generation preview with mineral markers completes")
 await RenderingServer.frame_post_draw
 check(root.get_texture().get_image().save_png(folder.path_join("generation.png"))==OK,"generation UI screenshot captured")
 browser.material_veins.button_pressed=false
 check(browser.selected_options().material_veins==0,"generation toggle disables mineral surface clues independently")
 browser.preview_due_ms=-1
 current_scene.free();await process_frame
 FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
 print("MATERIAL_DEPOSITS_UI checks=",checks," failures=",failures);quit(1 if failures else 0)

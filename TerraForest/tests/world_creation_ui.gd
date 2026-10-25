extends SceneTree
var failures:=0
func check(condition:bool,message:String)->void:
 if not condition:failures+=1
 print("PASS " if condition else "FAIL ",message)
func _initialize()->void:run.call_deferred()
func run()->void:
 if "--main-pack" in OS.get_cmdline_args():check(not FileAccess.file_exists("res://dist/reports/world_creation_1920x1080.png"),"pack excludes its own build and diagnostic output")
 var browser=load("res://demo/worlds.tscn").instantiate();root.add_child(browser)
 check(browser.buildable_ground.button_pressed and browser.buildable_roads.button_pressed and browser.selected_options().road_grid==3,"improved terrain and road preferences start enabled")
 check(browser.buildable_ground.get_parent()==browser.buildable_roads.get_parent() and browser.buildable_ground.get_parent().get_parent().name=="BuildingGridFit","related generation preferences share one named group")
 var tabs:TabContainer=browser.find_children("*","TabContainer",true,false)[0];tabs.current_tab=1
 browser.name_field.text="Alder_Reach";browser.biome.select(1);browser.district_count.select(1);browser.road_network.select(1);browser.invalidate_preview()
 browser.start_preview()
 var deadline:=Time.get_ticks_msec()+90000
 while browser.preview_worker!=null and Time.get_ticks_msec()<deadline:await process_frame
 check(browser.preview_worker==null and browser.preview_view.texture!=null,"new recipe renders actual native plan preview")
 check(browser.preview_metrics.text.contains("44 BUILDINGS"),"expanded towns report real building count")
 var options:Dictionary=browser.selected_options()
 var command:=preload("res://demo/world_launch.gd").command("recipe_launch_check",true,browser.Launch.INTEGRATED_PRESET,1703,true,"user://recipe_launch_check",true,"connected",true,options)
 var decoded:=preload("res://addons/world_runtime/world_recipe.gd").from_arguments(command.args)
 check(decoded.ok and decoded.options==options,"every visible option reaches launch recipe")
 var old_key:String=browser.selected_preview_key();browser.offroads.select(2);browser.offroads.item_selected.emit(2)
 check(browser.preview_view.texture==null and browser.selected_preview_key()!=old_key,"settings invalidate preview and its identity")
 browser.offroads.select(1);browser.invalidate_preview();browser.start_preview()
 while browser.preview_worker!=null and Time.get_ticks_msec()<deadline:await process_frame
 for resolution:Vector2i in [Vector2i(1920,1080),Vector2i(1280,720)]:
  root.content_scale_size=resolution
  for frame in 8:await process_frame
  var viewport:=Rect2(Vector2.ZERO,Vector2(resolution))
  check(viewport.encloses(browser.preview_button.get_global_rect()),"preview action stays on screen at "+str(resolution))
  check(viewport.encloses(browser.preview_view.get_global_rect()),"map stays on screen at "+str(resolution))
  for control:Button in browser.find_children("*","Button",true,false):
   if control.text=="Quit":check(viewport.encloses(control.get_global_rect()),"quit action stays on screen at "+str(resolution))
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/world_creation_%dx%d.png"%[resolution.x,resolution.y])
  var grid_scroll:ScrollContainer=browser.buildable_ground.get_parent().get_parent().get_parent().get_parent()
  grid_scroll.ensure_control_visible(browser.buildable_ground.get_parent().get_parent())
  for frame in 8:await process_frame
  check(grid_scroll.get_global_rect().encloses(browser.buildable_ground.get_global_rect()) and grid_scroll.get_global_rect().encloses(browser.buildable_roads.get_global_rect()),"grouped grid controls are reachable together at "+str(resolution))
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/world_creation_grid_%dx%d.png"%[resolution.x,resolution.y])
 root.content_scale_size=Vector2i(1920,1080)
 var categories:TabContainer=browser.find_children("*","TabContainer",true,false)[1];categories.current_tab=1
 for frame in 8:await process_frame
 for control:Control in [browser.settlement_count,browser.district_count,browser.road_network,browser.offroads]:check(Rect2(Vector2.ZERO,Vector2(1920,1080)).encloses(control.get_global_rect()),"settlement controls remain visible")
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/world_creation_settlements.png")
 FileAccess.open("res://reports/world_creation_ui.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"options":options,"metrics":browser.preview_metrics.text,"status":browser.preview_status.text},"  "))
 print("WORLD_CREATION_UI failures=",failures)
 browser.free();quit(1 if failures else 0)

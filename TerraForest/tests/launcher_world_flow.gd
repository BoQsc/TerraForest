# SPDX-License-Identifier: 0BSD
extends SceneTree
var slot := "LauncherUI_1703_Fixed"
var create := false
func _initialize()->void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--launcher-slot="):slot=arg.trim_prefix("--launcher-slot=")
  if arg=="--launcher-create":create=true
 run.call_deferred()
func run()->void:
 if not slot.begins_with("LauncherUI_"):quit(2);return
 if "--continue-last" in OS.get_cmdline_user_args():
  var candidates:=preload("res://demo/world_launch.gd").saved_slots()
  if candidates.is_empty() or candidates[0]!=slot:
   print("LAUNCHER_WORLD_FLOW refusing to continue a non-fixture world");quit(2);return
 change_scene_to_file("res://demo/worlds.tscn");await scene_changed
 var browser=current_scene
 if "--continue-last" not in OS.get_cmdline_user_args():
  while browser.library.loading:await process_frame
  if create:
   browser.name_field.text=slot;browser.seed_field.value=1703;browser.world_tabs.current_tab=1
   print("LAUNCHER_CREATE_UI recipe=",browser.world_style.get_item_text(browser.world_style.selected)," seed=",browser.seed_field.value)
   browser.generate_button.pressed.emit()
  else:
   var selected:=-1
   for i in browser.worlds.item_count:
    if browser.worlds.get_item_metadata(i)==slot:selected=i;break
   if selected<0:print("LAUNCHER_WORLD_FLOW missing owned fixture");quit(2);return
   browser.worlds.select(selected);browser.launch_selected(false)
 var deadline:=Time.get_ticks_msec()+(300000 if create else 120000)
 var report_at:=0
 var ready:=false
 while Time.get_ticks_msec()<deadline:
  if create and is_instance_valid(browser) and browser.preparation_pid<0 and FileAccess.file_exists(browser.preparation_status):
   var generation_state:Variant=JSON.parse_string(FileAccess.get_file_as_string(browser.preparation_status))
   if generation_state is Dictionary and generation_state.get("state","") in ["failed","cancelled"]:
    print("LAUNCHER_GENERATION_FAILURE ",JSON.stringify(generation_state));break
  if is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn":
   var game=current_scene
   if not game.loading_active:ready=game.terrain.save_slot==slot;break
   if game.lakes.water!=null:
    var water_state:Dictionary=game.lakes.statistics()
    if not str(water_state.get("equilibrium_failure","")).is_empty() or not str(water_state.get("surface_failure","")).is_empty() or not str(water_state.get("occupancy_failure","")).is_empty():
     print("LAUNCHER_WATER_FAILURE ",JSON.stringify(water_state));break
   if Time.get_ticks_msec()>report_at:
    print("LAUNCHER_LOADING ",JSON.stringify({"stage":game.loading_stage_text,"water":game.lakes.statistics() if game.lakes.water!=null else {},"mesh_task":game.lakes._mesh_task,"mesh_owned":game.lakes._mesh_job!=null,"busy":game.lakes._busy}))
    report_at=Time.get_ticks_msec()+10000
  await process_frame
 print("LAUNCHER_WORLD_FLOW ready=",ready," slot=",slot)
 if is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn":
  var game=current_scene
  if ready:print("LAUNCHER_WORLD_STATE ",JSON.stringify({"slot":game.terrain.save_slot,"water":game.lakes.statistics()}))
  game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
 quit(0 if ready else 1)

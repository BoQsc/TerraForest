extends "res://tests/window_session_flow.gd"
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
func run()->void:
 folder="res://reports/world_recipe_generation";DirAccess.make_dir_recursive_absolute(folder)
 original_window=root.get_window_id();original_handle=DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,original_window)
 change_scene_to_file("res://demo/worlds.tscn");await scene_changed
 var browser=current_scene
 var slot:="recipe_generated_"+Crypto.new().generate_random_bytes(8).hex_encode();slots.append(slot)
 browser.name_field.text=slot;browser.seed_field.value=1703;browser.biome.select(1);browser.settlement_count.select(2);browser.district_count.select(1);browser.road_network.select(1);browser.offroads.select(2)
 var options:Dictionary=browser.selected_options()
 browser.launch_selected(true)
 var status_path:String=browser.preparation_status
 await wait_for(func():
  if game_ready():return true
  if browser_ready() and current_scene.preparation_pid<0 and FileAccess.file_exists(status_path):
   var status=JSON.parse_string(FileAccess.get_file_as_string(status_path))
   return status is Dictionary and status.get("state","") in ["failed","cancelled"]
  return false,520)
 var ready:bool=game_ready()
 check(ready,"six-district production generation loads in same game window")
 if not ready:
  print("CUSTOM_GENERATION_STATUS ",FileAccess.get_file_as_string(status_path));await finish();return
 var game=current_scene
 var bytes:PackedByteArray=game.world_recipe.store.capture_snapshot()
 check(bytes==Recipe.encode(options) and game.ecosystem.biome_profile==1,"created world uses requested durable biome recipe")
 var region:Dictionary=game.generated_region.describe(1703,21)
 check(region.places.size()==6 and region.roads.size()>1000,"all six districts and regional routes publish to actual world map")
 check(game.structures.model("architecture/concrete_paving/v1").get_ids().is_empty(),"no legacy continuous decorative sidewalk meshes")
 var status:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(status_path))
 var metadata:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(status.report).path_join("run.json")))
 check(metadata.validation.ok and int(metadata.validation.section_bytes.world_recipe_v1)==28,"publication verifies native binary recipe alongside terrain and structures")
 check(metadata.phases.size()==1 and metadata.phases[0].mode=="same_window","generation introduces no second process or operating-system window")
 game.session_menu.set_open(false)
 await photograph("custom_world_playable")
 var region_bytes:PackedByteArray=game.generated_region.store.capture_snapshot()
 check(await leave(),"custom world saves and returns to selector")
 if not browser_ready():await finish();return
 check(await open_world(slot,false,1,42,true),"saved custom world reopens without reapplying UI options")
 if game_ready():
  check(current_scene.world_recipe.store.capture_snapshot()==bytes and current_scene.ecosystem.biome_profile==1,"custom biome survives save and reload")
  check(current_scene.generated_region.store.capture_snapshot()==region_bytes,"all district and road metadata survives reload exactly")
  await photograph("custom_world_reopened")
 check(windows_stable,"creation and reload preserve native window handle")
 FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"checks":checks,"slot":slot,"options":options,"report":status.report,"validation":metadata.validation,"window_stable":windows_stable},"  "))
 await finish()
func finish()->void:
 if is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn":
  current_scene.shutdown_requested=true;await current_scene.terrain.shutdown_after_edits()
 if is_instance_valid(current_scene):current_scene.free()
 await process_frame
 print("WORLD_RECIPE_GENERATION checks=",checks," failures=",failures," slots=",slots)
 quit(1 if failures else 0)

extends "res://tests/window_session_flow.gd"
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
var approved_records:Dictionary={}
var approved_lots:Dictionary={}

func verify_approved_records(game:Node)->void:
 for revision:String in approved_records:
  var lot:Dictionary=approved_lots[revision]
  game.session_menu.set_open(false)
  game.teleport(lot.entrance.segment.finish+Vector3.UP)
  var bounds:AABB=lot.asset.placement_bounds(lot.origin,lot.rotation)
  await wait_for(func():return not game.terrain.latest_error.is_empty() or (not game.loading_active and game.structures.is_collision_region_ready(bounds)),90)
  if not check(game.terrain.latest_error.is_empty() and not game.loading_active and game.structures.is_collision_region_ready(bounds),"approved "+revision+" streams in with complete collision"):return
  var records:PackedInt32Array=approved_records[revision]
  var exact:=true
  for offset in range(0,records.size(),4):
   var cell:=Vector3i(records[offset],records[offset+1],records[offset+2])
   var actual:int=game.structures.blocks.get_cell(cell)
   if actual!=records[offset+3]:print("APPROVED_CELL_MISMATCH ",revision," cell=",cell," expected=",records[offset+3]," actual=",actual);exact=false;break
  check(exact,"published world contains every approved "+revision+" block")

func run()->void:
 var grid_review:bool="--grid-review" in OS.get_cmdline_user_args()
 var use_defaults:bool="--default-recipe" in OS.get_cmdline_user_args() or grid_review
 folder="res://reports/world_recipe_generation_default" if use_defaults else "res://reports/world_recipe_generation"
 if grid_review:folder="res://reports/road_normalization/generation"
 DirAccess.make_dir_recursive_absolute(folder)
 FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":1,"state":"running","slot":""}))
 original_window=root.get_window_id();original_handle=DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,original_window)
 change_scene_to_file("res://demo/worlds.tscn");await scene_changed
 var browser=current_scene
 var slot:="recipe_generated_"+Crypto.new().generate_random_bytes(8).hex_encode();slots.append(slot)
 if grid_review:slot="GridPreference_1703_"+Crypto.new().generate_random_bytes(4).hex_encode();slots[-1]=slot
 browser.name_field.text=slot;browser.seed_field.value=1703
 if not use_defaults:browser.biome.select(1);browser.settlement_count.select(2);browser.district_count.select(1);browser.road_network.select(1);browser.offroads.select(2)
 var options:Dictionary=browser.selected_options()
 if use_defaults:check(options==Recipe.DEFAULTS,"untouched world browser uses the published two-settlement defaults")
 browser.launch_selected(true)
 var status_path:String=browser.preparation_status
 await wait_for(func():
  if game_ready():return true
  if browser_ready() and current_scene.preparation_pid<0 and FileAccess.file_exists(status_path):
   var status=JSON.parse_string(FileAccess.get_file_as_string(status_path))
   return status is Dictionary and status.get("state","") in ["failed","cancelled"]
  return false,520)
 var ready:bool=game_ready()
 check(ready,"production generation loads in same game window")
 if not ready:
  print("CUSTOM_GENERATION_STATUS ",FileAccess.get_file_as_string(status_path));await finish();return
 var game=current_scene
 var bytes:PackedByteArray=game.world_recipe.store.capture_snapshot()
 check(bytes==Recipe.encode(options) and game.ecosystem.biome_profile==options.biome,"created world uses requested durable biome recipe")
 check(game.construction_inventory.gameplay and game.ground_enabled and game.world_vehicle.fleet_enabled and "--actors" in Options.arguments(),"normal gameplay construction, vegetation, actors and vehicles are enabled")
 var region:Dictionary=game.generated_region.describe(1703,23)
 check(region.places.size()==options.settlements*options.districts and not region.roads.is_empty(),"all requested districts and regional routes publish to actual world map")
 check(game.structures.model("architecture/concrete_paving/v1").get_ids().is_empty(),"no legacy continuous decorative sidewalk meshes")
 var status:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(status_path))
 var metadata:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(status.report).path_join("run.json")))
 check(metadata.validation.ok and int(metadata.validation.section_bytes.world_recipe_v1)==bytes.size(),"publication verifies native binary recipe alongside terrain and structures")
 check(metadata.phases.size()==1 and metadata.phases[0].mode=="same_window","generation introduces no second process or operating-system window")
 var worker:=Thread.new()
 worker.start(Plan.build.bind(1703,23,true,true,"user://approved_default_plan_"+slot,options))
 while worker.is_alive():await process_frame
 var planned:Dictionary=worker.wait_to_finish()
 if check(planned.get("ok",false),"reconstruct exact approved-building plan independently"):
  var expected_region:RefCounted=ClassDB.instantiate("NativeGeneratedRegion")
  check(expected_region.set_plan(1703,23,planned.navigation.places,planned.navigation.roads) and expected_region.capture_snapshot()==game.generated_region.store.capture_snapshot(),"every published district and road matches the independently rebuilt native plan")
  for site:Dictionary in planned.sites:
   for lot:Dictionary in site.lots:
    var revision:String=lot.asset.get_meta("approved_revision","")
    if revision not in ["A2 R2","B1 R1","B2 R2"] or approved_records.has(revision):continue
    var world_asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
    if check(world_asset.compose([lot.asset],PackedInt32Array([0,lot.origin.x,lot.origin.y,lot.origin.z,lot.rotation])),"transform approved "+revision+" into generated lot"):
     approved_records[revision]=world_asset.get_records()
     approved_lots[revision]=lot
 check(approved_records.size()==3,"new world includes A2 cottage, B1 hipped shop and B2 thin-roof shop")
 await verify_approved_records(game)
 game.session_menu.set_open(false)
 await photograph("custom_world_playable")
 var region_bytes:PackedByteArray=game.generated_region.store.capture_snapshot()
 check(await leave(),"custom world saves and returns to selector")
 if not browser_ready():await finish();return
 browser=current_scene
 for index in browser.worlds.item_count:
  if browser.worlds.get_item_metadata(index)==slot:browser.worlds.select(index)
 browser.launch_selected(false)
 check(await wait_for(game_ready,90),"saved world reopens through the selector without reapplying UI options")
 if game_ready():
  check(current_scene.world_recipe.store.capture_snapshot()==bytes and current_scene.ecosystem.biome_profile==options.biome,"requested biome survives save and reload")
  check(current_scene.generated_region.store.capture_snapshot()==region_bytes,"all district and road metadata survives reload exactly")
  await verify_approved_records(current_scene)
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

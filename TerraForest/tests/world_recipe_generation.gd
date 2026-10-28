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
 var city_recipe:bool="--city-recipe" in OS.get_cmdline_user_args()
 var footprint_review:bool="--footprint-review" in OS.get_cmdline_user_args()
 var grid_review:bool="--grid-review" in OS.get_cmdline_user_args() or footprint_review
 var use_defaults:bool="--default-recipe" in OS.get_cmdline_user_args() or grid_review
 folder="res://reports/world_recipe_generation_default" if use_defaults else "res://reports/world_recipe_generation"
 if city_recipe:folder="res://reports/world_generator_city"
 if grid_review:folder="res://reports/road_normalization/generation"
 DirAccess.make_dir_recursive_absolute(folder)
 FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":1,"state":"running","slot":""}))
 original_window=root.get_window_id();original_handle=DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,original_window)
 change_scene_to_file("res://demo/worlds.tscn");await scene_changed
 var browser=current_scene
 var slot:="recipe_generated_"+Crypto.new().generate_random_bytes(8).hex_encode();slots.append(slot)
 if grid_review:slot="GridPreference_1703_"+Crypto.new().generate_random_bytes(4).hex_encode();slots[-1]=slot
 browser.name_field.text=slot;browser.seed_field.value=1703
 if city_recipe:browser.world_style.select(4);browser.world_style.item_selected.emit(4)
 elif not use_defaults:browser.biome.select(1);browser.settlement_count.select(2);browser.district_count.select(1);browser.road_network.select(1);browser.offroads.select(2)
 var options:Dictionary=browser.selected_options()
 var generator:int=Launch.terrain_generator(browser.ocean.button_pressed,browser.buildable_ground.button_pressed)
 if use_defaults:check(options==Recipe.DEFAULTS,"untouched world browser uses the published two-settlement defaults")
 check(browser.material_veins.button_pressed and options.material_veins==1,"material veins are enabled by default")
 browser.material_veins.button_pressed=false
 check(browser.selected_options().material_veins==0,"material veins can be disabled independently")
 browser.material_veins.button_pressed=true
 if footprint_review:
  options.road_grid=3
  var request:Dictionary=Launch.command(slot,true,browser.preset.get_selected_id(),1703,browser.gameplay.button_pressed,"user://worlds",browser.ocean.button_pressed,"connected",browser.buildable_ground.button_pressed,options)
  if not check(request.get("ok",false),"experimental native policy has a valid generation request"):await finish();return
  browser.start_preparation(request,slot)
 else:browser.launch_selected(true)
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
 var grid_settings:Node=game.session_menu.pages["Player"].get_node_or_null("BuildingGridFit")
 check(grid_settings!=null and grid_settings.find_children("*","CheckButton",true,false).size()==1,"placement preference belongs to the Player building-grid group")
 var bytes:PackedByteArray=game.world_recipe.store.capture_snapshot()
 check(bytes==Recipe.encode(options) and game.ecosystem.biome_profile==options.biome,"created world uses requested durable biome recipe")
 check(game.construction_inventory.gameplay and game.ground_enabled and game.world_vehicle.fleet_enabled and "--actors" in Options.arguments(),"normal gameplay construction, vegetation, actors and vehicles are enabled")
 var region:Dictionary=game.generated_region.describe(1703,generator)
 check(region.places.size()==options.settlements*options.districts and not region.roads.is_empty(),"all requested districts and regional routes publish to actual world map")
 check(game.structures.model("architecture/concrete_paving/v1").get_ids().is_empty(),"no legacy continuous decorative sidewalk meshes")
 var status:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(status_path))
 var metadata:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(status.report).path_join("run.json")))
 check(metadata.validation.ok and int(metadata.validation.section_bytes.world_recipe_v1)==bytes.size(),"publication verifies native binary recipe alongside terrain and structures")
 check(metadata.phases.size()==1 and metadata.phases[0].mode=="same_window","generation introduces no second process or operating-system window")
 var worker:=Thread.new()
 worker.start(Plan.build.bind(1703,generator,true,true,"user://approved_default_plan_"+slot,options))
 while worker.is_alive():await process_frame
 var planned:Dictionary=worker.wait_to_finish()
 if check(planned.get("ok",false),"reconstruct exact approved-building plan independently"):
  var expected_region:RefCounted=ClassDB.instantiate("NativeGeneratedRegion")
  check(expected_region.set_plan(1703,generator,planned.navigation.places,planned.navigation.roads) and expected_region.capture_snapshot()==game.generated_region.store.capture_snapshot(),"every published district and road matches the independently rebuilt native plan")
  for site:Dictionary in planned.sites:
   for lot:Dictionary in site.lots:
    var revision:String=lot.asset.get_meta("approved_revision","")
    if revision not in ["A2 R2","B1 R1","B2 R2","C1 R1"] or approved_records.has(revision):continue
    var world_asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
    if check(world_asset.compose([lot.asset],PackedInt32Array([0,lot.origin.x,lot.origin.y,lot.origin.z,lot.rotation])),"transform approved "+revision+" into generated lot"):
     approved_records[revision]=world_asset.get_records()
     approved_lots[revision]=lot
 check(approved_records.size()==4,"new world includes approved A2 cottage, both shops and additional C1 house")
 var mineral_bytes:PackedByteArray=game.material_deposits.store.capture_snapshot()
 var deposits:Array=game.material_deposits.describe(1703,generator)
 check(not deposits.is_empty() and deposits.size()==planned.get("material_deposits",[]).size(),"generated mineral metadata matches the independently planned geology")
 var mineral_count:=0
 for asset:String in preload("res://addons/world_runtime/material_deposits.gd").KEYS.values():mineral_count+=game.structures.model(asset).region_stats().get("logical_instances",0)
 check(mineral_count==deposits.size(),"every generated deposit has one persistent mineral stone, including unloaded regions")
 print("GENERATED_MINERALS count=",deposits.size()," logical_instances=",mineral_count," native_plan_ms=",planned.get("mineral_plan_ms",-1))
 game.app_focused=true;game.world_map.set_open(true);game.world_map.view.overview()
 check(game.world_map.deposits.size()==deposits.size(),"production map publishes all material deposits")
 var atlas=game.world_map
 check(await wait_for(func():return atlas.texture!=null and atlas.updates.identity_checked and atlas.updates.dirty.is_empty() and atlas.updates.pending.is_empty() and atlas.updates.io==null and atlas.water_survey.complete and atlas.block_survey.complete and atlas.model_survey.complete and atlas.water_survey.io==null and atlas.block_survey.io==null and atlas.model_survey.io==null,90),"complete generated map includes terrain, water, blocks and objects")
 check(not atlas.show_roads and not atlas.show_deposits and not atlas.show_places and not atlas.show_grid,"generated world opens on physical map without annotations")
 await photograph("material_map")
 game.destination_guide.track(atlas.places[0])
 check(atlas.view.visible_destinations(atlas.places,false)==[atlas.places[0]],"tracked destination remains visible with place annotations off")
 game.destination_guide.clear()
 for setting:String in ["show_roads","show_deposits","show_places","show_grid"]:
  var toggle:CheckBox=atlas.panel.find_child(setting,true,false)
  toggle.button_pressed=true
 check(atlas.show_roads and atlas.show_deposits and atlas.show_places and atlas.show_grid,"optional annotation controls operate independently")
 await photograph("annotated_map")
 for setting:String in ["show_roads","show_deposits","show_places","show_grid"]:atlas.panel.find_child(setting,true,false).button_pressed=false
 game.world_map.set_open(false)
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
  check(current_scene.material_deposits.store.capture_snapshot()==mineral_bytes,"material-deposit metadata survives full world save/reload exactly")
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

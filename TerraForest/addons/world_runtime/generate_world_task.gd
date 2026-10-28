# SPDX-License-Identifier: 0BSD
extends "res://addons/world_runtime/scene_task.gd"
# Production world creation. Developer review uses the compatibility wrapper.
var qualification:=false
var seed_value:=42
var output_dir:="res://reports"
var progress_path:=""
var generation_screen:CanvasLayer
var generation_cancel_path:=""
var saved_map_stamps:Dictionary={}
var planning_worker:Thread
var world_options:Dictionary={}
const Progress=preload("res://addons/world_runtime/generation_progress.gd")
func progress(stage:String,completed:int=0,total:int=0,details:Dictionary={})->void:
 progress_changed.emit(stage,completed,total,details)
 Progress.write(progress_path,stage,completed,total,details)
 if generation_screen!=null:generation_screen.update_stage(stage,completed,total,details)
func _initialize()->void:run.call_deferred()
func _finalize()->void:
 if planning_worker!=null and planning_worker.is_started():planning_worker.wait_to_finish()
func wait_generation_data(game:Node,seconds:float)->bool:
 var deadline:=Time.get_ticks_msec()+int(seconds*1000);var next_poll:=0;var previous:Dictionary={}
 var captured_bake:=false
 while not (game.terrain.world_ready and game.terrain.snapshot_restore_ok) and Time.get_ticks_msec()<deadline and not cancelled():
  if not game.terrain.latest_error.is_empty():return false
  if Time.get_ticks_msec()>=next_poll:
   next_poll=Time.get_ticks_msec()+100
   var diagnostic:Dictionary=game.terrain.backend.startup_diagnostics()
   var native_progress:Dictionary=diagnostic.get("terrain_bake",{})
   var water_progress:Dictionary=diagnostic.get("lake_bake",{})
   var observed:Dictionary={"terrain":native_progress,"water":water_progress,"phase":diagnostic.phase}
   if observed!=previous:
    if native_progress.get("state",0)==1:progress("Building roads and foundations",native_progress.completed,native_progress.total,native_progress)
    elif water_progress.get("status",0)==1:progress("Preparing water sources",0,0,water_progress)
    elif native_progress.get("state",0)==2:progress("Preparing generated world data")
    previous=observed
   if not captured_bake and native_progress.get("state",0)==1 and "--capture-generation-ui" in PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args())):
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output_dir.path_join("generation_baking.png"));captured_bake=true
  await process_frame
 return game.terrain.world_ready and game.terrain.snapshot_restore_ok
func ready_world(game:Node)->bool:
 return await wait_until(func():return not game.loading_active,120)
func capture_loading_view(game:Node,name:String)->Error:
 return await preload("res://addons/world_runtime/world_presentation.gd").capture(game,root,output_dir.path_join("loading_"+name+".png"))
func snapshot_signature(game:Node)->Dictionary:
 var water:PackedByteArray=game.lakes.capture_snapshot()
 var result:Dictionary={"water":preload("res://addons/world_runtime/survey_cache.gd").digest(water).hex_encode(),"blocks":block_signature(game),"region":Marshalls.raw_to_base64(game.generated_region.store.capture_snapshot())}
 result["material_deposits"]=Marshalls.raw_to_base64(game.material_deposits.store.capture_snapshot())
 for asset:String in game.structures._models:
  result[asset]=Marshalls.raw_to_base64(game.structures.model(asset).capture_snapshot())
 return result
func block_signature(game:Node)->Dictionary:
 var result:Dictionary={}
 var state:Dictionary=game.structures.blocks.capture_storage_state()
 var keys:PackedInt32Array=state.unavailable_keys
 var checksums:PackedByteArray=state.unavailable_checksums
 for i in keys.size()/3:
  result["%d,%d,%d" % [keys[i*3],keys[i*3+1],keys[i*3+2]]]=checksums.slice(i*32,(i+1)*32).hex_encode()
 for x in 32:
  for y in 4:
   for z in 32:
    var key:="%d,%d,%d" % [x,y,z]
    if result.has(key):continue
    var packet:PackedByteArray=game.structures.blocks.capture_region(Vector3i(x,y,z))
    if packet.size()>=100 and packet.decode_u32(32)>0:result[key]=packet.slice(packet.size()-32).hex_encode()
 return result
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func wait_until(condition:Callable,seconds:float)->bool:
 var deadline:int=Time.get_ticks_msec()+int(seconds*1000)
 while not condition.call() and Time.get_ticks_msec()<deadline and not cancelled():await process_frame
 return condition.call()
func run()->void:
 var generator:int=18 if "--coastal-inlet" in PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args())) else 17
 for arg:String in PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args())):
  if arg.begins_with("--world-seed="):seed_value=int(arg.trim_prefix("--world-seed="))
  if arg.begins_with("--world-generator="):generator=int(arg.trim_prefix("--world-generator="))
  if arg.begins_with("--progress-file="):progress_path=arg.trim_prefix("--progress-file=")
  if arg.begins_with("--cancel-file="):generation_cancel_path=arg.trim_prefix("--cancel-file=")
  if arg.begins_with("--preparation-output="):output_dir=arg.trim_prefix("--preparation-output=")
 if generator not in [17,18,19,20,21,22,23] or seed_value<0 or seed_value>2147483647:quit(1);return
 var recipe:=preload("res://addons/world_runtime/world_recipe.gd").from_arguments(PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args())))
 if not recipe.ok:print("INVALID_WORLD_RECIPE");quit(1);return
 world_options=recipe.options
 var native_lakes:=not qualification and generator in [17,19,20,21,22,23]
 DirAccess.make_dir_recursive_absolute(output_dir)
 if not qualification:
  generation_screen=preload("res://addons/world_runtime/generation_screen.gd").new();generation_screen.cancel_path=generation_cancel_path;root.add_child(generation_screen)
 if generation_screen!=null:generation_screen.diagnostics.context={"generation":{"seed":seed_value,"generator":generator,"output_path":ProjectSettings.globalize_path(output_dir),"progress_file":progress_path}}
 progress("Planning terrain, streets and building sites")
 await process_frame
 if not qualification and "--capture-generation-ui" in PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args())):
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(output_dir.path_join("generation_planning.png"))
 planning_worker=Thread.new()
 var arguments:=PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args()))
 var plan_progress:=preload("res://addons/world_runtime/world_plan_progress.gd").new()
 var build:=preload("res://addons/world_runtime/world_generation_plan.gd").build.bind(seed_value,generator,"--central-market" in arguments,"--regional-connection" in arguments,"user://generation_plans",world_options,plan_progress)
 if planning_worker.start(build)!=OK:planning_worker=null;print("WORLD_PLAN_WORKER_FAILED");quit(1);return
 var planning_frames:=0
 var observed:Dictionary={}
 while planning_worker.is_alive():
  var current:Dictionary=plan_progress.snapshot()
  if not current.is_empty() and current!=observed:progress("Planning terrain, streets and building sites",current.completed,current.total,current);observed=current
  await process_frame;planning_frames+=1
 var prepared:Dictionary=planning_worker.wait_to_finish();planning_worker=null
 if not prepared.get("ok",false):print("WORLD_PLAN_FAILED ",prepared);quit(1);return
 var plan:Dictionary=prepared.plan
 var works:Dictionary=prepared.works
 var market:Dictionary=prepared.market
 var connection:Dictionary=prepared.connection
 var sites:Array=prepared.get("sites",[plan,market])
 print("WORLD_PLAN digest=",prepared.plan_digest," cache_hit=",prepared.cache_hit," ms=",prepared.worker_ms," planning_frames=",planning_frames)
 FileAccess.open(output_dir.path_join("generation_plan_identity.json"),FileAccess.WRITE).store_string(JSON.stringify({"version":prepared.version,"seed":seed_value,"generator":generator,"digest":prepared.plan_digest,"options":world_options}))

 if cancelled():quit(2);return
 var game=load("res://demo/world.tscn").instantiate()
 var bake:bool="--save-terrain-lots" in PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args()))
 var reopen:bool="--reopen-terrain-lots" in PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args()))
 if bake:
  var slot:=""
  for arg:String in PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args())):
   if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
  if slot.is_empty() or FileAccess.file_exists("user://worlds/"+slot+".trw"):
   print("REFUSING_EXISTING_OR_UNNAMED_BAKE");game.free();quit(1);return
 var offline_grading:=bake and not "--interactive-generation-grading" in PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args()))
 if not qualification and not game.configure_generation_spawn(plan.roads[4].start):print("GENERATION_SPAWN_REJECTED");game.free();quit(1);return
 if not qualification:game.terrain.diagnostics_pause_streaming=true
 if native_lakes and not game.terrain.backend.configure_initial_lake_bake():print("OFFLINE_LAKE_JOB_UNAVAILABLE");game.free();quit(1);return
 if offline_grading:
  var packets:=preload("res://addons/world_runtime/generation_earthworks.gd").packets(works.segments,prepared.get("material_deposits",[]))
  if not game.terrain.backend.configure_initial_earthworks(packets,prepared.plan_digest,not qualification):print("OFFLINE_PACKETS_REJECTED");game.free();quit(1);return
  progress("Baking roads, foundations and connected mineral veins before terrain loading")
 game.lakes.offline_preparation=true;game.model_region_paging=false;game.temporary_world=not bake;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not qualification:
  game.set_process_input(false);game.set_process_unhandled_input(false);game.set_process_unhandled_key_input(false);game.set_process_shortcut_input(false)
  generation_screen.reparent(game)
  generation_screen.diagnostics.provider=preload("res://addons/world_runtime/loading_diagnostics.gd").snapshot.bind(game)
  generation_screen.diagnostics.context["plan"]={"digest":prepared.plan_digest,"cache_hit":prepared.cache_hit,"worker_ms":prepared.worker_ms,"version":prepared.version}
  game.ecosystem.set_process(false);game.ground_cover.set_process(false);game.vegetation.set_process(false)
 progress("Initializing generated terrain data" if not qualification else "Loading terrain and collision")
 if offline_grading and not qualification:
  progress("Building roads and foundations",0,works.segments.size())
  await process_frame
  if not game.terrain.backend.admit_initial_generation():print("OFFLINE_JOB_ADMISSION_REJECTED");game.free();quit(1);return
 var initialized:bool=await ready_world(game) if qualification else await wait_generation_data(game,60)
 if not initialized or game.terrain.backend.world_generator!=generator:print("WRONG_WORLD");quit(1);return
 if not reopen and not world_options.is_empty() and not game.world_recipe.configure(world_options):print("WORLD_RECIPE_SAVE_FAILED");game.free();quit(1);return
 if native_lakes and not game.terrain.backend.initial_lakes_result.get("ok",false):print("OFFLINE_LAKE_DATA_FAILED ",game.terrain.backend.initial_lakes_result);game.free();quit(1);return
 progress("Loading water sources")
 if not await wait_until(func():return game.lakes.statistics().ready==game.lakes.statistics().lakes and not game.lakes.capture_snapshot().is_empty(),120):print("GENERATED_WATER_BAKE_FAILED ",game.lakes.statistics());game.free();quit(1);return
 if not qualification:
  FileAccess.open(output_dir.path_join("generated_lakes_bake.json"),FileAccess.WRITE).store_string(JSON.stringify(game.terrain.backend.initial_lakes_result))
 game.set_physics_process(false);game._clear_motion();game.terrain.autosave_timer=-3600.0
 progress("Baking terrain overview")
 var map_worker:=Thread.new()
 if map_worker.start(preload("res://addons/world_runtime/survey_cache.gd").prepare.bind(seed_value,generator))!=OK:
  print("CARTOGRAPHY_WORKER_FAILED");game.free();quit(1);return
 while map_worker.is_alive():await process_frame
 var map_result:Dictionary=map_worker.wait_to_finish()
 if generation_screen!=null:generation_screen.diagnostics.context["terrain_overview"]=map_result
 if not map_result.get("ok",false):print("CARTOGRAPHY_CACHE_FAILED");game.free();quit(1);return
 print("PREPARED_CARTOGRAPHY ",JSON.stringify(map_result))
 if reopen:
  progress("Verifying saved terrain, buildings and water")
  var expected=FileAccess.get_file_as_bytes(output_dir.path_join("terrain_lot_region_expected.bin"))
  if expected.is_empty() or game.generated_region.store.capture_snapshot()!=expected or game.generated_region.describe(seed_value,generator).is_empty():
   print("REGION_REOPEN_FAILED");game.free();quit(1);return
  var manifest=JSON.parse_string(FileAccess.get_file_as_string(output_dir.path_join("world_signature.json")))
  if not manifest is Dictionary or manifest.seed!=seed_value or manifest.generator!=generator or manifest.signature!=snapshot_signature(game):
   print("WORLD_CONTENT_REOPEN_FAILED");game.free();quit(1);return
  print("PASS exact saved buildings, furnishings, paving and navigation restore with selected generator")
  game.world_map.refresh_world()
  if not connection.is_empty():
   var middle:int=connection.points.size()/2
   game.teleport(connection.points[middle])
   if not await ready_world(game):quit(1);return
   game.set_physics_process(false);game._clear_motion()
   game.camera.global_position=connection.points[middle]+Vector3.UP*1.7
   game.camera.look_at(connection.points[middle+1]+Vector3.UP*1.7)
   for i in 150:await process_frame
   var roots:Array=[]
   for row:Dictionary in game.vegetation.renderer.roots.values():roots.append(row.t)
   var blocked:PackedByteArray=game.generated_region.store.placement_mask(roots,2.0)
   var count:=0
   for value in blocked:count+=value
   print("ROAD_TREE_OVERLAPS ",count," resident=",roots.size())
   if count!=0:game.free();quit(1);return
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(output_dir.path_join("terrain_lot_regional_ground.png"))
  progress("Baking saved world map layers")
  game.app_focused=true;game.world_map.set_open(true)
  var atlas:Node=game.world_map
  var map_ready:bool=await wait_until(func():
   if atlas.updates.image==null or not atlas.updates.cache_saved or atlas.updates.io!=null or not atlas.updates.dirty.is_empty() or not atlas.updates.pending.is_empty():return false
   for layer:Node in [atlas.water_survey,atlas.block_survey,atlas.model_survey]:
    if not layer.complete or layer.io!=null or layer.cache_hits+layer.cache_writes==0:return false
   return true,120)
  if not map_ready:print("WORLD_MAP_PREPARATION_FAILED ",atlas.status.text);game.free();quit(1);return
  print("PREPARED_WORLD_MAP water_hits=",atlas.water_survey.cache_hits," water_writes=",atlas.water_survey.cache_writes," visibility_calls=",atlas.water_survey.visibility_calls)
  atlas.view.overview();await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(output_dir.path_join("prepared_world_map.png"))
  atlas.set_open(false)
  print("TERRAIN_LOT_REOPEN failures=0 places=",game.world_map.places.size()," roads=",game.world_map.roads.size())
  game.free();quit();return
 var runner=preload("res://addons/structures/site_preparation.gd").new()
 var completed_edits:=0
 var last_progress_ms:=0
 if offline_grading:
  completed_edits=int(game.terrain.backend.initial_earthworks_result.get("completed",0))
  if completed_edits!=works.segments.size()+prepared.get("material_deposits",[]).size():print("OFFLINE_GRADING_INCOMPLETE");game.free();quit(1);return
  FileAccess.open(output_dir.path_join("earthworks_bake.json"),FileAccess.WRITE).store_string(JSON.stringify(game.terrain.backend.initial_earthworks_result))
 else:
  progress("Grading roads and foundations",0,works.segments.size())
  for offset in range(0,works.segments.size(),256):
   var batch:Dictionary={"ok":true,"segments":works.segments.slice(offset,mini(offset+256,works.segments.size())),"bounds":works.bounds}
   if not runner.begin(batch,game.terrain,func(_bounds:AABB)->String:return ""):quit(1);return
   var deadline:int=Time.get_ticks_msec()+90000
   while runner.status=="running" and Time.get_ticks_msec()<deadline and not cancelled():
    runner.tick(game.terrain,func(_bounds:AABB)->String:return "")
    if Time.get_ticks_msec()-last_progress_ms>=250:
     progress("Grading roads and foundations",completed_edits+runner.completed,works.segments.size());last_progress_ms=Time.get_ticks_msec()
    await process_frame
   if runner.status!="complete":print("PREPARATION_FAILED ",runner.status," ",runner.reason);quit(1);return
   completed_edits+=runner.completed
 if not offline_grading:
  var mineral_packets:=preload("res://addons/world_runtime/generation_earthworks.gd").packets([],prepared.get("material_deposits",[]))
  for packet:PackedByteArray in mineral_packets:
   if not game.terrain.edit(packet,Vector3.ZERO,Vector3.ZERO) or not await wait_until(func():return not game.terrain.pending_edit,60):
    print("MINERAL_CONNECTION_BAKE_FAILED");game.free();quit(1);return
 game.structure_mode=true;game.structure_rotation=0
 var all_lots:Array=[]
 for site:Dictionary in sites:all_lots.append_array(site.get("lots",[]))
 var completed_buildings:=0
 progress("Placing buildings and interiors",0,all_lots.size())
 for lot:Dictionary in all_lots:
  if cancelled():game.free();quit(2);return
  var index:int=game.structure_prefabs.find(lot.asset)
  if index<0:
   game._accept_composed_prefab({"ok":true,"asset":lot.asset});index=game.structure_prefab_index
  game.structure_prefab_index=index;game.structure_rotation=lot.rotation
  var doors:int=game.doors.collection.get_ids().size()
  var expected_doors:=0
  for attachment:Dictionary in lot.asset.get_model_attachments():
   if attachment.model=="architecture/wooden_door/v1":expected_doors+=1
  var placed:=false
  if qualification:
   game._begin_frontage_placement(lot.asset,lot.origin,true)
   placed=await wait_until(func():return game._foundation_placement.is_empty(),20)
  else:placed=await generate_prefab(game,lot)
  if not placed or game.doors.collection.get_ids().size()!=doors+expected_doors:
   print("BUILDING_FAILED ",lot.label," ",game.foundation_check.status);quit(1);return
  completed_buildings+=1;progress("Placing buildings and interiors",completed_buildings,all_lots.size())
 progress("Baking streets and location metadata")
 var total_plates:=0
 for site:Dictionary in sites:total_plates+=site.get("block_paving",{}).get("tiles",0)
 var completed_plates:=0
 for site:Dictionary in sites:
  if site.is_empty():continue
  var pavement:Dictionary=site.get("block_paving",{})
  if not pavement.get("ok",false):print("PAVING_PLAN_MISSING");quit(1);return
  var records:PackedInt32Array=pavement.records
  var plates=ClassDB.instantiate("NativeBlockPrefab")
  for offset in range(0,records.size(),4096):
   if cancelled():game.free();quit(2);return
   if not plates.configure(records.slice(offset,mini(offset+4096,records.size()))) or not game.structures.blocks.place_prefab(plates,Vector3i.ZERO,0,false):print("PAVING_FAILED");quit(1);return
   completed_plates+=mini(4096,records.size()-offset)/4
   progress("Baking destructible sidewalk plates",completed_plates,total_plates)
   await process_frame
 if not game.generated_region.publish_neighborhood(seed_value,plan,generator):print("REGION_PUBLICATION_FAILED");quit(1);return
 if not world_options.is_empty():
  var metadata:Dictionary=prepared.navigation
  if not game.generated_region.store.set_plan(seed_value,generator,metadata.places,metadata.roads):print("CUSTOM_MAP_FAILED");quit(1);return
 elif not connection.is_empty():
  var metadata:Dictionary=game.generated_region.store.get_plan()
  for i in range(1,connection.points.size()):metadata.roads.append({"a":connection.points[i-1],"b":connection.points[i],"width":8.0})
  if market.is_empty():
   metadata.places.append({"id":0,"title":"Central road arrival","detail":"Road end at the planned central site; settlement construction is unfinished.","position":connection.points[-1]})
  else:
   var market_metadata:Dictionary=game.generated_region.neighborhood_metadata(market,0,"Central market","Shops, workshops and homes around two connected streets.")
   metadata.places.append_array(market_metadata.places);metadata.roads.append_array(market_metadata.roads)
  if not game.generated_region.store.set_plan(seed_value,generator,metadata.places,metadata.roads):print("CONNECTION_MAP_FAILED");quit(1);return
 if generator==18:
  game.lakes.offline_preparation=true
  if preload("res://addons/volumetric_water/coastal_inlet.gd").prepare(game.lakes)<=0:print("COAST_FILL_REJECTED");quit(1);return
  if not await wait_until(func():return game.lakes.statistics().ready==1 and game.lakes.statistics().render_ready,120):print("COAST_FILL_TIMEOUT ",game.lakes.statistics());quit(1);return
  game.lakes.offline_preparation=false
  var region:Dictionary=game.generated_region.store.get_plan()
  region.places.append({"id":10,"title":"Western beach","detail":"First coastal inlet; offshore horizon is not navigable ocean yet.","position":preload("res://addons/volumetric_water/coastal_inlet.gd").ARRIVAL})
  if not game.generated_region.store.set_plan(seed_value,generator,region.places,region.roads):quit(1);return
 if int(world_options.get("material_veins",0))==1:
  progress("Placing mineral-bearing stones and map markers",0,prepared.get("material_deposits",[]).size())
  if not game.material_deposits.publish(seed_value,generator,prepared.get("material_deposits",[]),game.structures):print("MATERIAL_DEPOSITS_FAILED");quit(1);return
 game.ecosystem._structures_changed()
 game.ground_cover._exclusion_changed(works.bounds)
 game.terrain.changed_since_save=true
 game.world_map.refresh_world()
 var expected_places:int=sites.size() if not world_options.is_empty() else ((1 if connection.is_empty() else 2)+(1 if generator==18 else 0))
 if game.world_map.places.size()!=expected_places or game.world_map.roads.is_empty():print("BAKED_MAP_FAILED");quit(1);return
 game.construction_palette.survey_dialog.hide()
 var road:Dictionary=plan.roads[4]
 if not qualification:
  # Data generation precedes presentation. No terrain mesh/collision is loaded
  # for an empty draft and invalidated again while its buildings are inserted.
  game.terrain.diagnostics_pause_streaming=false
  game.ecosystem.set_process(true);game.ground_cover.set_process(true);game.vegetation.set_process(true)
  progress("Photographing the generated world",0,3 if not market.is_empty() else 2 if not connection.is_empty() else 1)
  if not await bake_photographs(game,plan,market,connection):game.free();quit(1);return
 else:
  progress("Capturing world photographs")
  var center:Vector3=plan.center
  center.y=plan.lots[5].origin.y
  game.teleport(center+Vector3(70,0,70))
  if not await ready_world(game):quit(1);return
  game.set_physics_process(false);game._clear_motion()
  game.camera.global_position=center+Vector3(95,65,95);game.camera.look_at(center+Vector3(0,3,0))
  for i in 150:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(output_dir.path_join("terrain_lot_world_overview.png"))
  road=plan.roads[4]
  game.camera.global_position=road.start+Vector3.UP*1.7;game.camera.look_at(road.finish+Vector3.UP*1.7)
  for i in 90:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(output_dir.path_join("terrain_lot_world_street.png"))
  await capture_loading_view(game,"north")
  if not connection.is_empty():
   var midpoint:Vector3=connection.points[connection.points.size()/2]
   game.teleport(midpoint)
   if not await ready_world(game):quit(1);return
   game.set_physics_process(false);game._clear_motion()
   game.camera.global_position=midpoint+Vector3(55,40,30);game.camera.look_at(midpoint)
   for i in 120:await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(output_dir.path_join("terrain_lot_regional_road.png"))
   await capture_loading_view(game,"road")
   game.teleport(road.start)
   if not await ready_world(game):quit(1);return
   game.set_physics_process(false);game._clear_motion()
  if not market.is_empty():
   game.teleport(market.center)
   if not await ready_world(game):quit(1);return
   game.set_physics_process(false);game._clear_motion()
   game.camera.global_position=market.center+Vector3(65,45,65)
   game.camera.global_position.y=market.lots[0].origin.y+45
   game.camera.look_at(Vector3(market.center.x,market.lots[0].origin.y+2,market.center.z))
   for i in 120:await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(output_dir.path_join("central_market_overview.png"))
   var market_road:Dictionary=market.roads[3]
   game.camera.global_position=market_road.start+Vector3.UP*1.7;game.camera.look_at(market_road.finish+Vector3.UP*1.7)
   for i in 90:await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(output_dir.path_join("central_market_street.png"))
   await capture_loading_view(game,"market")
   for lot:Dictionary in market.lots:
    if not lot.asset.get_meta("cellar_clearance",false):continue
    game.player_hud.set_open(false)
    var origin:=Vector3(lot.origin)
    FileAccess.open(output_dir.path_join("market_cellar_location.json"),FileAccess.WRITE).store_string(JSON.stringify({"origin":[lot.origin.x,lot.origin.y,lot.origin.z],"grade":lot.survey.grade,"arrival":[lot.entrance.segment.finish.x,lot.entrance.segment.finish.y,lot.entrance.segment.finish.z],"rotation":lot.rotation}))
    game.camera.global_position=origin+Vector3(12,10,16);game.camera.look_at(origin+Vector3(0,7,0))
    for i in 60:await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output_dir.path_join("market_cellar_exterior.png"))
    game.camera.global_position=origin+Vector3(-1,2.7,2);game.camera.look_at(origin+Vector3(-1,1.8,-2))
    for i in 30:await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output_dir.path_join("market_cellar_interior.png"))
   game.teleport(road.start)
   if not await ready_world(game):quit(1);return
   game.set_physics_process(false);game._clear_motion()
  # Short actual-player traversal along a sloping walkway; no jumping or flying.
  var direction:Vector3=(road.finish-road.start).normalized()
  var across:Vector3=Vector3.UP.cross(direction).normalized()
  var start:Vector3=road.start+direction*0.8+across*3.75
  var target:Vector3=road.finish-direction*0.8+across*3.75
  game.fly=false;game.needs_floor_spawn=false;game.player.position=start+Vector3.UP*0.08
  game.player.velocity=Vector3.ZERO;game.controls.clear(Time.get_ticks_usec())
  game.camera.position=Vector3(0,1.65,0);game.camera.rotation=Vector3.ZERO
  var arrived:=false
  for tick in 240:
   var offset:Vector3=target-game.player.position;offset.y=0
   if offset.length()<0.25 and game.player.is_on_floor():arrived=true;break
   game.yaw=atan2(-offset.x,-offset.z);game.player.rotation.y=game.yaw
   game.controls.set_key(KEY_W,offset.length()>0.15,Time.get_ticks_usec())
   await physics_frame;game.app_focused=true;game._physics_process(1.0/60)
  game.controls.clear(Time.get_ticks_usec())
  print("PAVEMENT_WALK arrived=",arrived," start=",start," target=",target," actual=",game.player.position)
  if not arrived:game.free();quit(1);return
  if generator==18:
   game.teleport(Vector3(39,43,1008))
   if not await ready_world(game):quit(1);return
   game.set_physics_process(false);game._clear_motion()
   game.camera.global_position=Vector3(39,44.7,1008);game.camera.look_at(Vector3(0,40,1008))
   for frame in 120:await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(output_dir.path_join("coastal_inlet.png"))
 if bake:
  progress("Saving generated world")
  if qualification:
   var file=FileAccess.open(output_dir.path_join("terrain_lot_region_expected.bin"),FileAccess.WRITE)
   file.store_buffer(game.generated_region.store.capture_snapshot());file.close()
   var manifest:=FileAccess.open(output_dir.path_join("world_signature.json"),FileAccess.WRITE)
   manifest.store_string(JSON.stringify({"seed":seed_value,"generator":generator,"signature":snapshot_signature(game)}));manifest.close()
  else:
   saved_map_stamps={"blocks":game.world_map.block_survey.current_stamp(),"models":game.world_map.model_survey.current_stamp(),"water":game.world_map.water_survey.current_stamp(),"terrain":game.terrain.density_revision}
   var saved:Dictionary={"done":false,"ok":false}
   game.terrain.save_completed.connect(func(ok:bool):saved.done=true;saved.ok=ok,CONNECT_ONE_SHOT)
   game.terrain.save_world()
   if not await wait_until(func():return saved.done,30) or not saved.ok:print("GENERATION_SAVE_FAILED");game.free();quit(1);return
   progress("Caching the saved world map")
   if not await bake_map_layers(game):game.free();quit(1);return
  game.shutdown_requested=true
  if not await game.terrain.shutdown_after_edits():print("BAKE_SAVE_FAILED");game.free();quit(1);return
 progress("World generation complete")
 print("TERRAIN_LOT_WORLD_REVIEW failures=0 buildings=" if qualification else "WORLD_GENERATED failures=0 buildings=",all_lots.size()," edits=",completed_edits)
 game.free();quit()

func bake_map_layers(game:Node)->bool:
 game.app_focused=true;game.world_map.refresh_world();game.world_map.set_open(true)
 var atlas:Node=game.world_map
 var ready:=false;var deadline:=Time.get_ticks_msec()+120000;var next_poll:=0
 while not ready and Time.get_ticks_msec()<deadline and not cancelled():
  var pending:=PackedStringArray()
  if atlas.updates.image==null or not atlas.updates.cache_saved or atlas.updates.io!=null or not atlas.updates.dirty.is_empty() or not atlas.updates.pending.is_empty():pending.append("terrain")
  for layer:Node in [atlas.water_survey,atlas.block_survey,atlas.model_survey]:
   if not layer.complete or layer.io!=null or layer.cache_hits+layer.cache_writes==0:pending.append(str(layer.caption))
  ready=pending.is_empty()
  if Time.get_ticks_msec()>=next_poll:
   next_poll=Time.get_ticks_msec()+250
   progress("Caching the saved world map",4-pending.size(),4,{"activity":"Preparing world map layers","work":"Remaining: "+", ".join(pending) if not ready else "Map layers ready; verifying saved identities","stage_fraction":0.8*float(4-pending.size())/4.0})
  if not ready:await process_frame
 atlas.set_open(false)
 if not ready:print("WORLD_MAP_GENERATION_FAILED ",atlas.status.text)
 if not ready:return false
 return await cache_for_playback(game,atlas)

func cache_for_playback(game:Node,atlas:Node)->bool:
 var block_stamp:String=atlas.block_survey.current_stamp()
 var model_stamp:String=atlas.model_survey.current_stamp()
 var water_stamp:String=atlas.water_survey.current_stamp()
 if saved_map_stamps.get("blocks")!=block_stamp or saved_map_stamps.get("models")!=model_stamp or saved_map_stamps.get("water")!=water_stamp or saved_map_stamps.get("terrain")!=game.terrain.density_revision:
  print("MAP_SAVED_STATE_CHANGED blocks=",saved_map_stamps.get("blocks")!=block_stamp," models=",saved_map_stamps.get("models")!=model_stamp," water=",saved_map_stamps.get("water")!=water_stamp," terrain=",saved_map_stamps.get("terrain")!=game.terrain.density_revision);return false
 progress("Caching the saved world map",0,0,{"activity":"Verifying map cache against the saved world","stage_fraction":0.8})
 var worker:=Thread.new()
 if worker.start(saved_map_certificates.bind(game.terrain.backend))!=OK:print("MAP_CERTIFICATE_WORKER_FAILED");return false
 while worker.is_alive():await process_frame
 var certificate:Dictionary=worker.wait_to_finish()
 if not certificate.get("ok",false) or block_stamp!=atlas.block_survey.current_stamp() or model_stamp!=atlas.model_survey.current_stamp() or water_stamp!=atlas.water_survey.current_stamp() or game.terrain.pending_edit:print("MAP_CERTIFICATE_FAILED ",certificate);return false
 var cache=preload("res://addons/world_runtime/survey_patch_cache.gd")
 var block_identity:String=certificate.blocks_identity+"|"+var_to_bytes(game.structures.blocks.global_transform).hex_encode()
 var parts:=PackedStringArray();var names:Array=game.structures._models.keys();names.sort()
 for name:String in names:
  if not certificate.models.has(name):print("MAP_CERTIFICATE_ASSET_MISSING ",name);return false
  var batch:Node3D=game.structures._models[name]
  parts.append(name+"|"+str(certificate.models[name])+"|"+var_to_bytes(batch.global_transform).hex_encode()+"|"+var_to_bytes(batch.survey_prototype_bounds()).hex_encode())
 var model_identity:String="|".join(parts).sha256_text()
 var aliases:Array=[[atlas.block_survey,block_identity],[atlas.model_survey,model_identity]]
 if certificate.has("water_identity"):aliases.append([atlas.water_survey,certificate.water_identity])
 var cached_layers:=0
 for row:Array in aliases:
  var layer:Node=row[0]
  progress("Caching the saved world map",0,0,{"activity":"Saving "+str(layer.caption)+" map cache","stage_fraction":0.85+0.15*float(cached_layers)/aliases.size()})
  var key:String=layer.cache_namespace+"|certified|"+atlas.updates.cache_identity+"|"+str(row[1])
  var pixels:PackedByteArray=layer.texture.get_image().get_data()
  var io:=Thread.new()
  if io.start(cache.write.bind(key,key,pixels,layer.cache_root,16 if layer.image_size==512 else 64,layer.image_size),Thread.PRIORITY_LOW)!=OK:print("MAP_ALIAS_WORKER_FAILED ",layer.caption);return false
  while io.is_alive():await process_frame
  var written:Dictionary=io.wait_to_finish()
  if not written.get("persisted",false):print("MAP_ALIAS_WRITE_FAILED ",layer.caption," ",written);return false
  cached_layers+=1
 return true

func saved_map_certificates(backend:RefCounted)->Dictionary:
 # Worker-only codec orchestration. Bind aliases to the published bytes rather
 # than generation's transient resident representations.
 var path:=ProjectSettings.globalize_path(backend.save_path)
 var raw:RefCounted=ClassDB.instantiate("NativeWorldArchive")
 var canonical:PackedByteArray=raw.read(path)
 var certificate:Dictionary=backend.snapshot_codec.map_certificates()
 if not certificate.get("ok",false):return {}
 if backend.world_generator not in [19,21,23]:
  var root_data:Dictionary=raw.decode(canonical)
  if not root_data.get("ok",false) or not root_data.sections.has("volumetric_water"):return {}
  var store:RefCounted=ClassDB.instantiate("NativeWaterRegionStore")
  if not store.open_store(path+".water"):return {}
  var bytes:PackedByteArray=store.expand_water_snapshot(root_data.sections.volumetric_water);store.close()
  if bytes.is_empty():return {}
  certificate["water_identity"]="snapshot-v1|"+preload("res://addons/world_runtime/survey_cache.gd").digest(bytes).hex_encode()
 return certificate if raw.read(path)==canonical else {}

func generate_prefab(game:Node,lot:Dictionary)->bool:
 # Foundation/clearance checks sample the authoritative native field, independent
 # of terrain render meshes and physics residency. Placement uses the same native
 # atomic prefab transaction as the editor, without editor selection/input state.
 var foundation:RefCounted=game.foundation_check
 if not foundation.begin(game.terrain,lot.asset,lot.origin,lot.rotation):return false
 var deadline:=Time.get_ticks_msec()+10000
 while foundation.status=="checking" and Time.get_ticks_msec()<deadline and not cancelled():
  foundation.tick(game.terrain)
  await process_frame
 if foundation.status!="supported":print("GENERATION_FOUNDATION_REJECTED ",lot.label," ",foundation.status);return false
 var placement:RefCounted=ClassDB.instantiate("NativePrefabPlacement")
 var result:Dictionary=placement.place(game.structures.blocks,lot.asset,lot.origin,lot.rotation,game.structures.model_collections(),[])
 if not result.get("ok",false):print("GENERATION_PREFAB_REJECTED ",lot.label," ",result)
 return result.get("ok",false)

func photograph_cover_status(game:Node)->Dictionary:
 var cover:Node=game.ground_cover
 var total:=0;var ready:=0
 var eye:Vector3=game.camera.global_position
 if cover!=null and cover.is_processing():
  for key:Vector2i in cover._wanted:
   var center:=Vector3(key.x*32+16,eye.y,key.y*32+16)
   if center.distance_squared_to(eye)<96.0*96.0:
    total+=1
    if cover.resident.has(key) and not cover._dirty.has(key):ready+=1
 return {"total":total,"ready":ready}

func photograph_ready(game:Node)->bool:
 if game.loading_active or game.terrain.pending_edit:return false
 var cover:Node=game.ground_cover
 if cover==null or not cover.is_processing():return true
 if cover._wanted.is_empty():return false
 var eye:Vector3=game.camera.global_position
 for key:Vector2i in cover._wanted:
  var center:=Vector3(key.x*32+16,eye.y,key.y*32+16)
  if center.distance_squared_to(eye)<96.0*96.0 and (not cover.resident.has(key) or cover._dirty.has(key)):return false
 return true

func bake_photographs(game:Node,plan:Dictionary,market:Dictionary,connection:Dictionary)->bool:
 var views:Array=[]
 var road:Dictionary=plan.roads[4]
 views.append({"name":"north","anchor":road.start,"eye":road.start+Vector3.UP*1.7,"target":road.finish+Vector3.UP*1.7})
 if not connection.is_empty():
  var i:int=connection.points.size()/2
  views.append({"name":"road","anchor":connection.points[i],"eye":connection.points[i]+Vector3.UP*1.7,"target":connection.points[i+1]+Vector3.UP*1.7})
 if not market.is_empty():
  var street:Dictionary=market.roads[3]
  views.append({"name":"market","anchor":street.start,"eye":street.start+Vector3.UP*1.7,"target":street.finish+Vector3.UP*1.7})
 var completed:=0
 var trace:Array=[]
 for view:Dictionary in views:
  if cancelled():return false
  var label:String={"north":"Northern streets","road":"Woodland road","market":"Market square"}.get(view.name,view.name)
  var context:="View %d/%d · %s"%[completed+1,views.size(),label]
  var began:=Time.get_ticks_msec();var next_poll:=0;var deadline:=began+120000
  game.teleport(view.anchor)
  game.loading_stage_text="Preparing destination";game.loading_stage_percent=0
  while game.loading_active and Time.get_ticks_msec()<deadline and not cancelled():
   if Time.get_ticks_msec()>=next_poll:
    next_poll=Time.get_ticks_msec()+250
    var state:Dictionary=game.terrain.loading_state(game.player.position,game.fly)
    progress("Photographing the generated world",completed,views.size(),{"activity":context+" · "+game.loading_stage_text,"stage_fraction":(completed+0.65*game.loading_stage_percent/100.0)/views.size(),"work":game.loading_work_text,"terrain_readiness":state})
   await process_frame
  if game.loading_active:return false
  var loaded:=Time.get_ticks_msec()
  game.set_physics_process(false);game._clear_motion()
  game.camera.global_position=view.eye;game.camera.look_at(view.target)
  await process_frame
  deadline=Time.get_ticks_msec()+20000;next_poll=0
  while not photograph_ready(game) and Time.get_ticks_msec()<deadline and not cancelled():
   if Time.get_ticks_msec()>=next_poll:
    next_poll=Time.get_ticks_msec()+250
    var cover:Dictionary=photograph_cover_status(game)
    var fraction:float=float(cover.ready)/maxi(1,int(cover.total))
    progress("Photographing the generated world",completed,views.size(),{"activity":context+" · Loading grass and plants","stage_fraction":(completed+0.65+0.25*fraction)/views.size(),"work":"Nearby vegetation regions ready: %d / %d"%[cover.ready,cover.total]})
   await process_frame
  if not photograph_ready(game):print("PHOTOGRAPH_RESIDENCY_TIMEOUT ",view.name);return false
  var detailed:=Time.get_ticks_msec()
  progress("Photographing the generated world",completed,views.size(),{"activity":context+" · Capturing and saving image","stage_fraction":(completed+0.9)/views.size()})
  # Draw this state before readback/encoding; no extra rendering viewport.
  await process_frame
  if await capture_loading_view(game,view.name)!=OK:print("PHOTOGRAPH_SAVE_FAILED ",view.name);return false
  trace.append({"view":view.name,"loading_ms":loaded-began,"vegetation_ms":detailed-loaded,"capture_ms":Time.get_ticks_msec()-detailed})
  if generation_screen!=null:
   generation_screen.use_photograph(output_dir.path_join("loading_"+view.name+".png"))
   generation_screen.diagnostics.context["photographs"]=trace.duplicate(true)
  if completed==0 and "--capture-generation-ui" in PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args())):
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(output_dir.path_join("generation_loading.png"))
  completed+=1;progress("Photographing the generated world",completed,views.size())
 FileAccess.open(output_dir.path_join("photograph_timings.json"),FileAccess.WRITE).store_string(JSON.stringify(trace,"  "))
 return true

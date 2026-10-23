# SPDX-License-Identifier: 0BSD
extends SceneTree
var seed_value:=42
var output_dir:="res://reports"
var progress_path:=""
const Progress=preload("res://addons/world_runtime/generation_progress.gd")
func progress(stage:String,completed:int=0,total:int=0)->void:Progress.write(progress_path,stage,completed,total)
func _initialize()->void:run.call_deferred()
func ready_world(game:Node)->bool:
 return await wait_until(func():return not game.loading_active,120)
func capture_loading_view(game:Node,name:String)->void:
 await preload("res://addons/world_runtime/world_presentation.gd").capture(game,root,output_dir.path_join("loading_"+name+".png"))
func snapshot_signature(game:Node)->Dictionary:
 var water:PackedByteArray=game.lakes.capture_snapshot()
 var result:Dictionary={"water":preload("res://addons/world_runtime/survey_cache.gd").digest(water).hex_encode(),"blocks":block_signature(game),"region":Marshalls.raw_to_base64(game.generated_region.store.capture_snapshot())}
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
 while not condition.call() and Time.get_ticks_msec()<deadline:await process_frame
 return condition.call()
func run()->void:
 var generator:int=18 if "--coastal-inlet" in OS.get_cmdline_user_args() else 17
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--world-seed="):seed_value=int(arg.trim_prefix("--world-seed="))
  if arg.begins_with("--world-generator="):generator=int(arg.trim_prefix("--world-generator="))
  if arg.begins_with("--progress-file="):progress_path=arg.trim_prefix("--progress-file=")
  if arg.begins_with("--preparation-output="):output_dir=arg.trim_prefix("--preparation-output=")
 if generator not in [17,18,19] or seed_value<0 or seed_value>2147483647:quit(1);return
 DirAccess.make_dir_recursive_absolute(output_dir)
 progress("Planning terrain, streets and building sites")
 var prepared:Dictionary=preload("res://addons/world_runtime/world_generation_plan.gd").build(seed_value,generator,"--central-market" in OS.get_cmdline_user_args(),"--regional-connection" in OS.get_cmdline_user_args())
 if not prepared.get("ok",false):print("WORLD_PLAN_FAILED ",prepared);quit(1);return
 var plan:Dictionary=prepared.plan
 var works:Dictionary=prepared.works
 var market:Dictionary=prepared.market
 var connection:Dictionary=prepared.connection
 print("WORLD_PLAN digest=",prepared.plan_digest," cache_hit=",prepared.cache_hit," ms=",prepared.worker_ms)
 FileAccess.open(output_dir.path_join("generation_plan_identity.json"),FileAccess.WRITE).store_string(JSON.stringify({"version":prepared.version,"seed":seed_value,"generator":generator,"digest":prepared.plan_digest}))

 var game=load("res://demo/world.tscn").instantiate()
 var bake:bool="--save-terrain-lots" in OS.get_cmdline_user_args()
 var reopen:bool="--reopen-terrain-lots" in OS.get_cmdline_user_args()
 if bake:
  var slot:=""
  for arg:String in OS.get_cmdline_user_args():
   if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
  if slot.is_empty() or FileAccess.file_exists("user://worlds/"+slot+".trw"):
   print("REFUSING_EXISTING_OR_UNNAMED_BAKE");game.free();quit(1);return
 var offline_grading:=bake and not "--interactive-generation-grading" in OS.get_cmdline_user_args()
 if offline_grading:
  var packets:=preload("res://addons/world_runtime/generation_earthworks.gd").packets(works.segments)
  if not game.terrain.backend.configure_initial_earthworks(packets,prepared.plan_digest):print("OFFLINE_PACKETS_REJECTED");game.free();quit(1);return
  progress("Baking roads and foundations before terrain loading")
 game.lakes.offline_preparation=true;game.model_region_paging=false;game.temporary_world=not bake;game.max_fps=60;game.background_fps=60;root.add_child(game)
 progress("Loading terrain and collision")
 if not await ready_world(game) or game.terrain.backend.world_generator!=generator:print("WRONG_WORLD");quit(1);return
 progress("Baking generated lakes")
 if not await wait_until(func():return game.lakes.statistics().ready==game.lakes.statistics().lakes and not game.lakes.capture_snapshot().is_empty(),120):print("GENERATED_WATER_BAKE_FAILED ",game.lakes.statistics());game.free();quit(1);return
 game.set_physics_process(false);game._clear_motion();game.terrain.autosave_timer=-3600.0
 progress("Baking terrain overview")
 var map_worker:=Thread.new()
 if map_worker.start(preload("res://addons/world_runtime/survey_cache.gd").prepare.bind(seed_value,generator))!=OK:
  print("CARTOGRAPHY_WORKER_FAILED");game.free();quit(1);return
 while map_worker.is_alive():await process_frame
 var map_result:Dictionary=map_worker.wait_to_finish()
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
 progress("Grading roads and foundations",0,works.segments.size())
 if offline_grading:
  completed_edits=int(game.terrain.backend.initial_earthworks_result.get("completed",0))
  if completed_edits!=works.segments.size():print("OFFLINE_GRADING_INCOMPLETE");game.free();quit(1);return
  FileAccess.open(output_dir.path_join("earthworks_bake.json"),FileAccess.WRITE).store_string(JSON.stringify(game.terrain.backend.initial_earthworks_result))
 else:
  for offset in range(0,works.segments.size(),256):
   var batch:Dictionary={"ok":true,"segments":works.segments.slice(offset,mini(offset+256,works.segments.size())),"bounds":works.bounds}
   if not runner.begin(batch,game.terrain,func(_bounds:AABB)->String:return ""):quit(1);return
   var deadline:int=Time.get_ticks_msec()+90000
   while runner.status=="running" and Time.get_ticks_msec()<deadline:
    runner.tick(game.terrain,func(_bounds:AABB)->String:return "")
    if Time.get_ticks_msec()-last_progress_ms>=250:
     progress("Grading roads and foundations",completed_edits+runner.completed,works.segments.size());last_progress_ms=Time.get_ticks_msec()
    await process_frame
   if runner.status!="complete":print("PREPARATION_FAILED ",runner.status," ",runner.reason);quit(1);return
   completed_edits+=runner.completed
 game.structure_mode=true;game.structure_rotation=0
 var all_lots:Array=plan.lots.duplicate()
 if not market.is_empty():all_lots.append_array(market.lots)
 var completed_buildings:=0
 progress("Placing buildings and interiors",0,all_lots.size())
 for lot:Dictionary in all_lots:
  var index:int=game.structure_prefabs.find(lot.asset)
  if index<0:
   game._accept_composed_prefab({"ok":true,"asset":lot.asset});index=game.structure_prefab_index
  game.structure_prefab_index=index;game.structure_rotation=lot.rotation
  var doors:int=game.doors.collection.get_ids().size()
  game._begin_frontage_placement(lot.asset,lot.origin,true)
  if not await wait_until(func():return game._foundation_placement.is_empty(),20) or game.doors.collection.get_ids().size()!=doors+1:
   print("BUILDING_FAILED ",lot.label," ",game.foundation_check.status);quit(1);return
  completed_buildings+=1;progress("Placing buildings and interiors",completed_buildings,all_lots.size())
 progress("Baking streets and location metadata")
 var poses:Array=Planner.paving(plan)
 if not market.is_empty():poses.append_array(Planner.paving(market))
 var collection=game.structures.model(preload("res://addons/structures/paving_catalog.gd").KEY)
 for pose:Transform3D in poses:
  var records:PackedFloat32Array=preload("res://addons/structures/paving_catalog.gd").records([pose])
  if collection.insert_instance(records,AABB())<=0:print("PAVING_FAILED");quit(1);return
 var saved_paving:PackedByteArray=collection.capture_snapshot()
 if not collection.remove_instances(collection.get_ids()) or not collection.restore_snapshot(saved_paving) or collection.capture_snapshot()!=saved_paving:
  print("PAVING_ROUNDTRIP_FAILED");quit(1);return
 if not game.generated_region.publish_neighborhood(seed_value,plan,generator):print("REGION_PUBLICATION_FAILED");quit(1);return
 if not connection.is_empty():
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
 game.ecosystem._structures_changed()
 game.ground_cover._exclusion_changed(works.bounds)
 game.terrain.changed_since_save=true
 game.world_map.refresh_world()
 if game.world_map.places.size()!=((1 if connection.is_empty() else 2)+(1 if generator==18 else 0)) or game.world_map.roads.is_empty():print("BAKED_MAP_FAILED");quit(1);return
 game.construction_palette.survey_dialog.hide()
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
 var road:Dictionary=plan.roads[4]
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
  var file=FileAccess.open(output_dir.path_join("terrain_lot_region_expected.bin"),FileAccess.WRITE)
  file.store_buffer(game.generated_region.store.capture_snapshot());file.close()
  var manifest:=FileAccess.open(output_dir.path_join("world_signature.json"),FileAccess.WRITE)
  manifest.store_string(JSON.stringify({"seed":seed_value,"generator":generator,"signature":snapshot_signature(game)}));manifest.close()
  game.shutdown_requested=true
  if not await game.terrain.shutdown_after_edits():print("BAKE_SAVE_FAILED");game.free();quit(1);return
 print("TERRAIN_LOT_WORLD_REVIEW failures=0 buildings=",all_lots.size()," edits=",completed_edits)
 game.free();quit()

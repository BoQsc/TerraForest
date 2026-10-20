# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var report_path:String
var reopening:=false
var mixed:=false
var regional:=false
var districts:=false
var central_layout_seed:=0
var world_quality_sites:Array=[]
const WorldQuality=preload("res://addons/world_runtime/world_building_quality.gd")
func require(ok:bool,message:String)->bool:
 print("PASS " if ok else "FAIL ",message)
 return ok
func wait_until(predicate:Callable,seconds:int=30)->bool:
 var deadline:=Time.get_ticks_msec()+seconds*1000
 while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
 return predicate.call()
func signature()->Dictionary:
 var result:Dictionary={"blocks":regional_block_signature() if regional else Marshalls.raw_to_base64(game.structures.blocks.capture_snapshot()),"roads":Marshalls.raw_to_base64(game.road_palette.capture_anchors())}
 for asset: String in game.structures._models:
  var batch=game.structures.model(asset)
  result[asset]=Marshalls.raw_to_base64(batch.capture_snapshot())
 result["actors"]=Marshalls.raw_to_base64(game.actors.store.capture_storage_snapshot())
 result["actor_orders"]=Marshalls.raw_to_base64(game.actors.orders.capture_storage_snapshot())
 result["tree_groves"]=Marshalls.raw_to_base64(game.ecosystem._scatter().capture_storage_snapshot())
 result["ground_cover"]=Marshalls.raw_to_base64(game.ground_cover.removed.capture_storage_snapshot())
 result["vehicles"]=Marshalls.raw_to_base64(game.world_vehicle.capture_snapshot())
 result["chest_contents"]=Marshalls.raw_to_base64(game.storage.store.capture_storage_snapshot())
 return result
func _initialize()->void:run.call_deferred()
func run()->void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--checkpoint-report="):report_path=arg.trim_prefix("--checkpoint-report=")
  if arg=="--reopen-checkpoint":reopening=true
  if arg=="--checkpoint-layout=districts":districts=true
  if arg=="--checkpoint-layout=mixed":mixed=true
  if arg in ["--checkpoint-layout=regional","--checkpoint-layout=poi","--checkpoint-layout=lakes","--checkpoint-layout=districts"]:mixed=true;regional=true
 if report_path.is_empty():quit(1);return
 game=load("res://demo/world.tscn").instantiate();game.max_fps=60;game.background_fps=60;game.lakes.offline_preparation=true;game.model_region_paging=false;root.add_child(game)
 # Whole-world offline signatures require every model resident, unlike gameplay.
 # Offline staging is committed explicitly after the complete generation batch.
 # A periodic save between survey and grading can invalidate admission.
 game.terrain.autosave_timer=-3600.0
 game.set_physics_process(false) # Compare restored authoritative state before any patrol tick.
 # Cold offline generation includes all generated lake caches. This is not a
 # runtime arrival budget; the independent preparation runner records duration.
 var bake_timeout:int=360 if districts or "--checkpoint-layout=lakes" in OS.get_cmdline_user_args() else 180
 var started:bool=await wait_until(func():return not game.loading_active,bake_timeout)
 if not started:print("STARTUP_DIAGNOSTIC ",game.terrain.loading_state(game.player.position,game.fly)," lakes=",game.lakes.statistics()," catalog=",game.lakes.descriptions()," label=",game.loading_label.text)
 if not require(started,"normal generated world starts"):await finish(false);return
 game.set_physics_process(false);game._clear_motion();game.app_focused=true
 # Prepare the same derived map consumed by M before publishing a playable world.
 var map_worker:=Thread.new()
 var map_job:=preload("res://addons/world_runtime/survey_cache.gd").prepare.bind(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 if not require(map_worker.start(map_job)==OK,"cartography preparation worker starts"):await finish(false);return
 while map_worker.is_alive():await process_frame
 var map_result:Dictionary=map_worker.wait_to_finish()
 if not require(map_result.get("ok",false),"cartography persisted and reopened before gameplay"):await finish(false);return
 print("PREPARED_CARTOGRAPHY ",JSON.stringify(map_result))
 if reopening:
  game.world_map.set_open(true)
  var updates:Node=game.world_map.updates
  var ready_map:bool=await wait_until(func():return updates.image!=null and updates.identity_checked and updates.dirty.is_empty() and updates.pending.is_empty() and updates.cache_saved and updates.io==null,90)
  if not require(ready_map and (updates.cache_hits>0 or updates.cache_writes>0),"edited terrain cartography cached before publication"):await finish(false);return
  print("PREPARED_EDITED_CARTOGRAPHY hits=",updates.cache_hits," writes=",updates.cache_writes," patches=",updates.patches)
  game.world_map.set_open(false)


 if reopening:
  if not require(game.construction_inventory.gameplay and game.player_hud.gameplay_construction,"reopen uses resource-cost gameplay with actors and fleet enabled"):await finish(false);return
  if not require(game.actors.pool!=null and game.actors.store.statistics().active==2,"reopen has exactly two residents with simulation enabled"):await finish(false);return
  var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(report_path))
  var ready:bool=regional or await wait_until(func():return game.structures.blocks.stats().cells==int(expected.cells))
  if not require(game.terrain.backend.world_seed==int(expected.seed) and game.terrain.backend.world_generator==int(expected.generator),"seed and generator identity survive reopen"):await finish(false);return
  var actual:=signature()
  for key: String in actual:
   if actual[key]!=expected.signature.get(key):print("SIGNATURE_MISMATCH ",key)
  if not require(ready and actual==expected.signature,"fresh process restores exact settlement blocks, all furnishings, roads and patrol residents"):await finish(false);return
  if not require(game.player.position.distance_to(Vector3(expected.spawn[0],expected.spawn[1],expected.spawn[2]))<0.1,"on-foot start survives reopen"):await finish(false);return
 else:
  if not require(game.structures.blocks.stats().cells==0,"preparation starts in an empty staging world"):await finish(false);return
  if regional:
   var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
   if not require(not layout.is_empty(),"shared native regional layout available"):await finish(false);return
   var center:Vector3=layout.sites[0].position
   game.teleport(center-Vector3(36,0,36))
   if not require(await wait_until(func():return not game.loading_active,60),"regional centre loads for settlement generation"):await finish(false);return
   game.set_physics_process(false);game._clear_motion()
  game.structure_mode=true;game.structure_rotation=0
  var sources:=PackedInt32Array()
  for i in game.structure_prefabs.size():
   var title: String=game.structure_prefabs[i].resource_name
   if title=="Furnished cottage with door and windows" or (mixed and title.begins_with("Furnished tower")):sources.append(i)
  if not require(sources.size()==(2 if mixed else 1),"registered furnished building sources are available"):await finish(false);return
  game.prefab_library.directory="user://checkpoint_prefabs/"+game.terrain.save_slot
  central_layout_seed=game.terrain.backend.world_seed
  if mixed:
   var assets:Array[Resource]=[]
   for index:int in sources:assets.append(game.structure_prefabs[index])
   var choice:Dictionary=preload("res://addons/structures/regional_districts.gd").mixed_layout_seed(assets,central_layout_seed)
   if not require(choice.get("ok",false),"mixed central recipe contains both building types"):await finish(false);return
   central_layout_seed=choice.seed
   print("CENTRAL_LAYOUT world_seed=",game.terrain.backend.world_seed," layout_seed=",central_layout_seed)
  var count:int=game.structure_prefabs.size()
  game._frontage_sources_construction(sources,2 if mixed else 1,8,3,central_layout_seed,"Mixed neighborhood" if mixed else "Gameplay settlement",2)
  if not require(await wait_until(func():return game.structure_prefabs.size()==count+1,10),"existing native editor composes connected furnished streets"):await finish(false);return
  game.camera.global_position=game.player.global_position+Vector3(0,15,0)
  game.camera.look_at(game.player.global_position+Vector3(10,-5,0))
  await physics_frame
  if regional:
   var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
   var asset:Resource=game.structure_prefabs[game.structure_prefab_index]
   var bounds:AABB=asset.placement_bounds(Vector3i.ZERO,0)
   var center:Vector3=layout.sites[0].position
   var origin:Vector3i=preload("res://addons/structures/site_plan.gd").regional_origin(asset,center)
   var survey:Dictionary=await game.site_survey.assess(game.terrain,asset,origin,0)
   world_quality_sites.append(WorldQuality.site(survey,"Central settlement"))
   print("REGIONAL_SITE_SURVEY ",survey," footprint=",asset.placement_bounds(origin,0))
   if not require(survey.ok,"regional district beside arterial has supported foundation"):await finish(false);return
   var plan:Dictionary=preload("res://addons/structures/site_plan.gd").prepare(asset,origin,0,survey.grade)
   if not require(plan.ok,"regional district foundation plan valid"):await finish(false);return
   if not connect_regional_street(plan,center):await finish(false);return
   game._survey_generation+=1
   plan["epoch"]=game.terrain.epoch;plan["revision"]=game.terrain.density_revision;plan["generation"]=game._survey_generation;plan["asset"]=asset
   game._survey_plan=plan
  else:game._survey_construction()
  if not require(await wait_until(func():return not game.construction_palette.survey_busy,20) and not game._survey_plan.is_empty(),"terrain survey finds supported settlement grade"):await finish(false);return
  game.player.global_position-=Vector3(100,0,0)
  game._prepare_construction_site()
  if not require(await wait_until(func():return game.site_preparation.status!="running",30) and game.site_preparation.status=="complete","native grading and asphalt preparation complete"):await finish(false);return
  game._place_prepared_site()
  if not require(await wait_until(func():return game._foundation_placement.is_empty(),20) and game.structures.blocks.stats().cells>0,"staged furnished settlement publishes"):await finish(false);return
  if mixed:
   var door_count: int=game.doors.collection.get_ids().size()
   var rails: int=game.structures.model("architecture/metal_guardrail/v1").get_ids().size()
   if not require(door_count==8 and rails>0 and rails<door_count*5,"mixed generation contains eight furnished buildings including cottages and towers"):await finish(false);return
  var target:Vector3=Vector3(game.site_preparation.plan.target)
  game.needs_floor_spawn=false;game.fly=false
  game.player.position=Vector3(target.x+4.5,target.y+2.1,game.road_palette.prepared_streets[0].ends[0].z-11.0)
  if mixed:
   var p: PackedFloat32Array=game.doors.collection.get_instance(game.doors.collection.get_ids()[0])
   var pose:=Transform3D(Basis(Vector3(p[0],p[4],p[8]),Vector3(p[1],p[5],p[9]),Vector3(p[2],p[6],p[10])).orthonormalized(),Vector3(p[3],p[7],p[11]))
   game.player.position=pose*Vector3(0.5,0.1,-2.5)
  game.yaw=0;game.pitch=-0.15;game.player.rotation.y=0
  game.camera.position=Vector3(0,1.6,0);game.camera.rotation=Vector3(game.pitch,0,0)
  game.terrain.focus=game.player.position;game.structures.set_model_focus(game.player.position)
  game.construction_palette.survey_dialog.hide()
  var spawn: Vector3=game.player.position
  var street: Dictionary=game.road_palette.prepared_streets[0]
  var center: Vector3=(street.ends[0]+street.ends[1])*.5
  var direction: Vector3=(street.ends[1]-street.ends[0]).normalized()
  game.player.position=center+Vector3(-direction.z,0,direction.x)*3+Vector3.UP*1.5
  game.terrain.focus=game.player.position;game.structures.set_model_focus(game.player.position)
  if not require(await wait_until(func():return game._actor_collision_ready(AABB(center-Vector3(6,1,6),Vector3(12,4,12))),30),"resident street collision ready"):await finish(false);return
  var population: Dictionary=preload("res://addons/world_runtime/settlement_actors.gd").populate(game)
  if not require(population.ok and game.actors.store.statistics().active==2,"two native patrol residents prepared: "+population.reason):await finish(false);return
  game.player.position=spawn;game.terrain.focus=spawn;game.structures.set_model_focus(spawn)

  if regional:
   if not await prepare_outer_sites():await finish(false);return
   if game.terrain.backend.world_generator>=10 and not await prepare_cellar_location():await finish(false);return
   if not await prepare_underground_locations():await finish(false);return
   if districts and not await prepare_woodland_locations():await finish(false);return
   if districts and not await prepare_transport():await finish(false);return
   if districts:
    var supplies:Dictionary=preload("res://addons/world_runtime/settlement_supplies.gd").populate(game)
    if not require(supplies.ok,"generated chest supplies: "+str(supplies)):await finish(false);return
   game.teleport(spawn)
   if not require(await wait_until(func():return not game.loading_active,60),"central spawn reloads after outer town generation"):await finish(false);return
   game.set_physics_process(false);game._clear_motion();game.player.position=spawn
   game.fly=false;game.needs_floor_spawn=false
   game.yaw=0;game.pitch=-0.15;game.player.rotation.y=0
   game.camera.position=Vector3(0,1.6,0);game.camera.rotation=Vector3(game.pitch,0,0)

  var quality:Dictionary=WorldQuality.summary(world_quality_sites)
  print("WORLD_QUALITY_REVIEW ",JSON.stringify(quality))
  var file:=FileAccess.open(report_path,FileAccess.WRITE)
  file.store_string(JSON.stringify({"slot":game.terrain.save_slot,"seed":game.terrain.backend.world_seed,"central_layout_seed":central_layout_seed,"world_quality":quality,"generator":game.terrain.backend.world_generator,"cells":game.structures.blocks.stats().cells,"spawn":[game.player.position.x,game.player.position.y,game.player.position.z],"signature":signature()},"  "));file.close()
 # Wait for existing generated components before ordinary compound persistence.
 if not require(await wait_until(func():return not game.lakes.capture_snapshot().is_empty(),60),"generated components ready for compound save"):await finish(false);return
 for frame in 10:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(report_path+(".reopened.png" if reopening else ".created.png"))
 await finish(true)
func finish(ok:bool)->void:
 game.shutdown_requested=true
 if ok:ok=await game.terrain.shutdown_after_edits()
 else:game.terrain.shutdown()
 game.free();await process_frame
 print("COMBINED_PREPARATION failures=",0 if ok else 1)
 quit(0 if ok else 1)

# Offline composition only. Native terrain edits and prefab transactions own work.
func connect_regional_street(plan:Dictionary,center:Vector3)->bool:
 return require(preload("res://addons/structures/site_plan.gd").connect_regional_street(plan,center),"regional road foundations fit protected authoring bounds")

func prepare_transport()->bool:
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 if not require(game.world_vehicle.fleet_enabled and game.world_vehicle.fleet.statistics().records==0,"transport starts with an empty prepared fleet"):return false
 for site in [0,2]:
  var center:Vector3=layout.sites[site].position
  var bay:Vector3=center+Vector3(12,0,16)
  var mine_parking:Dictionary=preload("res://addons/structures/mine_catalog.gd").parking(center) if site==2 else {}
  game.teleport(center+Vector3(5,0,5))
  if not require(await wait_until(func():return not game.loading_active,60),"parking location loads"):return false
  game.set_physics_process(false);game._clear_motion()
  var start:=center+Vector3(0,0,16);var finish:=center+Vector3(17,0,16)
  if site==2:start=mine_parking.start;finish=mine_parking.finish;bay=mine_parking.pose.origin-Vector3.UP*0.85
  var bounds:=AABB(start-Vector3(4,5,4),finish-start+Vector3(8,12,8))
  if not require(game._road_protection_error(bounds).is_empty(),"parking apron is clear of protected structures"):return false
  if not require(game.terrain.construct_graded_bed(start,finish,4.0,4.0,7.0,4,0.0),"parking apron edit accepted"):return false
  if not require(await wait_until(func():return not game.terrain.pending_edit,30) and game.terrain.last_edit_outcome.get("status","") in ["published","unchanged"],"parking apron published"):return false
  var pose:=Transform3D(Basis(Vector3.UP,-PI/2),bay+Vector3.UP*0.85)
  if not require(await wait_until(func():return game.world_vehicle.ready_bounds(game,AABB(pose.origin-Vector3(3.25,1,3.25),Vector3(6.5,3,6.5))),20),"parking collision ready"):return false
  var box:=BoxShape3D.new();box.size=Vector3(2.2,1.8,4.4)
  var query:=PhysicsShapeQueryParameters3D.new();query.shape=box;query.transform=Transform3D(pose.basis,pose.origin+Vector3.UP*0.3);query.collision_mask=15
  if not require(game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"parked chassis space is unobstructed"):return false
  if not require(game.world_vehicle.fleet.spawn(pose)>0,"parked vehicle stored at site %d"%site):return false
 var north:Vector3=layout.sites[3].position
 var bay:Dictionary=preload("res://addons/structures/northern_lots.gd").parking(north)
 if not require(bay.ok,"northern bay recipe fits world"):return false
 game.teleport(north+Vector3(4,0,60))
 if not require(await wait_until(func():return not game.loading_active,60),"northern bay loads"):return false
 game.set_physics_process(false);game._clear_motion()
 var survey:Dictionary=await game.site_survey.assess(game.terrain,bay.probe,Vector3i(north),0)
 survey.grade=north.y
 var quality:Dictionary=WorldQuality.site(survey,"Northern parking bay")
 if not require(quality.status=="pass","northern bay earthworks fit: "+str(quality)+" survey="+str(survey)):return false
 world_quality_sites.append(quality)
 if not require(game._road_protection_error(bay.bounds).is_empty(),"northern bay clears homes, paths and protected objects"):return false
 if not require(game.terrain.construct_graded_bed(bay.start,bay.finish,4,1,4,4,0),"northern bay asphalt admitted"):return false
 if not require(await wait_until(func():return not game.terrain.pending_edit,30) and game.terrain.last_edit_outcome.get("status","") in ["published","unchanged"],"northern bay asphalt publishes"):return false
 game.road_palette.register_prepared_street(bay,game.terrain.epoch)
 if not require(await wait_until(func():return game.world_vehicle.ready_bounds(game,AABB(bay.pose.origin-Vector3(3.25,1,3.25),Vector3(6.5,3,6.5))),20),"northern bay collision ready"):return false
 var shape:=BoxShape3D.new();shape.size=Vector3(2.2,1.8,4.4)
 var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=Transform3D(bay.pose.basis,bay.pose.origin+Vector3.UP*0.3);query.collision_mask=15
 if not require(game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"northern parked chassis is unobstructed"):return false
 if not require(game.world_vehicle.fleet.spawn(bay.pose)>0,"northern off-road vehicle stored"):return false
 return game.world_vehicle.fleet.statistics().records==3

func prepare_woodland_locations()->bool:
 var author=preload("res://addons/world_ecosystem/woodland_authoring.gd")
 var index:=0
 for center:Vector3 in author.centers(game.terrain.backend.world_seed,game.terrain.backend.world_generator):
  game.teleport(center)
  if not require(await wait_until(func():return not game.loading_active,60),"woodland location loads"):return false
  game.set_physics_process(false);game._clear_motion()
  var result:Dictionary=await author.plant(game,center,game.terrain.backend.world_seed+index,16 if index>=2 else 32)
  if not require(result.ok,"woodland authored planting completes: "+str(result)):return false
  print("REGIONAL_WOODLAND center=",center," result=",result)
  index+=1
 return index==4

func prepare_outer_sites()->bool:
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 var cottage:=-1
 for i in game.structure_prefabs.size():
  if game.structure_prefabs[i].resource_name=="Furnished cottage with door and windows":cottage=i;break
 if not require(cottage>=0,"outer town furnished source available"):return false
 for site:Dictionary in layout.sites.slice(1):
  var center:Vector3=site.position
  game.construction_palette.survey_dialog.hide()
  game.teleport(center+Vector3(30,0,30))
  if not require(await wait_until(func():return not game.loading_active,60),"outer site %d loads" % site.id):return false
  game.set_physics_process(false);game._clear_motion();game.structure_mode=true;game.structure_rotation=0
  if districts and site.id==3:
   if not await prepare_northern_lots(center):return false
   continue
  var count:int=game.structure_prefabs.size()
  var selection:=PackedInt32Array([cottage])
  var district:Dictionary={"title":"Regional village %d"%site.id,"lots":1,"width":8,"gap":3,"streets":1,"buildings":2}
  if districts:
   district=preload("res://addons/structures/regional_districts.gd").plan(site.id);selection=PackedInt32Array()
   for title:String in district.sources:
    for i in game.structure_prefabs.size():
     if game.structure_prefabs[i].resource_name==title:selection.append(i);break
   if not require(selection.size()==district.sources.size(),"district sources available: "+district.title):return false
  var layout_seed:int=game.terrain.backend.world_seed+int(site.id)
  if districts and selection.size()==2:
   var sources:Array[Resource]=[]
   for index:int in selection:sources.append(game.structure_prefabs[index])
   var mixed:Dictionary=preload("res://addons/structures/regional_districts.gd").mixed_layout_seed(sources,layout_seed,district.lots,district.streets)
   if not require(mixed.get("ok",false),"regional mixed building choices available"):return false
   layout_seed=mixed.seed
  game._frontage_sources_construction(selection,district.lots,district.width,district.gap,layout_seed,district.title,district.streets)
  if not require(await wait_until(func():return game.structure_prefabs.size()==count+1,10),"outer furnished street composed"):return false
  var asset:Resource=game.structure_prefabs[game.structure_prefab_index]
  if districts:asset.set_meta("entrance_paths",true)
  var origin:Vector3i=preload("res://addons/structures/site_plan.gd").regional_origin(asset,center)
  var survey:Dictionary=await game.site_survey.assess(game.terrain,asset,origin,0)
  world_quality_sites.append(WorldQuality.site(survey,district.title))
  if not require(survey.ok,"outer site supported: "+str(survey)):return false
  var plan:Dictionary=preload("res://addons/structures/site_plan.gd").prepare(asset,origin,0,survey.grade)
  if not require(plan.ok,"outer site plan valid"):return false
  if not connect_regional_street(plan,center):return false
  game._survey_generation+=1
  plan["epoch"]=game.terrain.epoch;plan["revision"]=game.terrain.density_revision;plan["generation"]=game._survey_generation;plan["asset"]=asset
  game._survey_plan=plan
  game._prepare_construction_site()
  if not require(await wait_until(func():return game.site_preparation.status!="running",30) and game.site_preparation.status=="complete","outer foundation and arterial connection prepared"):return false
  var doors:int=game.doors.collection.get_ids().size()
  game._place_prepared_site()
  if not require(await wait_until(func():return game._foundation_placement.is_empty(),20) and game.doors.collection.get_ids().size()==doors+district.buildings,"district furnished buildings published: "+district.title):return false
  print("REGIONAL_TOWN site=",site.id," doors=",game.doors.collection.get_ids().size()," cells=",game.structures.blocks.stats().cells)
 var expected:=8
 for site_id in range(1,5):expected+=preload("res://addons/structures/regional_districts.gd").plan(site_id).buildings if districts else 2
 return require(game.doors.collection.get_ids().size()==expected,"five regional sites contain expected furnished buildings")

func regional_block_signature()->Dictionary:
 # Check persistent content independently of the camera's resident window.
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

func prepare_underground_locations()->bool:
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 for poi:Dictionary in layout.get("underground",[]):
  var entrance:Vector3=poi.entrance
  game.teleport(entrance+Vector3(30,0,20))
  if not require(await wait_until(func():return not game.loading_active,60),"mine location streams before placement"):return false
  game.set_physics_process(false);game._clear_motion();game.structure_rotation=0
  var access:Dictionary=preload("res://addons/structures/mine_catalog.gd").access_plan(entrance,layout.sites[int(poi.owner_site)].position)
  if not require(access.ok,"mine access plan fits world bounds"):return false
  for segment:Dictionary in access.segments:
   if not require(game._road_protection_error(segment.bounds).is_empty(),"mine access does not overwrite protected placement"):return false
   var accepted:bool=game.terrain.construct_graded_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,segment.material,segment.shoulder)
   if not require(accepted,"mine access terrain edit accepted"):return false
   if not require(await wait_until(func():return not game.terrain.pending_edit,30) and game.terrain.last_edit_outcome.get("status","") in ["published","unchanged"],"mine access asphalt publishes"):return false
  game.road_palette.register_prepared_street(access,game.terrain.epoch)
  var asset:Resource=preload("res://addons/structures/mine_catalog.gd").entrance()
  if not require(asset!=null,"mine entrance prefab builds"):return false
  var origin:=Vector3i(entrance)
  var before:int=game.structures.blocks.stats().cells
  if not require(game._place_combined_prefab(asset,origin,0),"mine entrance and storage publish through native combined transaction"):return false
  if not require(game.structures.blocks.stats().cells>before,"mine timber frames exist in world"):return false
  print("REGIONAL_MINE owner=",poi.owner_site," entrance=",entrance," cells=",game.structures.blocks.stats().cells)
 return true

func prepare_cellar_location()->bool:
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 var center:Vector3=layout.sites[1].position+Vector3(20,0,20)
 game.teleport(center+Vector3(15,0,15))
 if not require(await wait_until(func():return not game.loading_active,60),"cellar location loads"):return false
 game.set_physics_process(false);game._clear_motion();game.structure_rotation=0
 var asset:Resource=preload("res://addons/structures/cellar_catalog.gd").cottage()
 game._accept_composed_prefab({"ok":true,"asset":asset})
 var plan:Dictionary=preload("res://addons/structures/site_plan.gd").prepare(asset,Vector3i(center),0,int(center.y))
 plan=preload("res://addons/structures/cellar_catalog.gd").connect_access(plan,layout.sites[1].position)
 if not require(plan.ok,"cellar building site plan valid"):return false
 game._survey_generation+=1
 plan["epoch"]=game.terrain.epoch;plan["revision"]=game.terrain.density_revision;plan["generation"]=game._survey_generation;plan["asset"]=asset
 game._survey_plan=plan;game._prepare_construction_site()
 if not require(await wait_until(func():return game.site_preparation.status!="running",30) and game.site_preparation.status=="complete","cellar surface and underground preparation publishes"):return false
 var before:int=game.doors.collection.get_ids().size()
 game._place_prepared_site()
 if not require(await wait_until(func():return game._foundation_placement.is_empty(),20) and game.doors.collection.get_ids().size()==before+1,"cellar cottage and attachments publish"):return false
 print("REGIONAL_CELLAR origin=",plan.target," cells=",game.structures.blocks.stats().cells)
 return true

func prepare_northern_lots(center:Vector3)->bool:
 var builder=preload("res://addons/structures/northern_lots.gd")
 var lots:Array=builder.recipe(center);var surveys:Array=[]
 for lot:Dictionary in lots:
  var survey:Dictionary=await game.site_survey.assess(game.terrain,lot.asset,lot.origin,lot.rotation)
  if not require(survey.ok,"lot surveyed before any grading: "+lot.label):return false
  surveys.append(survey)
 var common:Dictionary=preload("res://addons/structures/neighborhood_common.gd").build(center)
 if not require(common.ok,"northern common recipe builds before grading"):return false
 var common_survey:Dictionary=await game.site_survey.assess(game.terrain,common.asset,common.origin,0)
 common_survey.grade=center.y
 var common_quality:Dictionary=WorldQuality.site(common_survey,"Northern common paths and furniture")
 if not require(common_quality.status=="pass","common pre-edit earthworks fit: "+str(common_quality)+" survey="+str(common_survey)):return false
 world_quality_sites.append(common_quality)
 var plan:Dictionary=builder.assemble(lots,center,surveys)
 if not require(plan.ok,"independent northern lot plan: "+str(plan.get("reason","accepted"))):return false
 plan.common["survey"]=common_survey
 var road_probe:Resource=builder.street_probe(center)
 if not require(road_probe!=null,"northern road survey geometry"):return false
 var road_survey:Dictionary=await game.site_survey.assess(game.terrain,road_probe,Vector3i(center),0)
 road_survey.grade=center.y
 var road_quality:Dictionary=WorldQuality.site(road_survey,"Northern street corridors")
 if not require(road_quality.status=="pass","street earthworks fit: "+str(road_quality)+" survey="+str(road_survey)):return false
 world_quality_sites.append_array(plan.qualities);world_quality_sites.append(road_quality)
 print("NORTHERN_LOT_QUALITY ",JSON.stringify(plan.qualities))
 game.teleport(center+Vector3(100,0,0))
 if not require(await wait_until(func():return not game.loading_active,45),"move outside northern preparation bounds"):return false
 game.set_physics_process(false);game._clear_motion();game.structure_mode=true;game.structure_rotation=0
 game._accept_composed_prefab({"ok":true,"asset":plan.asset})
 game._survey_generation+=1
 plan["epoch"]=game.terrain.epoch;plan["revision"]=game.terrain.density_revision;plan["generation"]=game._survey_generation
 game._survey_plan=plan;game._prepare_construction_site()
 if not require(await wait_until(func():return game.site_preparation.status!="running",45) and game.site_preparation.status=="complete","independent lots and streets prepared"):return false
 for lot:Dictionary in plan.lots:
  var index:int=game.structure_prefabs.find(lot.asset)
  if index<0:
   game._accept_composed_prefab({"ok":true,"asset":lot.asset});index=game.structure_prefab_index
  game.structure_prefab_index=index;game.structure_rotation=lot.rotation
  var doors:int=game.doors.collection.get_ids().size()
  # Support/clearance bands belong to each lot's base, not one global height.
  game._begin_frontage_placement(lot.asset,lot.origin,true)
  if not require(await wait_until(func():return game._foundation_placement.is_empty(),20) and game.doors.collection.get_ids().size()==doors+1,"terrain-fitted building published: "+lot.label+" support="+game.foundation_check.status):return false
 if not require(game._place_combined_prefab(plan.sidewalk_asset,plan.sidewalk_origin,0),"native concrete walkways published"):return false
 if not prepare_northern_common(plan.common):return false
 var groves:=PackedVector3Array()
 for x in [-60,60]:
  for z in [-26,26]:groves.append(Vector3(center.x+x,16,center.z+z))
 if not require(game.ecosystem.configure_groves(groves),"persistent native neighborhood groves configured"):return false
 return true

func prepare_northern_common(common:Dictionary)->bool:
 # Terrain beds belong to the master plan and run before any structure publication.
 if not require(game._place_combined_prefab(common.asset,common.origin,0),"common paving, shared furniture and public chest publish together: "+game.construction_inventory.reason):return false
 print("NORTHERN_COMMON origin=",common.origin," blocks=",common.asset.get_records().size()/4," props=",common.asset.get_model_attachments().size()," survey=",common.survey)
 return true

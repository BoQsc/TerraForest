# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var report_path:String
var reopening:=false
var mixed:=false
var regional:=false
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
 return result
func _initialize()->void:run.call_deferred()
func run()->void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--checkpoint-report="):report_path=arg.trim_prefix("--checkpoint-report=")
  if arg=="--reopen-checkpoint":reopening=true
  if arg=="--checkpoint-layout=mixed":mixed=true
  if arg in ["--checkpoint-layout=regional","--checkpoint-layout=poi"]:mixed=true;regional=true
 if report_path.is_empty():quit(1);return
 game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 # Offline staging is committed explicitly after the complete generation batch.
 # A periodic save between survey and grading can invalidate admission.
 game.terrain.autosave_timer=-3600.0
 game.set_physics_process(false) # Compare restored authoritative state before any patrol tick.
 # Cold offline generation includes all generated lake caches. This is not a
 # runtime arrival budget; the independent preparation runner records duration.
 var started:bool=await wait_until(func():return not game.loading_active,180)
 if not started:print("STARTUP_DIAGNOSTIC ",game.terrain.loading_state(game.player.position,game.fly)," lakes=",game.lakes.statistics()," catalog=",game.lakes.descriptions()," label=",game.loading_label.text)
 if not require(started,"normal generated world starts"):await finish(false);return
 game.set_physics_process(false);game._clear_motion();game.app_focused=true
 if reopening:
  if not require(game.construction_inventory.gameplay and game.player_hud.gameplay_construction,"reopen uses resource-cost gameplay with actors and fleet enabled"):await finish(false);return
  if not require(game.actors.pool!=null and game.actors.store.statistics().active==2,"reopen has exactly two residents with simulation enabled"):await finish(false);return
  var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(report_path))
  var ready:bool=regional or await wait_until(func():return game.structures.blocks.stats().cells==int(expected.cells))
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
  var count:int=game.structure_prefabs.size()
  game._frontage_sources_construction(sources,2 if mixed else 1,8,3,1703,"Mixed neighborhood" if mixed else "Gameplay settlement",2)
  if not require(await wait_until(func():return game.structure_prefabs.size()==count+1,10),"existing native editor composes connected furnished streets"):await finish(false);return
  game.camera.global_position=game.player.global_position+Vector3(0,15,0)
  game.camera.look_at(game.player.global_position+Vector3(10,-5,0))
  await physics_frame
  if regional:
   var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
   var asset:Resource=game.structure_prefabs[game.structure_prefab_index]
   var bounds:AABB=asset.placement_bounds(Vector3i.ZERO,0)
   var center:Vector3=layout.sites[0].position
   var origin:=Vector3i(floori(center.x-12-bounds.end.x),int(center.y),floori(center.z-12-bounds.end.z))
   var survey:Dictionary=await game.site_survey.assess(game.terrain,asset,origin,0)
   print("REGIONAL_SITE_SURVEY ",survey," footprint=",asset.placement_bounds(origin,0))
   if not require(survey.ok,"regional district beside arterial has supported foundation"):await finish(false);return
   var plan:Dictionary=preload("res://addons/structures/site_plan.gd").prepare(asset,origin,0,survey.grade)
   if not require(plan.ok,"regional district foundation plan valid"):await finish(false);return
   connect_regional_street(plan,center)
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
   game.teleport(spawn)
   if not require(await wait_until(func():return not game.loading_active,60),"central spawn reloads after outer town generation"):await finish(false);return
   game.set_physics_process(false);game._clear_motion();game.player.position=spawn
   game.fly=false;game.needs_floor_spawn=false
   game.yaw=0;game.pitch=-0.15;game.player.rotation.y=0
   game.camera.position=Vector3(0,1.6,0);game.camera.rotation=Vector3(game.pitch,0,0)

  var file:=FileAccess.open(report_path,FileAccess.WRITE)
  file.store_string(JSON.stringify({"slot":game.terrain.save_slot,"cells":game.structures.blocks.stats().cells,"spawn":[game.player.position.x,game.player.position.y,game.player.position.z],"signature":signature()},"  "));file.close()
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
func connect_regional_street(plan:Dictionary,center:Vector3)->void:
 var lines:PackedVector3Array=plan.street_lines
 var start:=lines[0]
 for point:Vector3 in lines:
  if point.x>start.x:start=point
 var corner:=Vector3(center.x,start.y,start.z)
 var finish:=Vector3(center.x,start.y,center.z)
 for pair in [[start,corner],[corner,finish]]:
  var a:Vector3=pair[0];var b:Vector3=pair[1]
  if a.distance_to(b)<1:continue
  var region:=AABB(a.min(b)-Vector3(4,8,4),a.max(b)-a.min(b)+Vector3(8,20,8))
  plan.segments.append({"start":a,"finish":b,"half_width":4.0,"depth":8.0,"clearance":12.0,"shoulder":0.0,"material":4,"bounds":region})
  plan.bounds=plan.bounds.merge(region);plan.paving_segments+=1
  plan.street_lines.append(a);plan.street_lines.append(b)

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
  var count:int=game.structure_prefabs.size()
  game._frontage_sources_construction(PackedInt32Array([cottage]),1,8,3,1703+int(site.id),"Regional village %d" % site.id,1)
  if not require(await wait_until(func():return game.structure_prefabs.size()==count+1,10),"outer furnished street composed"):return false
  var asset:Resource=game.structure_prefabs[game.structure_prefab_index]
  var bounds:AABB=asset.placement_bounds(Vector3i.ZERO,0)
  var origin:=Vector3i(floori(center.x-12-bounds.end.x),int(center.y),floori(center.z-12-bounds.end.z))
  var survey:Dictionary=await game.site_survey.assess(game.terrain,asset,origin,0)
  if not require(survey.ok,"outer site supported: "+str(survey)):return false
  var plan:Dictionary=preload("res://addons/structures/site_plan.gd").prepare(asset,origin,0,survey.grade)
  if not require(plan.ok,"outer site plan valid"):return false
  connect_regional_street(plan,center)
  game._survey_generation+=1
  plan["epoch"]=game.terrain.epoch;plan["revision"]=game.terrain.density_revision;plan["generation"]=game._survey_generation;plan["asset"]=asset
  game._survey_plan=plan
  game._prepare_construction_site()
  if not require(await wait_until(func():return game.site_preparation.status!="running",30) and game.site_preparation.status=="complete","outer foundation and arterial connection prepared"):return false
  var doors:int=game.doors.collection.get_ids().size()
  game._place_prepared_site()
  if not require(await wait_until(func():return game._foundation_placement.is_empty(),20) and game.doors.collection.get_ids().size()==doors+2,"outer two furnished buildings published"):return false
  print("REGIONAL_TOWN site=",site.id," doors=",game.doors.collection.get_ids().size()," cells=",game.structures.blocks.stats().cells)
 return require(game.doors.collection.get_ids().size()==16,"five regional sites contain sixteen furnished buildings")

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

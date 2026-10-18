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
 var result:Dictionary={"blocks":Marshalls.raw_to_base64(game.structures.blocks.capture_snapshot()),"roads":Marshalls.raw_to_base64(game.road_palette.capture_anchors())}
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
  if arg=="--checkpoint-layout=regional":mixed=true;regional=true
 if report_path.is_empty():quit(1);return
 game=load("res://demo/world.tscn").instantiate();root.add_child(game)
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
  var ready:bool=await wait_until(func():return game.structures.blocks.stats().cells==int(expected.cells))
  var actual:=signature()
  for key: String in actual:
   if actual[key]!=expected.signature.get(key):print("SIGNATURE_MISMATCH ",key)
  if not require(ready and actual==expected.signature,"fresh process restores exact settlement blocks, all furnishings, roads and patrol residents"):await finish(false);return
  if not require(game.player.position.distance_to(Vector3(expected.spawn[0],expected.spawn[1],expected.spawn[2]))<0.1,"on-foot start survives reopen"):await finish(false);return
 else:
  if not require(game.structures.blocks.stats().cells==0,"preparation starts in an empty staging world"):await finish(false);return
  if regional:
   var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed)
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
   var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed)
   var asset:Resource=game.structure_prefabs[game.structure_prefab_index]
   var bounds:AABB=asset.placement_bounds(Vector3i.ZERO,0)
   var center:Vector3=layout.sites[0].position
   var origin:=Vector3i(floori(center.x-12-bounds.end.x),int(center.y),floori(center.z-12-bounds.end.z))
   var survey:Dictionary=await game.site_survey.assess(game.terrain,asset,origin,0)
   print("REGIONAL_SITE_SURVEY ",survey," footprint=",asset.placement_bounds(origin,0))
   if not require(survey.ok,"regional district beside arterial has supported foundation"):await finish(false);return
   var plan:Dictionary=preload("res://addons/structures/site_plan.gd").prepare(asset,origin,0,survey.grade)
   if not require(plan.ok,"regional district foundation plan valid"):await finish(false);return
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

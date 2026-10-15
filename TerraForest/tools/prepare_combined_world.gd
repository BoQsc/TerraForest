# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var report_path:String
var reopening:=false
func require(ok:bool,message:String)->bool:
 print("PASS " if ok else "FAIL ",message)
 return ok
func wait_until(predicate:Callable,seconds:int=30)->bool:
 var deadline:=Time.get_ticks_msec()+seconds*1000
 while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
 return predicate.call()
func signature()->Dictionary:
 var result:Dictionary={"blocks":Marshalls.raw_to_base64(game.structures.blocks.capture_snapshot()),"roads":Marshalls.raw_to_base64(game.road_palette.capture_anchors())}
 for asset in ["furniture/table/v1","furniture/chair/v1","furniture/shelf/v1","storage/wooden_chest/v1"]:
  var batch=game.structures.model(asset)
  result[asset]=Marshalls.raw_to_base64(batch.capture_snapshot())
 return result
func _initialize()->void:run.call_deferred()
func run()->void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--checkpoint-report="):report_path=arg.trim_prefix("--checkpoint-report=")
  if arg=="--reopen-checkpoint":reopening=true
 if report_path.is_empty():quit(1);return
 game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 var started:bool=await wait_until(func():return not game.loading_active,60)
 if not started:print("STARTUP_DIAGNOSTIC ",game.terrain.loading_state(game.player.position,game.fly)," lakes=",game.lakes.statistics()," catalog=",game.lakes.descriptions()," label=",game.loading_label.text)
 if not require(started,"normal generated world starts"):await finish(false);return
 game.set_physics_process(false);game._clear_motion();game.app_focused=true
 if reopening:
  if not require(game.construction_inventory.gameplay and game.player_hud.gameplay_construction,"reopen uses resource-cost gameplay with actors and fleet enabled"):await finish(false);return
  var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(report_path))
  var ready:bool=await wait_until(func():return game.structures.blocks.stats().cells==int(expected.cells))
  if not require(ready and signature()==expected.signature,"fresh process restores exact settlement blocks, furnishings and roads"):await finish(false);return
  if not require(game.player.position.distance_to(Vector3(expected.spawn[0],expected.spawn[1],expected.spawn[2]))<0.1,"on-foot start survives reopen"):await finish(false);return
 else:
  if not require(game.structures.blocks.stats().cells==0,"preparation starts in an empty staging world"):await finish(false);return
  game.structure_mode=true;game.structure_rotation=0
  var source:=-1
  for i in game.structure_prefabs.size():
   if game.structure_prefabs[i].resource_name=="Furnished cottage with storage":source=i;break
  if not require(source>=0,"registered furnished cottage is available"):await finish(false);return
  game.prefab_library.directory="user://checkpoint_prefabs/"+game.terrain.save_slot
  var count:int=game.structure_prefabs.size()
  game._frontage_sources_construction(PackedInt32Array([source]),1,8,3,1703,"Gameplay settlement",2)
  if not require(await wait_until(func():return game.structure_prefabs.size()==count+1,10),"existing native editor composes connected furnished streets"):await finish(false);return
  game.camera.global_position=game.player.global_position+Vector3(0,15,0)
  game.camera.look_at(game.player.global_position+Vector3(10,-5,0))
  await physics_frame
  game._survey_construction()
  if not require(await wait_until(func():return not game.construction_palette.survey_busy,20) and not game._survey_plan.is_empty(),"terrain survey finds supported settlement grade"):await finish(false);return
  game.player.global_position-=Vector3(100,0,0)
  game._prepare_construction_site()
  if not require(await wait_until(func():return game.site_preparation.status!="running",30) and game.site_preparation.status=="complete","native grading and asphalt preparation complete"):await finish(false);return
  game._place_prepared_site()
  if not require(await wait_until(func():return game._foundation_placement.is_empty(),20) and game.structures.blocks.stats().cells>0,"staged furnished settlement publishes"):await finish(false);return
  var target:Vector3=Vector3(game.site_preparation.plan.target)
  game.needs_floor_spawn=false;game.fly=false
  game.player.position=Vector3(target.x+4.5,target.y+2.1,game.road_palette.prepared_streets[0].ends[0].z-11.0)
  game.yaw=0;game.pitch=-0.15;game.player.rotation.y=0
  game.camera.position=Vector3(0,1.6,0);game.camera.rotation=Vector3(game.pitch,0,0)
  game.terrain.focus=game.player.position;game.structures.set_model_focus(game.player.position)
  game.construction_palette.survey_dialog.hide()
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

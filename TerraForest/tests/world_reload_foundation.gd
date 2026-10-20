# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var stages:Dictionary={}
var max_retire_ms:=0.0
var restore_frames:=0
var preparation_frames:=0
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60
 game.terrain.stage_measured.connect(func(label:String,ms:float):
  if label=="retire collision/mesh":max_retire_ms=maxf(max_retire_ms,ms)
  if label=="reload preparation frame":preparation_frames+=1
  if label=="restore frame":
   restore_frames+=1
   if game.terrain.world_ready:check(false,"partial component restoration must not publish world readiness")
  if label.begins_with("restore ") or label.begins_with("reload ") or label=="receive reload":stages[label]=maxf(stages.get(label,0.0),ms))
 root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved world starts before reload"):await done();return
 game.terrain.autosave_timer=-3600.0
 var lake:Dictionary=game.lakes._lakes.values()[0]
 var ray_from:Vector3=Vector3(lake.seed.x,lake.level+2,lake.seed.z)
 var ray_to:Vector3=Vector3(lake.seed.x,lake.level-2,lake.seed.z)
 if not check(await wait_for(func():return game.lakes.water.raycast_surface(ray_from,ray_to).hit,30),"water surface query publishes before reload"):await done();return
 var hit_before:Dictionary=game.lakes.water.raycast_surface(ray_from,ray_to)
 var before:Dictionary=game.lakes.water.statistics()
 var identity:String=game.lakes.water.survey_cache_identity()
 var old_epoch:int=game.terrain.epoch
 stages.clear();restore_frames=0;preparation_frames=0
 var old_roots:Array=[]
 for entry:Dictionary in game.terrain.tiles.values():old_roots.append(entry.node)
 var began:=Time.get_ticks_usec();game.terrain.reload_world()
 print("RELOAD_DISPATCH ms=",(Time.get_ticks_usec()-began)/1000.0)
 var hidden:=true
 for node:Node3D in old_roots: hidden=hidden and (not is_instance_valid(node) or not node.visible)
 check(hidden,"old terrain is hidden immediately before deferred data retirement")
 if not check(await wait_for(func():return game.terrain.epoch>old_epoch and game.terrain.world_ready and not game.loading_active,60),"populated world reload completes"):await done();return
 check(game.terrain.snapshot_restore_ok,"all components restore successfully")
 check(restore_frames>1 and game.terrain._restore_pending.is_empty(),"component restoration spans frames and closes publication barrier")
 print("COMPONENT_RESTORE_FRAMES ",restore_frames)
 check(preparation_frames>1 and not game.ground_cover._reset_active and not game.terrain._reload_preparing,"ground cover preparation spans frames and finishes before readiness")
 print("RELOAD_PREPARATION_FRAMES ",preparation_frames)
 var released:=true
 for batch:Node3D in game.ground_cover.batches:released=released and batch.stats().retired_collection_units==0 and batch.render_stats().retired_render_bytes==0
 check(released,"all native vegetation retirement records and render buffers drain")
 check(game.lakes.water.survey_cache_identity()==identity,"water content identity survives reload")
 check(game.lakes.water.statistics().water_ml==before.water_ml,"reload preserves generated water quantity")
 check(game.lakes.water.statistics().map_identity_scene_hash_us==0,"reload hashes water off scene thread")
 check(await wait_for(func():return game.lakes._retirement_jobs.is_empty(),5),"retired water worker releases its state")
 if check(await wait_for(func():return game.lakes.water.raycast_surface(ray_from,ray_to).hit,30),"water interaction surface republishes after reload"):
  check(game.lakes.water.raycast_surface(ray_from,ray_to).point.distance_to(hit_before.point)<0.001,"republished interaction surface retains exact target")
 check(await wait_for(func():return game.terrain.retired_payloads.is_empty() and game.terrain.retired_nodes.is_empty(),20),"retired terrain payloads and nodes drain completely")
 print("TERRAIN_RETIRE_MAX ms=",max_retire_ms)
 print("WATER_RESTORE_PROFILE ",JSON.stringify(game.lakes.last_restore_profile))
 print("RELOAD_STAGES ",JSON.stringify(stages))
 game.world_map.set_open(true)
 if check(await wait_for(func():return game.world_map.water_survey.complete and game.world_map.block_survey.complete and game.world_map.model_survey.complete,35),"all component maps complete after reload"):
  check(game.world_map.water_survey.fast_cache_hits>0 and game.world_map.water_survey.source_calls==0,"reload water map reuses certified cache")
 await done()
func done()->void:
 print("WORLD_RELOAD_FOUNDATION failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)

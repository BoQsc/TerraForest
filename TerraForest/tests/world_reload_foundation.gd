# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var stages:Dictionary={}
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60
 game.terrain.stage_measured.connect(func(label:String,ms:float):
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
 stages.clear()
 var began:=Time.get_ticks_usec();game.terrain.reload_world()
 print("RELOAD_DISPATCH ms=",(Time.get_ticks_usec()-began)/1000.0)
 if not check(await wait_for(func():return game.terrain.epoch>old_epoch and game.terrain.world_ready and not game.loading_active,60),"populated world reload completes"):await done();return
 check(game.terrain.snapshot_restore_ok,"all components restore successfully")
 check(game.lakes.water.survey_cache_identity()==identity,"water content identity survives reload")
 check(game.lakes.water.statistics().water_ml==before.water_ml,"reload preserves generated water quantity")
 check(game.lakes.water.statistics().map_identity_scene_hash_us==0,"reload hashes water off scene thread")
 check(await wait_for(func():return game.lakes._retirement_jobs.is_empty(),5),"retired water worker releases its state")
 if check(await wait_for(func():return game.lakes.water.raycast_surface(ray_from,ray_to).hit,30),"water interaction surface republishes after reload"):
  check(game.lakes.water.raycast_surface(ray_from,ray_to).point.distance_to(hit_before.point)<0.001,"republished interaction surface retains exact target")
 print("WATER_RESTORE_PROFILE ",JSON.stringify(game.lakes.last_restore_profile))
 print("RELOAD_STAGES ",JSON.stringify(stages))
 game.world_map.set_open(true)
 if check(await wait_for(func():return game.world_map.water_survey.complete and game.world_map.block_survey.complete and game.world_map.model_survey.complete,35),"all component maps complete after reload"):
  check(game.world_map.water_survey.fast_cache_hits>0 and game.world_map.water_survey.source_calls==0,"reload water map reuses certified cache")
 await done()
func done()->void:
 print("WORLD_RELOAD_FOUNDATION failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved world loads"):await done();return
 game.app_focused=true;game.world_map.set_open(true)
 var atlas=game.world_map;var survey=atlas.water_survey
 if not check(await wait_for(func():return survey.complete and atlas.texture!=null and atlas.updates.dirty.is_empty() and atlas.updates.pending.is_empty(),40),"terrain and actual water map complete"):await done();return
 check(not survey.fast_identity().is_empty(),"loaded water has certified map identity")
 check(game.lakes.water.statistics().map_identity_scene_hash_us==0,"world loading prepares water identity off scene thread")
 if "--expect-water-map-hit" in OS.get_cmdline_user_args():check(survey.fast_cache_hits==1 and survey.source_calls==0 and survey.visibility_calls==0,"fresh process reuses water cache without source scans")
 var before:PackedByteArray=survey.texture.get_image().get_data();var land:PackedByteArray=atlas.updates.image.get_data()
 var has_water:=false
 for i in range(3,before.size(),4):has_water=has_water or before[i]>0
 check(has_water,"actual lakes contribute visible blue coverage")
 atlas.view.overview();await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/world_map_water_before.png")
 var builds:int=survey.builds;atlas.set_open(false);game.app_focused=true;atlas.set_open(true)
 for i in 5:await process_frame
 check(survey.complete and survey.builds==builds,"unchanged map reopening reuses completed water raster")
 game.lakes.set_process(false)
 var snapshot:PackedByteArray=game.lakes.capture_snapshot()
 var removed:int=game.lakes.water.remove_bounds(AABB(Vector3.ZERO,Vector3(2000,256,2000)))
 check(removed>0,"real water store changes")
 check(game.lakes.water.survey_cache_identity().is_empty(),"water removal clears certified shortcut")
 if not check(await wait_for(func():return survey.complete and survey.builds>builds,30),"water removal rebuilds map layer"):await done();return
 var empty:PackedByteArray=survey.texture.get_image().get_data();var clear:=true
 for i in range(3,empty.size(),4):clear=clear and empty[i]==0
 check(clear and atlas.updates.image.get_data()==land,"removed lakes leave no stale blue pixels and do not rebuild terrain")
 atlas.view.overview();await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/world_map_water_removed.png")
 builds=survey.builds
 var factory=ClassDB.instantiate("NativeWaterMapIdentity")
 var restore_worker:=Thread.new();restore_worker.start(factory.prepare.bind(snapshot))
 while restore_worker.is_alive():await process_frame
 var prepared:RefCounted=restore_worker.wait_to_finish()
 check(game.lakes.water.restore_prepared(prepared),"worker-decoded original water snapshot restores")
 check(game.lakes.water.capture_snapshot(prepared.get_catalog())==snapshot,"worker handoff preserves all water/contact bytes")
 if not check(await wait_for(func():return survey.complete and survey.builds>builds,30),"restored water resurvey completes"):await done();return
 check(survey.texture.get_image().get_data()==before,"restored water produces identical map coverage")
 check(await wait_for(func():return survey.io==null,5),"water cache I/O completes")
 if "--expect-water-map-hit" in OS.get_cmdline_user_args():check(survey.cache_hits>=2 and survey.visibility_calls==0,"fresh process reuses independently keyed water rasters")
 print("MAP_WATER_CACHE hits=",survey.cache_hits," writes=",survey.cache_writes)
 print("MAP_WATER_PROFILE builds=",survey.builds," source_calls=",survey.source_calls," reduced_points=",survey.raster.count()," visibility_calls=",survey.visibility_calls," max_source_us=",survey.max_source_us," max_visibility_ms=",survey.max_visibility_ms)
 await done()
func done()->void:
 print("WORLD_MAP_WATER failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)

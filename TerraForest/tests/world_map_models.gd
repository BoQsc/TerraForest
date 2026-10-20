# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved world loads"):await done();return
 game.app_focused=true;game.world_map.set_open(true)
 var atlas=game.world_map;var survey=atlas.model_survey
 var collection=game.structures._models["architecture/metal_beam/v1"]
 var residency:Dictionary={}
 for asset in game.structures._models:residency[asset]=game.structures._models[asset].region_stats()
 if not check(await wait_for(func():return survey.complete and survey.io==null and atlas.block_survey.complete and atlas.water_survey.complete and atlas.texture!=null,55),"all map layers complete"):await done();return
 var before:PackedByteArray=survey.texture.get_image().get_data()
 var unchanged:=true
 for asset in residency:unchanged=unchanged and residency[asset]==game.structures._models[asset].region_stats()
 check(survey.archived_reads>0 and unchanged,"archived object survey preserves all collection residency")
 if "--expect-model-map-hit" in OS.get_cmdline_user_args():check(survey.cache_hits==1 and survey.visibility_calls==0,"fresh process reuses object raster")
 atlas.view.center=Vector2(1000,1000);atlas.view.zoom=4;atlas.view.queue_redraw()
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/world_map_models_before.png")
 var built:int=survey.builds;atlas.set_open(false);game.app_focused=true;atlas.set_open(true)
 for n in 4:await process_frame
 check(survey.complete and survey.builds==built,"unchanged reopening reuses object layer")
 var id:int=collection.insert_instance(PackedFloat32Array([14,0,0,1010,0,2,0,160,0,0,14,935]),AABB())
 if not check(id>0,"actual large placed model inserted"):await done();return
 if not check(await wait_for(func():return survey.complete and survey.builds>built and survey.io==null,45),"placement refreshes actual object map"):await done();return
 check(survey.texture.get_image().get_data()!=before,"placed model adds map coverage")
 atlas.view.center=Vector2(1000,935);atlas.view.zoom=8;atlas.view.queue_redraw()
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/world_map_models_edited.png")
 built=survey.builds
 check(collection.remove_instances(PackedInt64Array([id])),"temporary model removed")
 if not check(await wait_for(func():return survey.complete and survey.builds>built and survey.io==null,45),"removal refreshes actual object map"):await done();return
 check(survey.texture.get_image().get_data()==before,"removal restores identical map coverage")
 survey.stamp=""
 if check(await wait_for(func():return survey.ticket>0,15),"object survey has cancellable archive request"):
  atlas.set_open(false);check(survey.ticket==0 and survey.lease==0,"map close releases object request and lease")
 print("MODEL_MAP_PROFILE builds=",survey.builds," archived_reads=",survey.archived_reads," hits=",survey.cache_hits," writes=",survey.cache_writes," visibility_calls=",survey.visibility_calls," max_visibility_ms=",survey.max_visibility_ms)
 await done()
func done()->void:
 if game.world_map.opened:game.world_map.set_open(false)
 print("WORLD_MAP_MODELS failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)

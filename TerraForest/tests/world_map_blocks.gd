# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved world loads"):await done();return
 game.app_focused=true;game.world_map.set_open(true)
 var atlas=game.world_map;var survey=atlas.block_survey;var blocks=game.structures.blocks
 var residency:Dictionary=blocks.region_stats()
 if not check(await wait_for(func():return survey.complete and survey.io==null and atlas.water_survey.complete and atlas.texture!=null,40),"all actual map layers complete"):await done();return
 var before:PackedByteArray=survey.texture.get_image().get_data()
 check(survey.archived_reads>0 and blocks.region_stats()==residency,"map includes archived buildings without admitting gameplay regions")
 if "--expect-block-map-hit" in OS.get_cmdline_user_args():check(survey.cache_hits==1 and survey.visibility_calls==0,"fresh process reuses building raster cache")
 atlas.view.center=Vector2(1000,1000);atlas.view.zoom=4;atlas.view.queue_redraw()
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/world_map_blocks_before.png")
 var north:Vector3=atlas.places.filter(func(place:Dictionary):return place.title=="North neighborhood")[0].position
 atlas.view.center=Vector2(north.x,north.z);atlas.view.zoom=6;atlas.view.queue_redraw()
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/world_map_blocks_archived.png")
 var built:int=survey.builds;atlas.set_open(false);game.app_focused=true;atlas.set_open(true)
 for n in 4:await process_frame
 check(survey.complete and survey.builds==built,"unchanged reopen reuses map")
 var key:=Vector3i(15,2,14)
 if not check(blocks.is_region_loaded(key),"temporary overhead footprint is in available region"):await done();return
 var saved:PackedByteArray=blocks.capture_region(key);var cells:=PackedInt32Array()
 for z in range(930,942):
  for x in range(970,982):cells.append_array(PackedInt32Array([x,160,z,1]))
 check(blocks.set_cells(cells),"actual block placement changes authored world")
 if not check(await wait_for(func():return survey.complete and survey.builds>built and survey.io==null,30),"building edit invalidates and refreshes footprint"):await done();return
 check(survey.texture.get_image().get_data()!=before,"new construction changes map pixels")
 atlas.view.center=Vector2(975,935);atlas.view.zoom=8;atlas.view.queue_redraw()
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/world_map_blocks_edited.png")
 built=survey.builds
 check(blocks.restore_region(saved,blocks.capture_region(key)),"original region restored")
 if not check(await wait_for(func():return survey.complete and survey.builds>built and survey.io==null,30),"restored footprint settles"):await done();return
 check(survey.texture.get_image().get_data()==before,"restoration reproduces original footprint")
 # Force a new survey and close while its archive read is outstanding.
 survey.stamp=""
 if check(await wait_for(func():return survey.ticket>0,10),"map has one cancellable archive request"):
  atlas.set_open(false)
  check(survey.ticket==0 and survey.lease==0,"closing map releases survey request and checkpoint lease")
 print("BLOCK_MAP_PROFILE builds=",survey.builds," archived_reads=",survey.archived_reads," cache_hits=",survey.cache_hits," cache_writes=",survey.cache_writes," native_ms=",survey.max_visibility_ms)
 await done()
func done()->void:
 if game.world_map.opened:game.world_map.set_open(false)
 print("WORLD_MAP_BLOCKS failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)

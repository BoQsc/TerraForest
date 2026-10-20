# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved world loads"):await done();return
 game.app_focused=true;game.world_map.set_open(true)
 var atlas=game.world_map
 if not check(await wait_for(func():return atlas.texture!=null and atlas.updates.dirty.is_empty() and atlas.updates.pending.is_empty(),60),"saved terrain patches complete"):await done();return
 var before:PackedByteArray=atlas.updates.image.get_data();var builds:int=atlas.builds;var patches:int=atlas.updates.patches
 var focus:Vector3=game.terrain.focus
 atlas.view.overview()
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/world_map_edits_before.png")
 atlas.set_open(false)
 var codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
 var core=ClassDB.instantiate("TerrainCore");core.execute(codec.command(6,[game.terrain.backend.world_seed,game.terrain.backend.world_generator]))
 var center:=Vector3(1050,0,1310);center.y=core.execute(codec.point_command(center)).decode_float(12)
 if not check(game.terrain.edit(codec.brush(center,center,12,1,false,3),center-Vector3.ONE*14,center+Vector3.ONE*14),"native excavation admitted"):await done();return
 if not check(await wait_for(func():return not game.terrain.pending_edit,30),"excavation publishes"):await done();return
 game.app_focused=true;atlas.set_open(true)
 if not check(await wait_for(func():return atlas.updates.dirty.is_empty() and atlas.updates.pending.is_empty(),15),"edited map patch queue drains"):await done();return
 check(before!=atlas.updates.image.get_data(),"excavation changes displayed terrain pixels")
 check(atlas.builds==builds and atlas.updates.patches-patches<=16,"local edit avoids whole-world survey")
 check(game.terrain.focus.distance_to(focus)<1,"map updates do not move streaming focus")
 atlas.view.center=Vector2(center.x,center.z);atlas.view.zoom=6;atlas.view.queue_redraw()
 for frame in 10:await process_frame
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/world_map_edits_after.png")
 print("MAP_PATCH_PROFILE total=",atlas.updates.patches," local=",atlas.updates.patches-patches," max_native_ms=",atlas.updates.max_native_ms)
 await done()
func done()->void:
 print("WORLD_MAP_EDITS failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)

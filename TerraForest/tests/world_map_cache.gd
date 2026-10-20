# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"world loads"):await done();return
 game.app_focused=true;game.world_map.set_open(true)
 var u=game.world_map.updates
 if not check(await wait_for(func():return u.image!=null and u.identity_checked and u.dirty.is_empty() and u.pending.is_empty() and u.cache_saved and u.io==null,40),"complete map cache ready"):await done();return
 if "--expect-map-hit" in OS.get_cmdline_user_args():check(u.cache_hits==1 and u.patches==0,"fresh process reuses exact saved terrain without native resurvey")
 else:check(u.cache_writes==1 and u.patches>0,"cold map surveys and publishes one cache entry")
 var digest:=preload("res://addons/world_runtime/survey_cache.gd").digest(u.image.get_data()).hex_encode()
 print("MAP_CACHE_PROFILE hits=",u.cache_hits," writes=",u.cache_writes," patches=",u.patches," pixels_sha256=",digest)
 await done()
func done()->void:
 print("WORLD_MAP_CACHE failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)

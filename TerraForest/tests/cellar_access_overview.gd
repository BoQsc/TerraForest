# SPDX-License-Identifier: 0BSD
extends "res://tests/regional_connected_access.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"world loads"):await done();return
 var site:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator).sites[1].position
 game.teleport(site+Vector3(28,0,20))
 if not check(await wait_for(func():return not game.loading_active,45),"cellar overview residency"):await done();return
 game.set_physics_process(false);game._clear_motion()
 game.camera.global_position=site+Vector3(48,23,46)
 game.camera.look_at(site+Vector3(22,0,17))
 for frame in 60:await process_frame
 await done()
func done()->void:
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/cellar_access_overview.png")
 print("CELLAR_ACCESS_OVERVIEW failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();quit(1 if failures else 0)

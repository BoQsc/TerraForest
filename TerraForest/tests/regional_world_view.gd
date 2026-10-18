# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+60000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 if game.loading_active or game.terrain.backend.world_generator!=7:quit(1);return
 game.set_physics_process(false);game._clear_motion()
 var plan:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed)
 var center:Vector3=plan.sites[0].position
 game.teleport(center+Vector3(0,0,100))
 deadline=Time.get_ticks_msec()+45000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 if game.loading_active:quit(1);return
 game.camera.global_position=center+Vector3(35,25,125);game.camera.look_at(center+Vector3(0,0,50))
 for i in 30:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/regional_world_view.png")
 print("REGIONAL_WORLD_VIEW generator=",game.terrain.backend.world_generator," buildings_cells=",game.structures.blocks.stats().cells," roads=",plan.roads.size())
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit()

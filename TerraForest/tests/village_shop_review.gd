# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:call_deferred("run")
func ready_world(game:Node)->bool:
 var deadline:int=Time.get_ticks_msec()+60000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 return not game.loading_active
func run()->void:
 var game=load("res://demo/world.tscn").instantiate()
 game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await ready_world(game):quit(1);return
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 var center:Vector3=layout.sites[3].position
 # Northern lot four faces towards the southern cross street.
 var shop:Vector3=center+Vector3(24,0,-36)
 game.teleport(shop+Vector3(20,3,-22))
 if not await ready_world(game):quit(1);return
 game.set_physics_process(false);game._clear_motion()
 game.camera.global_position=shop+Vector3(23,10,-28)
 game.camera.look_at(shop+Vector3(0,5,0))
 for i in 120:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/village_shop_exterior.png")
 game.camera.global_position=shop+Vector3(-4,3,-6)
 game.camera.look_at(shop+Vector3(0,2,3))
 for i in 5:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/village_shop_interior.png")
 print("VILLAGE_SHOP_REVIEW failures=0")
 game.free();quit()

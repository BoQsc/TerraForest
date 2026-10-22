# SPDX-License-Identifier: 0BSD
extends "res://tests/village_shop_review.gd"
func run()->void:
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
 if not await ready_world(game):quit(1);return
 game.set_physics_process(false);game._clear_motion();game.app_focused=true
 var before:int=game.lakes.statistics().regions
 game.world_map.set_open(true)
 var started:=Time.get_ticks_msec();var survey:Node=game.world_map.water_survey
 while Time.get_ticks_msec()-started<60000 and not survey.complete and not survey.failed:await process_frame
 if not survey.complete:print("OCEAN_MAP_INCOMPLETE ",survey.description()," calls=",survey.visibility_calls," offset=",survey.offset);game.free();quit(1);return
 var image:Image=survey.texture.get_image();var failures:=0
 if "--expect-ocean-map-cache" in OS.get_cmdline_user_args() and (survey.cache_hits!=1 or survey.visibility_calls!=0):failures+=1
 for point:Vector2i in [Vector2i(2,128),Vector2i(253,128),Vector2i(128,2),Vector2i(128,253),Vector2i(2,2)]:
  if image.get_pixelv(point).a<0.9:failures+=1
 if image.get_pixel(128,128).a>0:failures+=1
 if game.lakes.statistics().regions!=before:failures+=1
 print("OCEAN_MAP_READY ms=",Time.get_ticks_msec()-started," source_calls=",survey.source_calls," visibility_calls=",survey.visibility_calls," regions=",before)
 var builds:int=survey.builds
 game.lakes.water.update_ocean_residency(Vector3(4,40,1000),1)
 for frame in 60:await process_frame
 if survey.builds!=builds:failures+=1
 game.world_map.view.overview()
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/world_map_ocean.png")
 game.free();print("WORLD_MAP_OCEAN failures=",failures);quit(failures)

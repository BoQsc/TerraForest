# SPDX-License-Identifier: 0BSD
extends SceneTree
const Checkpoint=preload("res://demo/cave_checkpoint.gd")
func _initialize()->void:run.call_deferred()
func ready_world(game:Node)->bool:
 var deadline:=Time.get_ticks_msec()+60000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 return not game.loading_active
func run()->void:
 var route:Dictionary=Checkpoint.route()
 if route.is_empty():push_error("Cave checkpoint query failed");quit(1);return
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
 game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await ready_world(game):push_error("Cave world startup did not finish");game.terrain.shutdown();game.free();quit(1);return
 if game.terrain.backend.world_generator!=6 or game.terrain.backend.world_seed!=1703 or not game.temporary_world:
  push_error("Cave review requires temporary generator6 seed1703");game.terrain.shutdown();game.free();quit(1);return
 Checkpoint.position_player(game,route)
 if not await ready_world(game):push_error("Cave entrance collision did not arrive");game.terrain.shutdown();game.free();quit(1);return
 game.set_physics_process(true);game.headlamp.visible=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 var layer:=CanvasLayer.new();root.add_child(layer)
 var label:=Label.new();label.position=Vector2(400,30);label.add_theme_font_size_override("font_size",21)
 label.add_theme_color_override("font_shadow_color",Color.BLACK);label.add_theme_constant_override("shadow_offset_x",2);label.add_theme_constant_override("shadow_offset_y",2)
 label.text="NATURAL CAVE REVIEW / disposable world\nWalk into the entrance ahead, then return to the surface.\nHeadlamp is on. Esc opens controls. Changes are discarded."
 layer.add_child(label)
 if "--review-smoke" in OS.get_cmdline_user_args():
  for frame in 10:await physics_frame
  await RenderingServer.frame_post_draw
  DirAccess.make_dir_recursive_absolute("res://reports/natural_cave_review")
  root.get_texture().get_image().save_png("res://reports/natural_cave_review/start.png")
  var okay:bool=not game.fly and game.player.position.distance_to(route.points[0])<0.5 and game.player.is_on_floor() and not game.session_menu.developer
  print("NATURAL_CAVE_REVIEW failures=",0 if okay else 1)
  game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();quit(0 if okay else 1)

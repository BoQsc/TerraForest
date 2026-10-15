# SPDX-License-Identifier: 0BSD
extends "res://tests/natural_cave_walk.gd"
const Checkpoint=preload("res://demo/cave_checkpoint.gd")
func run()->void:
 var route:Dictionary=Checkpoint.route()
 if route.is_empty():push_error("Cave route query failed");quit(1);return
 game=load("res://demo/world.tscn").instantiate();game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await wait_for(func():return not game.loading_active):failures+=1;await finish();return
 if game.terrain.backend.world_generator!=6 or game.terrain.backend.world_seed!=1703:
  push_error("Depth route requires generator6 seed1703");failures+=1;await finish();return
 Checkpoint.position_player(game,route)
 if not await wait_for(func():return not game.loading_active):failures+=1;await finish();return
 game.set_physics_process(true);game.headlamp.visible=true
 for frame in 5:await physics_frame
 for index in [1,2,3,2,1,0]:
  var passed:bool=await walk_to(route.points[index])
  print("PASS " if passed else "FAIL ","cave depth waypoint ",index)
  if not passed:failures+=1;break
 await finish()

# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,45),"world loads"):await finish();return
 game.set_physics_process(false);game._clear_motion()
 var session=game.world_vehicle
 check(game.actors.enable(),"actor simulation enabled")
 if not check(session._install_vehicle(game,Transform3D(Basis.IDENTITY,game.player.position+Vector3(0,1,-4))),"native vehicle fixture installs"):await finish();return
 session.car.freeze=true
 for frame in 5:await physics_frame
 var first:Vector3=session.safe_exit_position(game)
 if not check(first.is_finite(),"fixture has a supported exit"):await finish();return
 game.actors.spawn(first+Vector3.UP*.93);game.actors.select_near(first)
 for frame in 3:await physics_frame
 var second:Vector3=session.safe_exit_position(game)
 if not check(second.is_finite() and second.distance_to(first)>1,"occupied exit is rejected in favour of other side"):await finish();return
 game.actors.spawn(second+Vector3.UP*.93);game.actors.select_near(first)
 for frame in 3:await physics_frame
 # There are five exit candidates, including the rear and wider side offsets.
 # Two occupied sides must not imply that every other supported exit is blocked.
 for candidate in 3:
  var remaining:Vector3=session.safe_exit_position(game)
  if not remaining.is_finite():break
  check(remaining.distance_to(first)>.7 and remaining.distance_to(second)>.7,"additional exit avoids the already occupied sides")
  game.actors.spawn(remaining+Vector3.UP*.93);game.actors.select_near(first)
  for frame in 3:await physics_frame
 check(not session.safe_exit_position(game).is_finite(),"all actor-occupied exits refuse player placement")
 check(session.car.collision_mask==15,"single vehicle chassis includes actor collision")
 check((session.car.wheel_rays[0].collision_mask & 8)==0,"wheel support rays exclude actors")
 var handle:int=game.actors.pool.active_handles()[0]
 var position:Vector3=game.actors.store.get_position(handle)
 game.actors.orders.set_target(game.actors.store.persistent_id(handle),position+Vector3(0,0,2))
 await physics_frame
 game.actors.update_simulation(1.0/60,position,true,game._actor_collision_ready)
 var state:String=game.actors.pool.navigation_status(handle).state
 check(state!="idle","actor has a route before vehicle change")
 session.capture_snapshot()
 # Flush any initial position publication, then rebuild the affected route.
 await physics_frame
 game.actors.update_simulation(1.0/60,position,true,game._actor_collision_ready)
 state=game.actors.pool.navigation_status(handle).state
 session.fleet.set_pose(session.car_identity,session.car.global_transform)
 check(game.actors.pool.navigation_status(handle).state==state,"unchanged vehicle leaves existing actor route intact")
 session.car.position+=Vector3(0,0,10)
 session.update(game,0.21)
 check(game.actors.pool.navigation_status(handle).state=="idle","ordinary vehicle update invalidates intersecting actor route")
 await physics_frame
 game.actors.update_simulation(1.0/60,position,true,game._actor_collision_ready)
 check(game.actors.pool.navigation_status(handle).state!="idle","invalidated actor starts bounded replanning")
 await finish()

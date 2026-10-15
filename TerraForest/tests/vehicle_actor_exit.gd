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
 check(not session.safe_exit_position(game).is_finite(),"both actor-occupied exits refuse player placement")
 check(session.car.collision_mask==15,"single vehicle chassis includes actor collision")
 check((session.car.wheel_rays[0].collision_mask & 8)==0,"wheel support rays exclude actors")
 await finish()

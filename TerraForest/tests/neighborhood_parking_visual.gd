# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved world loads"):await done();return
 var center:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator).sites[3].position
 var bay:Dictionary=preload("res://addons/structures/northern_lots.gd").parking(center)
 game.teleport(center+Vector3(0,0,65))
 if not check(await wait_for(func():return not game.loading_active,45),"northern bay streams"):await done();return
 var session=game.world_vehicle
 var restored:Dictionary=session.storage.decode_fleet(session.capture_snapshot())
 var id:=0
 for record:Dictionary in restored.records:
  if record.pose.origin.distance_to(bay.pose.origin)<0.1:id=record.identity
 if not check(id>0 and await wait_for(func():return session.activation.residents.has(id),15),"parked saved car activates"):await done();return
 var car:RigidBody3D=session.activation.residents[id]
 check(car.freeze and not car.is_physics_processing() and not car.controls_enabled,"unoccupied car has no active driving physics")
 check(game.road_palette.prepared_streets.any(func(r):return r.ends==bay.street_ends and r.width==8),"bay road anchor restores for map and editor")
 game.set_physics_process(false);game._clear_motion()
 var views:Array=[{"from":Vector3(6,4,82),"to":Vector3(-10,0.8,70)},{"from":Vector3(8,10,100),"to":Vector3(-8,0,65)}]
 for i in views.size():
  game.camera.global_position=center+views[i].from;game.camera.look_at(center+views[i].to)
  for frame in 30:await process_frame
  await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/neighborhood_parking_%d.png"%i)
 await done()
func done()->void:
 print("NEIGHBORHOOD_PARKING_VISUAL failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)

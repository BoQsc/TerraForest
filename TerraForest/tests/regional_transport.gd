# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func key(code:int,pressed:bool)->void:
 var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
 Input.parse_input_event(event);Input.flush_buffered_events()
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,90),"transport world loads"):await done();return
 var session=game.world_vehicle
 var saved:Dictionary=session.storage.decode_fleet(session.capture_snapshot())
 if not check(saved.ok and saved.records.size()==2,"two prepared vehicles restore without test spawning"):await done();return
 var index:=0
 for record:Dictionary in saved.records:
  var pose:Transform3D=record.pose
  game.teleport(pose.origin+pose.basis.x*2.8)
  if not check(await wait_for(func():return not game.loading_active,60),"parking area streams"):continue
  if not check(await wait_for(func():return session.activation.residents.has(record.identity),15),"saved parked car activates nearby"):continue
  var car:RigidBody3D=session.activation.residents[record.identity]
  aim(car.position+car.global_basis.x*2.8,car.position+Vector3.UP*.4)
  for tick in 30:await physics_frame
  use()
  if not check(session.driving and session.car_identity==record.identity,"E enters saved vehicle in gameplay"):continue
  for tick in 30:await physics_frame
  var start:Vector3=car.position
  key(KEY_W,true)
  for tick in 240:game.app_focused=true;await physics_frame
  key(KEY_W,false);key(KEY_SPACE,true)
  var deadline:=Time.get_ticks_msec()+8000
  while car.linear_velocity.length()>0.15 and Time.get_ticks_msec()<deadline:await physics_frame
  key(KEY_SPACE,false)
  var distance:=Vector2(car.position.x-start.x,car.position.z-start.z).length()
  check(distance>2 and not car.streaming.waiting and car.linear_velocity.length()<0.15,"saved vehicle drives off its parking position and brakes")
  print("PREPARED_VEHICLE id=",record.identity," distance=",distance," speed=",car.linear_velocity.length())
  use()
  check(not session.driving,"E exits stopped saved vehicle")
  game.camera.global_position=car.position+Vector3(7,4,7);game.camera.look_at(car.position)
  for frame in 30:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/regional_transport_%d.png"%index)
  index+=1
 check(session.fleet.statistics().records==2,"interaction preserves fleet identities without duplication")
 await done()
func done()->void:
 key(KEY_W,false);key(KEY_SPACE,false)
 print("REGIONAL_TRANSPORT failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)

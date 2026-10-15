# SPDX-License-Identifier: 0BSD
extends "res://tests/water_raised_world.gd"
func key_event(code:int,pressed:bool):
 var event:=InputEventKey.new();event.physical_keycode=code;event.keycode=code;event.pressed=pressed
 game._input(event);game._unhandled_input(event)
func run():
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Normal disposable world ready")
 if failures:await finish();return
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var center:=Vector3(floorf(entry.seed.x)+.5,entry.level,floorf(entry.seed.z)+.5)
 var baseline:=amounts(game.lakes.capture_snapshot())
 aim(center);click(MOUSE_BUTTON_LEFT)
 check(await wait_publication() and held_ml()==1000000,"Make a hole through normal bucket input")
 game.fly=false;game.needs_floor_spawn=false;game._clear_motion()
 game.player.global_position=center+Vector3(0,-1.9,1.3)
 game.camera.position=Vector3(0,1.65,0)
 game.pitch=0;game.yaw=0;game.player.rotation=Vector3.ZERO;game.camera.rotation=Vector3.ZERO
 game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 deadline=Time.get_ticks_msec()+6000
 while (not game.terrain.player_region_ready(game.player.position) or not game._additional_motion_ready(0.016)) and Time.get_ticks_msec()<deadline:await physics_frame
 check(game._player_water_depth()>0,"Player body is swimming, not flying")
 var before:Vector3=game.player.global_position
 key_event(KEY_W,true)
 for frame in 8:await physics_frame
 var at_click:Vector3=game.player.global_position
 var start:Vector3=game.camera.global_position
 var end:Vector3=start-game.camera.global_basis.z*3.5
 print("MOVING_BUCKET before=",before," at_click=",at_click," depth=",game._player_water_depth()," input=",game.controls.direction()," surface=",game.lakes.water.raycast_surface(start,end)," vacancy=",game.lakes.water.raycast_vacancy(start,end))
 check(before.distance_to(at_click)>.05 and game._player_water_depth()>0,"Player moves through real swimming physics before clicking")
 click(MOUSE_BUTTON_RIGHT)
 check(await wait_publication() and held_ml()==0,"Moving player's pour completes")
 for frame in 6:await physics_frame
 check(game.controls.direction()!=Vector3.ZERO and game.player.global_position.distance_to(at_click)>.05,"Bucket click preserves held movement")
 key_event(KEY_W,false)
 check(amounts(game.lakes.capture_snapshot())==baseline,"Moving player's aimed hole refills exactly")
 await photo("res://reports/water_moving_player.png")
 await finish()
func finish():
 if game!=null:
  key_event(KEY_W,false)
  game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_MOVING_PLAYER failures=",failures);quit(failures)

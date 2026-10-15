# SPDX-License-Identifier: 0BSD
extends "res://tests/water_raised_world.gd"
func run():
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Normal disposable water world ready")
 if failures:await finish();return
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var center:=Vector3(floorf(entry.seed.x)+.5,entry.level,floorf(entry.seed.z)+.5)
 var baseline:=amounts(game.lakes.capture_snapshot())
 var geometry:=fingerprints()
 aim(center);click(MOUSE_BUTTON_LEFT)
 check(await wait_publication() and held_ml()==1000000,"Normal input scoops a unit")
 game.fly=true;game._clear_motion();game.set_process(false);game.set_physics_process(false)
 game.camera.global_position=center+Vector3(.1,-.25,.1)
 game.camera.look_at(game.camera.global_position+Vector3.RIGHT,Vector3.UP)
 var start:Vector3=game.camera.global_position
 var end:Vector3=start-game.camera.global_basis.z*3.5
 var vacancy:Dictionary=game.lakes.water.raycast_vacancy(start,end)
 var surface:Dictionary=game.lakes.water.raycast_surface(start,end)
 print("SWIMMING_WORLD origin=",start," vacancy=",vacancy," surface=",surface)
 check(not vacancy.hit,"Submerged camera does not select its surrounding empty cells")
 check(surface.hit and start.distance_to(surface.point)>.1,"Crosshair reaches a visible surface ahead")
 await photo("res://reports/water_swimming_before.png")
 click(MOUSE_BUTTON_RIGHT)
 check(await wait_publication() and held_ml()==0,"Normal underwater pour input completes")
 check(amounts(game.lakes.capture_snapshot())==baseline,"Underwater return restores every original water cell")
 check(fingerprints()==geometry,"Underwater return restores published geometry")
 await photo("res://reports/water_swimming_after.png")
 # Two distinct holes: an underwater oblique aim at the second must not
 # distribute its bucket into the first, even near the targeted hole's edge.
 aim(center);click(MOUSE_BUTTON_LEFT)
 check(await wait_publication() and held_ml()==1000000,"Create first nearby hole")
 var inventory=game.player_hud.inventory
 check(inventory.exchange_water(game.player_hud.active_slot,true,inventory.snapshot().revision,1000000),"Move first unit out of this test area")
 var expected:=amounts(game.lakes.capture_snapshot())
 var expected_geometry:=fingerprints()
 var second:Vector3=center+Vector3(1.5,0,1.5)
 aim(second);click(MOUSE_BUTTON_LEFT)
 check(await wait_publication() and held_ml()==1000000,"Create second nearby hole")
 game.camera.global_position=center+Vector3(.8,-.25,.8)
 game.camera.look_at(second+Vector3(-.24,-.25,-.24),Vector3.UP)
 start=game.camera.global_position;end=start-game.camera.global_basis.z*3.5
 print("MULTI_WORLD origin=",start," vacancy=",game.lakes.water.raycast_vacancy(start,end)," surface=",game.lakes.water.raycast_surface(start,end))
 click(MOUSE_BUTTON_RIGHT)
 check(await wait_publication() and held_ml()==0,"Oblique underwater pour completes")
 check(amounts(game.lakes.capture_snapshot())==expected,"Only the aimed hole refills; the other stays unchanged")
 check(fingerprints()==expected_geometry,"Only the aimed hole's published geometry restores")
 await finish()
func finish():
 if game!=null:game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_SWIMMING_WORLD failures=",failures);quit(failures)

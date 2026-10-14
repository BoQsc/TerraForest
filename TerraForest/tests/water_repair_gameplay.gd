# SPDX-License-Identifier: 0BSD
extends "res://tests/water_return_shore.gd"
func run():
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Actual lake ready")
 if failures:await finish();return
 var original:=amounts(game.lakes.capture_snapshot());var view:Transform3D=game.camera.global_transform
 await measured_click(MOUSE_BUTTON_LEFT)
 check(held_ml()==1000000,"Scoop original shore hole")
 var after_hole:=amounts(game.lakes.capture_snapshot())
 var dry:Vector3=game.player.global_position+Vector3(0,0,10)
 var ground:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(dry+Vector3.UP*30,dry-Vector3.UP*30,1))
 check(not ground.is_empty(),"Dry deposit target exists")
 if failures:await finish();return
 aim(ground.position);await measured_click(MOUSE_BUTTON_RIGHT)
 check(held_ml()==0,"Leave original unit on dry ground")
 var entry:Dictionary=game.lakes._lakes.values()[0]
 aim(Vector3(entry.seed.x+3,entry.level,entry.seed.z));await measured_click(MOUSE_BUTTON_LEFT)
 check(held_ml()==1000000,"Collect replacement from different lake area")
 game.camera.global_transform=view;game.camera.global_position+=Vector3(.5,0,0)
 await measured_click(MOUSE_BUTTON_RIGHT)
 var current:=amounts(game.lakes.capture_snapshot());var restored:=true;var missing:=0
 for cell in original:
  if original[cell]>after_hole.get(cell,0):
   missing+=original[cell]-after_hole.get(cell,0)
   restored=restored and current.get(cell,0)==original[cell]
 check(missing==1000000 and restored and held_ml()==0,"Replacement water repairs all of original shore hole")
 results={"original_removed_ml":missing,"restored":restored,"failures":failures}
 await finish()
func finish():
 results.failures=failures
 var file:=FileAccess.open("res://reports/water_repair_gameplay.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_REPAIR_GAMEPLAY failures=",failures);quit(failures)

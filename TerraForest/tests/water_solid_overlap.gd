# SPDX-License-Identifier: 0BSD
extends "res://tests/water_static_mining.gd"
func run():
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Actual lake prepared")
 if failures:await finish();return
 game.set_process(false);game.set_physics_process(false);game._clear_motion()
 game.session_menu.toggle_developer()
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var target:=Vector3i(floori(entry.seed.x+3),floori(entry.level)-1,floori(entry.seed.z))
 var before:=amounts(game.lakes.capture_snapshot());var total:int=game.lakes.statistics().water_ml
 check(game.lakes.depth_at(Vector3(target)+Vector3.ONE*.5)>0,"Terrain placement starts inside water")
 check(game.terrain.set_block(target,1),"Solid terrain placement in water is accepted")
 check(game.lakes.restore_snapshot(game.lakes.capture_snapshot()),"Pending terrain displacement survives water snapshot reload")
 check(await ready_water(),"Solid terrain and water publish")
 var after:=amounts(game.lakes.capture_snapshot());var removed:int=total-game.lakes.statistics().water_ml
 check(removed>0,"Solid deposition deletes replaced water")
 check(game.lakes.depth_at(Vector3(target)+Vector3.ONE*.5)==0,"Placed solid contains no water")
 var untouched:=true
 for key in before:
  var parts:PackedStringArray=key.split(":");var region:int=int(parts[0]);var i:int=int(parts[1])
  var cell:=Vector3i((region>>24)&4095,(region>>12)&4095,region&4095)*8+Vector3i(i%8,(i/8)%8,i/64)
  if not AABB(Vector3(target)-Vector3.ONE,Vector3.ONE*3).has_point(Vector3(cell)*.5):untouched=untouched and after.get(key,0)==before[key]
 check(untouched,"Water beyond local terrain reconstruction remains unchanged")
 var saved:PackedByteArray=game.lakes.capture_snapshot()
 check(game.lakes.restore_snapshot(saved),"Edited water snapshot reloads")
 check(await ready_water(),"Reloaded surfaces publish")
 check(amounts(game.lakes.capture_snapshot())==after,"Reload preserves deleted quantities exactly")
 check(game.terrain.set_block(target,0),"Remove the placed terrain")
 check(await ready_water(),"Terrain removal publishes")
 check(amounts(game.lakes.capture_snapshot())==after,"Digging out the solid does not resurrect deleted water")
 # Smooth deposition uses the same occupied-volume replacement path.
 var sphere:=Vector3(target)+Vector3(4,.5,0)
 var smooth_before:int=game.lakes.statistics().water_ml
 check(game.terrain.sculpt_sphere(sphere,1.5,true),"Smooth terrain deposition into water accepted")
 check(await ready_water(),"Smooth deposition publishes")
 var smooth_after:=amounts(game.lakes.capture_snapshot())
 check(game.lakes.statistics().water_ml<smooth_before,"Smooth deposition removes replaced water")
 check(game.terrain.sculpt_sphere(sphere,1.5,false),"Mine smooth deposited terrain")
 check(await ready_water(),"Smooth excavation publishes")
 check(amounts(game.lakes.capture_snapshot())==smooth_after,"Smooth excavation does not restore deleted water")
 var file:=FileAccess.open("res://reports/water_solid_overlap.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"removed_ml":removed,"target":target,"scope":"Actual terrain placement, water snapshot reload and terrain removal"},"  "));file.close()
 await finish()
func finish():
 if is_instance_valid(game):game.terrain.shutdown();game.queue_free()
 await process_frame;await process_frame
 print("WATER_SOLID_OVERLAP failures=",failures);quit(failures)

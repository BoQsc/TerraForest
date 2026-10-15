# SPDX-License-Identifier: 0BSD
extends "res://tests/water_bucket_roundtrip.gd"
func fingerprints()->Dictionary:
 var result:Dictionary={}
 for coordinate in game.lakes._meshes:
  var mesh:Mesh=game.lakes._meshes[coordinate].mesh
  if mesh!=null and mesh.get_surface_count()>0:
   var vertices:PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
   if not vertices.is_empty():result[coordinate]=hash(vertices.to_byte_array())
 return result
func delta_summary(baseline:Dictionary)->Dictionary:
 var current:=amounts(game.lakes.capture_snapshot());var positive:=0;var negative:=0;var low:=Vector3.INF;var high:=-Vector3.INF
 for p:Vector3i in current:
  var added:int=current[p]-baseline.get(p,0)
  if added>0:positive+=added;low=low.min(Vector3(p)*.5);high=high.max(Vector3(p)*.5)
 var missing_low:=Vector3.INF;var missing_high:=-Vector3.INF
 for p:Vector3i in baseline:
  var missing:=maxi(0,int(baseline[p])-int(current.get(p,0)));negative+=missing
  if missing:missing_low=missing_low.min(Vector3(p)*.5);missing_high=missing_high.max(Vector3(p)*.5)
 return {"positive":positive,"negative":negative,"low":low,"high":high,"missing_low":missing_low,"missing_high":missing_high}
func photo(path:String):
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(path)
func run():
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Normal disposable water world ready")
 if failures:await finish();return
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var center:=Vector3(floorf(entry.seed.x)+0.5,entry.level,floorf(entry.seed.z)+0.5)
 var donor:Vector3=center+Vector3(4,0,0)
 var original_lake:Dictionary=amounts(game.lakes.capture_snapshot())
 var original_meshes:=fingerprints()
 # Build raised water using real mouse actions, including an offset placement.
 for offset:float in [0.0,0.0,-0.5]:
  aim(donor);click(MOUSE_BUTTON_LEFT)
  check(await wait_publication() and held_ml()==1000000,"Collect full unit away from raised placement")
  if failures:await finish();return
  var hit:Dictionary=game.lakes.water.raycast_surface(center+Vector3(offset,4,0),center+Vector3(offset,-1,0))
  check(hit.hit,"Raised placement surface is targetable")
  if failures:await finish();return
  aim(hit.point);click(MOUSE_BUTTON_RIGHT)
  check(await wait_publication() and held_ml()==0,"Place full unit on existing water")
  if failures:await finish();return
 var top:Dictionary=game.lakes.water.raycast_surface(center+Vector3.UP*4,center-Vector3.UP)
 check(top.hit and top.point.y>center.y+0.5,"Player actions made raised water")
 if failures:await finish();return
 var point:Vector3=top.point-Vector3.UP*0.4
 var camera_position:Vector3=point+Vector3(-2.0,0.1,0.4)
 game.fly=true;game._clear_motion();game.set_process(false);game.set_physics_process(false)
 game.camera.global_position=camera_position;game.camera.look_at(point,Vector3.UP)
 var baseline:Dictionary=amounts(game.lakes.capture_snapshot())
 var baseline_meshes:=fingerprints()
 print("RAISED_BASELINE center=",center," delta=",delta_summary(original_lake))
 await photo("res://reports/water_raised_before.png")
 results.cycles=[]
 for cycle in 3:
  var started:=Time.get_ticks_usec();click(MOUSE_BUTTON_LEFT)
  check(await wait_publication() and held_ml()==1000000,"Side scoop of raised water fills full unit")
  if failures:break
  if cycle==0:await photo("res://reports/water_raised_scooped.png")
  click(MOUSE_BUTTON_RIGHT)
  check(await wait_publication() and held_ml()==0,"Return side scoop empties bucket")
  check(amounts(game.lakes.capture_snapshot())==baseline,"Every water cell restored after side scoop/return")
  check(fingerprints()==baseline_meshes,"Published geometry restored exactly after side scoop/return")
  results.cycles.append({"cycle":cycle,"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0})
  if failures:break
 await photo("res://reports/water_raised_returned.png")
 # Reverse the actual transfer: remove the raised placement from its side,
 # and put each bucket into the lower donor hole, not back into the column.
 for cycle in 3:
  point=center+Vector3.UP*0.3
  game.camera.global_position=point+Vector3(-2,0.1,0.4);game.camera.look_at(point,Vector3.UP)
  print("LOWER_AIM ",game.lakes.water.raycast_surface(game.camera.global_position,game.camera.global_position-game.camera.global_basis.z*3.5))
  click(MOUSE_BUTTON_LEFT)
  check(await wait_publication() and held_ml()==1000000,"Lower raised water from the side (%d)"%cycle)
  if failures:break
  print("AFTER_LOWER ",delta_summary(original_lake))
  aim(donor);click(MOUSE_BUTTON_RIGHT)
  check(await wait_publication() and held_ml()==0,"Return raised water into the lower donor hole (%d)"%cycle)
  if failures:break
 print("LOWER_FINAL ",delta_summary(original_lake))
 check(amounts(game.lakes.capture_snapshot())==original_lake,"Moving raised water back restores the original flat lake cell-for-cell")
 check(fingerprints()==original_meshes,"Lowered lake geometry equals original flat lake")
 game.camera.global_position=center+Vector3(-3,1,2);game.camera.look_at(center,Vector3.UP)
 await photo("res://reports/water_lowered.png")
 results.statistics=game.lakes.statistics()
 await finish()
func finish():
 results.failures=failures
 var file:=FileAccess.open("res://reports/water_raised_world.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 if is_instance_valid(game):game.terrain.shutdown();game.queue_free()
 await process_frame;await process_frame
 print("WATER_RAISED_WORLD failures=",failures);quit(failures)

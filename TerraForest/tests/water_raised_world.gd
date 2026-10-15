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
 results.statistics=game.lakes.statistics()
 await finish()
func finish():
 results.failures=failures
 var file:=FileAccess.open("res://reports/water_raised_world.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 if is_instance_valid(game):game.terrain.shutdown();game.queue_free()
 await process_frame;await process_frame
 print("WATER_RAISED_WORLD failures=",failures);quit(failures)

# SPDX-License-Identifier: 0BSD
extends "res://tests/water_ground_pour.gd"
var measuring:=false
var last_frame_us:=0
var frame_ms:Array=[]
func record_frame():
 var now:=Time.get_ticks_usec()
 if measuring:frame_ms.append((now-last_frame_us)/1000.0)
 last_frame_us=now
func measured_click(button:int)->Dictionary:
 frame_ms.clear();last_frame_us=Time.get_ticks_usec();var started:=last_frame_us;measuring=true
 click(button)
 var ready:bool=await wait_publication();measuring=false
 return {"ready":ready,"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,"max_frame_ms":frame_ms.max() if not frame_ms.is_empty() else 0,"water":game.lakes.statistics()}
func wait_publication()->bool:
 var deadline:=Time.get_ticks_msec()+6000
 while Time.get_ticks_msec()<deadline:
  await process_frame
  var s:Dictionary=game.lakes.statistics()
  if game.lakes._pending_bucket.is_empty() and int(s.dirty_meshes)==0 and not s.mesh_batch_active and not s.mesh_publish_pending:return true
 return false
func run():
 process_frame.connect(record_frame)
 game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready") and game.temporary_world,"Disposable gameplay world is ready")
 if failures:await finish();return
 click(MOUSE_BUTTON_LEFT);await wait_publication()
 check(held_ml()==1000000,"One normal click fills the bucket")
 if failures:await finish();return
 var origin:Vector3=game.player.global_position+Vector3(0,0,10)
 var original:Dictionary=amounts(game.lakes.capture_snapshot());results.cases=[]
 for offset in [Vector3.ZERO,Vector3(2,0,0),Vector3(-2,0,0),Vector3(0,0,2),Vector3(0,0,-2),Vector3(4,0,2)]:
  var position:Vector3=origin+offset
  var ground:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(position+Vector3.UP*30,position-Vector3.UP*30,1))
  check(not ground.is_empty(),"Natural ground exists for case %d"%results.cases.size())
  if ground.is_empty():break
  if results.cases.size()==5:
   check(game.terrain.sculpt_sphere(Vector3(ground.position)+Vector3.UP*0.5,2.0),"Mine a crater through the ordinary terrain path")
   deadline=Time.get_ticks_msec()+10000
   while game.terrain.pending_edit and Time.get_ticks_msec()<deadline:await process_frame
   check(not game.terrain.pending_edit,"Mined terrain publishes")
   for frame in 6:await physics_frame
   position+=Vector3(1.25,0,0)
   ground=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(position+Vector3.UP*30,position-Vector3.UP*30,1))
   check(not ground.is_empty(),"Mined crater has a collidable surface")
   if failures:break
  var target:Vector3=ground.position
  check(not game.lakes.water.surface_near(target,1.0).is_finite(),"Round-trip target starts dry")
  if failures:break
  aim(target)
  for frame in 3:await process_frame
  var pour:Dictionary=await measured_click(MOUSE_BUTTON_RIGHT)
  check(pour.ready,"Pour finishes publication")
  check(held_ml()==0,"Full bucket transfers into world")
  if failures:break
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/water_roundtrip_%d.png"%results.cases.size())
  # Aim straight down at the actual clicked terrain position, without searching
  # cell metadata for a specially chosen easier-to-scoop part of the water.
  var scoop:Dictionary=await measured_click(MOUSE_BUTTON_LEFT)
  check(scoop.ready,"Scoop finishes publication")
  var current:Dictionary=amounts(game.lakes.capture_snapshot())
  var same:bool=current==original
  check(held_ml()==1000000 and same,"One scoop recovers the whole pour, with no hidden water remainder")
  var visible:bool=game.lakes.water.raycast_surface(target+Vector3.UP*2,target-Vector3.UP).hit
  check(not visible,"Recovered pour leaves no stale visible water surface")
  results.cases.append({"target":target,"slope_degrees":rad_to_deg(acos(ground.normal.y)),"recovered_ml":held_ml(),"cell_amounts_restored":same,"stale_surface":visible,"pour":pour,"scoop":scoop})
  if failures:break
 await finish()
func finish():
 results.failures=failures
 var file:=FileAccess.open("res://reports/water_bucket_roundtrip.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_BUCKET_ROUNDTRIP failures=",failures);quit(failures)

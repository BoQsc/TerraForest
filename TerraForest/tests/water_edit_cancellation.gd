# SPDX-License-Identifier: 0BSD
extends "res://tests/water_ground_pour.gd"
func run():
 game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Actual review world is ready")
 if failures:await finish();return
 var original:Dictionary=amounts(game.lakes.capture_snapshot())
 for distance in [30,38,46]:
  var position:Vector3=game.player.global_position+Vector3(0,0,distance)
  var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(position+Vector3.UP*30,position-Vector3.UP*30,1))
  check(not hit.is_empty(),"Uncached target has terrain")
  if hit.is_empty():break
  var point:Vector3=hit.position+Vector3.UP*0.03
  if distance==46:
   var inventory=game.player_hud.inventory;var slot:int=game.player_hud.active_slot
   check(inventory.exchange_water(slot,false,inventory.snapshot().revision,1000000),"Prepare full test bucket")
   var reply:Dictionary=game.lakes.bucket(point+Vector3.UP*2,point,true,inventory,slot,inventory.snapshot().revision)
   check(reply.pending and not game.lakes._pending_bucket.is_empty(),"Cold-target bucket pour awaits terrain data")
   game.lakes.dev_brush(point,true)
  else:
   game.lakes.dev_brush(point,false)
   check(not game.lakes._pending_dev.is_empty(),"Cold-target developer placement awaits terrain data")
   if distance==30:game.lakes.dev_brush(point,true)
   else:game.lakes.dev_brush(Vector3.INF,false)
  check(game.lakes._pending_dev.is_empty() and game.lakes._pending_bucket.is_empty(),"Latest action cancels the obsolete pending placement")
 # Expiring an uncached action must stop saying "Preparing" and retain items.
 var remote:Vector3=game.player.global_position+Vector3(0,0,54)
 var floor_hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(remote+Vector3.UP*30,remote-Vector3.UP*30,1))
 check(not floor_hit.is_empty(),"Timeout target has terrain")
 if not floor_hit.is_empty():
  var point:Vector3=floor_hit.position+Vector3.UP*0.03
  var inventory=game.player_hud.inventory;var slot:int=game.player_hud.active_slot
  var reply:Dictionary=game.lakes.bucket(point+Vector3.UP*2,point,true,inventory,slot,inventory.snapshot().revision)
  check(reply.pending,"Timeout case genuinely awaits uncached terrain")
  if reply.pending:
   game.lakes._pending_bucket.deadline=Time.get_ticks_msec()-1
   game.lakes._process(0.0)
   check(game.lakes._pending_bucket.is_empty() and held_ml()==1000000,"Expired action is retired without consuming the bucket")
   check(game._lake_notice=="Water action timed out; bucket unchanged. Try again.","HUD reports the terminal timeout instead of a permanent Preparing message")
 deadline=Time.get_ticks_msec()+6000
 while Time.get_ticks_msec()<deadline:
  await process_frame
  var state:Dictionary=game.lakes.statistics()
  if int(state.pending_regions)==0 and int(state.dirty_meshes)==0 and not game.lakes._busy and game.lakes._pending_dev.is_empty():break
 check(game.lakes.statistics().pending_regions==0,"Already requested terrain preparation finishes")
 check(held_ml()==1000000,"Canceled bucket pour retains all held water")
 check(amounts(game.lakes.capture_snapshot())==original,"Canceled edits never appear after terrain preparation completes")
 await finish()
func finish():
 var file:=FileAccess.open("res://reports/water_edit_cancellation.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures}));file.close()
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_EDIT_CANCELLATION failures=",failures);quit(failures)

# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func survey(water:RefCounted)->Dictionary:
 var cursor:=0;var revision:=-1;var amount:=0;var calls:=0;var peak:=0;var columns:=PackedVector3Array()
 while calls<20000:
  var reply:Dictionary=water.survey_columns(cursor,revision,4)
  if not reply.get("ok",false):return {}
  if reply.regions>4 or reply.columns.size()>256:return {}
  revision=reply.revision;cursor=reply.cursor;amount+=reply.water_ml;calls+=1;peak=maxi(peak,reply.worker_us);columns.append_array(reply.columns)
  if reply.complete:return {"amount":amount,"calls":calls,"peak_us":peak,"columns":columns,"revision":revision}
 return {}
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved world loads"):await done();return
 game.set_physics_process(false);game.lakes.set_process(false)
 var water:RefCounted=game.lakes.water
 var before:Dictionary=survey(water)
 if not check(not before.is_empty() and before.amount==water.statistics().water_ml and before.amount>0,"bounded survey covers all stored water amounts"):await done();return
 var first:Dictionary=water.survey_columns(0,-1,1)
 var point:Vector3=before.columns[0]
 var removed:int=water.remove_bounds(AABB(point-Vector3(1,1,1),Vector3(2,2,2)))
 check(removed>0,"real stored water removed")
 check(water.survey_columns(first.cursor,first.revision,1).get("stale",false),"mutation invalidates partially accumulated survey")
 var after:Dictionary=survey(water)
 check(not after.is_empty() and after.amount==before.amount-removed,"fresh survey accounts exactly for removal")
 var snapshot:PackedByteArray=game.lakes.capture_snapshot()
 var restored=ClassDB.instantiate("NativeRegionalWater")
 check(restored.restore_snapshot(snapshot),"water storage restores")
 var reopened:Dictionary=survey(restored)
 check(not reopened.is_empty() and reopened.amount==after.amount and reopened.columns==after.columns,"restored survey has identical occupied columns and amounts")
 check(not water.survey_columns(-1,-1,1).get("ok",false) and not water.survey_columns(0,-1,17).get("ok",false),"invalid survey budgets rejected")
 print("WATER_MAP_PROFILE regions_calls=",before.calls," columns=",before.columns.size()," max_call_us=",before.peak_us)
 await done()
func done()->void:
 print("WATER_MAP_SURVEY failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)

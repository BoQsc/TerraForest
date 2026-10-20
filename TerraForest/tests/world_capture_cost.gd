# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func materialize(state:Dictionary)->Dictionary:
 for key:String in state.sections:
  if state.sections[key] is RefCounted:state.sections[key]=state.sections[key].serialize_snapshot()
 return state
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"world ready"):await done();return
 game.set_physics_process(false);game._clear_motion()
 var results:Array=[]
 for i in 3:
  var state:Dictionary=game.persistence._capture()
  var measured:Dictionary=game.persistence.last_capture.duplicate(true)
  var worker:=Thread.new();var worker_begin:=Time.get_ticks_usec()
  check(worker.start(materialize.bind(state))==OK,"snapshot worker starts")
  while worker.is_alive():await process_frame
  state=worker.wait_to_finish()
  measured.worker_elapsed_us=Time.get_ticks_usec()-worker_begin
  var hashing:=HashingContext.new();hashing.start(HashingContext.HASH_SHA256);hashing.update(state.sections.volumetric_water)
  measured.water_sha256=hashing.finish().hex_encode()
  results.append(measured)
  if i>0:check(measured.total_us<5000,"unchanged capture stays below 5 ms")
  check(game.lakes.statistics().snapshot_cache_bytes<=64*1024*1024,"snapshot cache respects 64 MiB bound")
  check(not state.sections.is_empty(),"complete captured sections")
  for frame in 10:await process_frame
 # Exercise edited serialization on an independent store; preserve the source world.
 var original:PackedByteArray=game.lakes.capture_snapshot()
 var catalog:PackedByteArray=game.lakes.water.snapshot_catalog(original)
 var copy=ClassDB.instantiate("NativeRegionalWater")
 check(copy.restore_snapshot(original),"captured world restores")
 var frozen:Variant=copy.capture_storage_snapshot(catalog)
 check(frozen is RefCounted,"cold storage capture freezes native records")
 copy.remove_bounds(AABB(Vector3.ZERO,Vector3(2000,256,2000)))
 var frozen_thread:=Thread.new();check(frozen_thread.start(frozen.serialize_snapshot)==OK,"frozen snapshot serializes on worker")
 while frozen_thread.is_alive():await process_frame
 check(frozen_thread.wait_to_finish()==original,"later live mutations cannot alter queued snapshot")
 frozen=null
 check(copy.restore_snapshot(original),"restore source after queued snapshot test")
 check(copy.capture_snapshot(catalog)==original,"restored world is byte-identical")
 var builds:int=copy.statistics().snapshot_builds
 check(copy.capture_snapshot(catalog)==original and copy.statistics().snapshot_builds==builds and copy.statistics().snapshot_hits>0,"unchanged snapshot reuses immutable bytes")
 var caller_copy:PackedByteArray=copy.capture_snapshot(catalog)
 caller_copy[0]=0
 check(copy.capture_snapshot(catalog)==original,"caller mutation cannot corrupt cached snapshot")
 copy.invalidate(AABB(Vector3.ZERO,Vector3(2000,256,2000)),false)
 var invalidated:PackedByteArray=copy.capture_snapshot(catalog)
 check(invalidated!=original and copy.validate_snapshot(invalidated),"terrain invalidation changes cached occupancy")
 check(copy.restore_snapshot(original) and copy.capture_snapshot(catalog)==original,"restore invalidates older cached state")
 copy.invalidate_buildings(AABB(Vector3.ZERO,Vector3(2000,256,2000)))
 check(copy.capture_snapshot(catalog)!=original,"building invalidation changes cached occupancy")
 check(copy.restore_snapshot(original),"original occupancy restored")
 var other_catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var other:PackedByteArray=copy.capture_snapshot(other_catalog)
 check(other!=original and copy.snapshot_catalog(other)==other_catalog,"catalog identity invalidates cached archive")
 check(copy.capture_snapshot(catalog)==original,"original catalog recaptures exactly")
 var removed:int=copy.remove_bounds(AABB(Vector3.ZERO,Vector3(2000,256,2000)))
 check(removed>0,"fixture contains removable water")
 var edited:PackedByteArray=copy.capture_snapshot(catalog)
 check(edited!=original and copy.validate_snapshot(edited),"edited snapshot differs and validates")
 check(copy.restore_snapshot(edited) and copy.statistics().water_ml==0,"edited quantities survive restore")
 check(copy.capture_snapshot(catalog)==edited,"edited snapshot roundtrips exactly")
 check(not copy.restore_snapshot(edited.slice(0,edited.size()-1)),"truncation rejected")
 check(copy.capture_snapshot(catalog)==edited,"failed restore preserves live data")
 check(game.lakes.capture_snapshot()==original,"independent capture edits preserve original world")
 var held:Array=[];var exhausted:=false
 for i in 32:
  copy.invalidate(AABB(Vector3.ZERO,Vector3(2000,256,2000)),false)
  var payload:Variant=copy.capture_storage_snapshot(catalog)
  if payload is PackedByteArray:
   check(payload.is_empty(),"snapshot pressure fails closed")
   exhausted=true;break
  held.append(payload)
 check(exhausted and not held.is_empty(),"queued immutable snapshots have a finite bound")
 check(copy.statistics().snapshot_pending_bytes<=128*1024*1024,"queued snapshot reservation stays below 128 MiB")
 held.clear();copy.invalidate(AABB(Vector3.ZERO,Vector3(2000,256,2000)),false)
 check(copy.capture_storage_snapshot(catalog) is RefCounted,"snapshot capacity recovers after release")
 FileAccess.open("res://reports/world_capture_cost.json",FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
 await done()
func done()->void:
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
 print("WORLD_CAPTURE_COST failures=",failures);quit(1 if failures else 0)

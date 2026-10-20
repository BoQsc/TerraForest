# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"world ready"):await done();return
 game.set_physics_process(false);game._clear_motion()
 var results:Array=[]
 for i in 3:
  var state:Dictionary=game.persistence._capture()
  var measured:Dictionary=game.persistence.last_capture.duplicate(true)
  var hashing:=HashingContext.new();hashing.start(HashingContext.HASH_SHA256);hashing.update(state.sections.volumetric_water)
  measured.water_sha256=hashing.finish().hex_encode()
  results.append(measured)
  check(not state.sections.is_empty(),"complete captured sections")
  for frame in 10:await process_frame
 # Exercise edited serialization on an independent store; preserve the source world.
 var original:PackedByteArray=game.lakes.capture_snapshot()
 var catalog:PackedByteArray=game.lakes.water.snapshot_catalog(original)
 var copy=ClassDB.instantiate("NativeRegionalWater")
 check(copy.restore_snapshot(original),"captured world restores")
 check(copy.capture_snapshot(catalog)==original,"restored world is byte-identical")
 var removed:int=copy.remove_bounds(AABB(Vector3.ZERO,Vector3(2000,256,2000)))
 check(removed>0,"fixture contains removable water")
 var edited:PackedByteArray=copy.capture_snapshot(catalog)
 check(edited!=original and copy.validate_snapshot(edited),"edited snapshot differs and validates")
 check(copy.restore_snapshot(edited) and copy.statistics().water_ml==0,"edited quantities survive restore")
 check(copy.capture_snapshot(catalog)==edited,"edited snapshot roundtrips exactly")
 check(not copy.restore_snapshot(edited.slice(0,edited.size()-1)),"truncation rejected")
 check(copy.capture_snapshot(catalog)==edited,"failed restore preserves live data")
 check(game.lakes.capture_snapshot()==original,"independent capture edits preserve original world")
 FileAccess.open("res://reports/world_capture_cost.json",FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
 await done()
func done()->void:
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
 print("WORLD_CAPTURE_COST failures=",failures);quit(1 if failures else 0)

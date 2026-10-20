# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var factory=ClassDB.instantiate("NativeWaterMapIdentity")
 var water=ClassDB.instantiate("NativeRegionalWater")
 var catalog=ClassDB.instantiate("NativeLakeCatalog")
 var packet:PackedByteArray=water.capture_snapshot(catalog.encode([],1))
 var worker:=Thread.new();worker.start(factory.prepare.bind(packet))
 while worker.is_alive():await process_frame
 var prepared:RefCounted=worker.wait_to_finish()
 check(prepared!=null and prepared.get_bytes()==packet,"worker prepares exact immutable water packet")
 var copy:PackedByteArray=prepared.get_bytes();copy[0]^=1
 check(prepared.get_bytes()==packet,"caller mutation cannot change prepared bytes")
 check(water.restore_prepared(prepared) and water.statistics().map_identity_scene_hash_us==0,"prepared restore hashes no bytes on scene thread")
 check(prepared.get_catalog()==catalog.encode([],1),"prepared catalog matches validated packet")
 check(not water.restore_prepared(prepared),"prepared state cannot be consumed twice")
 var retire_worker:=Thread.new();retire_worker.start(prepared.retire)
 while retire_worker.is_alive():await process_frame
 retire_worker.wait_to_finish()
 check(not water.restore_prepared(prepared),"retired handoff cannot install discarded state")
 var identity:String=water.survey_cache_identity()
 check(not identity.is_empty() and water.restore_snapshot(packet) and water.survey_cache_identity()==identity,"prepared and ordinary restore certify identical content")
 var bad= factory.prepare(PackedByteArray([1,2,3]))
 check(not water.restore_prepared(bad) and water.survey_cache_identity()==identity,"invalid prepared payload cannot replace certified state")
 check(not water.restore_prepared(null),"missing prepared payload rejected")
 print("WATER_MAP_IDENTITY failures=",failures);quit(1 if failures else 0)

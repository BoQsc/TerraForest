# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 var data:PackedByteArray=FileAccess.get_file_as_bytes("res://docs/evidence/water_structure_replacement/cached_water.bin.gz").decompress_dynamic(16*1024*1024,FileAccess.COMPRESSION_GZIP)
 var water=ClassDB.instantiate("NativeRegionalWater")
 check(water.validate_snapshot(data) and water.restore_snapshot(data),"Actual-world building occupancy snapshot restores")
 check(water.statistics().sampled_nodes==0 and water.statistics().structure_contact_bytes>0,"Reload uses cached structures without terrain sampling")
 check(water.depth_at(Vector3(796.5,47.5,1292.5))==0,"Saved sphere interior stays dry")
 check(water.depth_at(Vector3(796.9,47.9,1292.9))>0,"Saved sphere empty corner retains water")
 var encoded:PackedByteArray=water.capture_snapshot(water.snapshot_catalog(data))
 check(encoded==data,"Cached world snapshot round-trips byte-exactly")
 var invalid:PackedByteArray=data.duplicate();invalid.append(0)
 check(not water.restore_snapshot(invalid) and water.capture_snapshot(water.snapshot_catalog(data))==data,"Invalid snapshot cannot partially replace state")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/water_structure_cache.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"failures":failures,"cached_structure_bytes":water.statistics().structure_contact_bytes}));file.close()
 print("WATER_STRUCTURE_CACHE failures=",failures);quit(failures)

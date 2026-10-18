# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 var scatter=ClassDB.instantiate("NativeVegetationScatter")
 var legacy:Dictionary=scatter.candidates(Vector2i(10,20),42,0.82)
 var empty:PackedByteArray=scatter.capture_storage_snapshot()
 var failures:=0
 if not scatter.configure_groves(PackedVector3Array([Vector3(1024,32,256)])):failures+=1
 var added:Dictionary=scatter.candidates(Vector2i(16,4),42,0.82)
 if added.ids.is_empty():failures+=1
 if scatter.candidates(Vector2i(10,20),42,0.82)!=legacy:failures+=1
 var saved:PackedByteArray=scatter.capture_storage_snapshot()
 var restored=ClassDB.instantiate("NativeVegetationScatter")
 if not restored.restore_storage_snapshot(saved) or restored.candidates(Vector2i(16,4),42,0.82)!=added:failures+=1
 for bad in [saved.slice(0,saved.size()-1),PackedByteArray([0]),PackedByteArray()]:
  if restored.validate_snapshot(bad) or restored.restore_storage_snapshot(bad) or restored.capture_storage_snapshot()!=saved:failures+=1
 if scatter.configure_groves(PackedVector3Array([Vector3(1024,INF,256)])) or scatter.capture_storage_snapshot()!=saved:failures+=1
 if scatter.configure_groves(PackedVector3Array([Vector3(1024,65,256)])):failures+=1
 var huge:=PackedVector3Array();huge.resize(33);huge.fill(Vector3(1024,16,256))
 if scatter.configure_groves(huge):failures+=1
 if not scatter.restore_storage_snapshot(empty) or not scatter.candidates(Vector2i(16,4),42,0.82).ids.is_empty():failures+=1
 print("VEGETATION_GROVES failures=",failures," added_candidates=",added.ids.size())
 quit(1 if failures else 0)

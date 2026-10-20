# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 var r=ClassDB.instantiate("NativeWaterMapRaster");var failures:=0
 if not r.offer(PackedVector3Array([Vector3(1,10,1),Vector3(1,20,1),Vector3(5,15,1)])) or r.count()!=2:failures+=1
 if r.batch(0)!=PackedVector3Array([Vector3(1,20,1),Vector3(5,15,1)]):failures+=1
 if not r.accept(0,PackedByteArray([1,0])) or r.pixels()[3]!=63:failures+=1
 if not r.accept(0,PackedByteArray([0,0])) or r.pixels()[3]!=0:failures+=1
 if r.accept(0,PackedByteArray([1])) or r.offer(PackedVector3Array([Vector3(NAN,2,2)])) or not r.batch(-1).is_empty():failures+=1
 var overflow:=PackedVector3Array();overflow.resize(257)
 if r.offer(overflow) or r.count()!=2:failures+=1
 print("WATER_MAP_RASTER failures=",failures);quit(1 if failures else 0)

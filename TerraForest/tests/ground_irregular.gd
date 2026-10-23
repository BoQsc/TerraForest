# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
 var scatter=ClassDB.instantiate("NativeGroundCover")
 var valid:=true
 var changed:=0
 var samples:=0
 for seed_value in [0,42,1703,2147483647]:
  for cell in [Vector2i.ZERO,Vector2i(30,30),Vector2i(31,30),Vector2i(62,62)]:
   var base:Dictionary=scatter.candidates(cell,seed_value)
   check(base==scatter.candidates(cell,seed_value,0,PackedVector3Array(),true),"base stones and stable identities preserved")
   for layer in range(1,16):
    var old:Dictionary=scatter.candidates(cell,seed_value,layer)
    var data:Dictionary=scatter.candidates(cell,seed_value,layer,PackedVector3Array(),true)
    valid=valid and data==scatter.candidates(cell,seed_value,layer,PackedVector3Array(),true) and data.ids.size()<=64
    for i in data.ids.size():
     var point:Vector3=data.points[i]
     valid=valid and point.is_finite() and floori(point.x/32)==cell.x and floori(point.z/32)==cell.y
     var previous:int=old.ids.find(data.ids[i])
     if previous>=0:
      changed+=int(point.distance_to(old.points[previous])>0.1)
      samples+=1
 check(valid,"irregular placement deterministic and confined to stable owner namespaces")
 check(changed>samples*0.9,"detail positions no longer follow previous layer lattice")
 var occupied:Dictionary={}
 for layer in range(1,16):
  var distribution:Dictionary=scatter.candidates(Vector2i(30,30),42,layer,PackedVector3Array(),true)
  for point:Vector3 in distribution.points:
   var pocket:=Vector2i(floori((point.x-960)/4),floori((point.z-960)/4))
   occupied[pocket]=int(occupied.get(pocket,0))+1
 var differing:=0
 for count:int in occupied.values():differing+=int(count!=15)
 check(differing>45,"four-metre pockets no longer all contain exactly fifteen detail plants")
 var data:Dictionary=scatter.candidates(Vector2i(30,30),42,3,PackedVector3Array(),true)
 var normals:=PackedVector3Array();normals.resize(data.ids.size());normals.fill(Vector3.UP)
 var placed:Dictionary=scatter.place(data.ids,data.points,normals)
 var nonuniform:=0
 for transform:Transform3D in placed.transforms:
  var scale:Vector3=transform.basis.get_scale()
  nonuniform+=int(absf(scale.x-scale.y)>0.01)
 check(nonuniform>40,"native placement provides varied silhouettes before validation")
 print("GROUND_IRREGULAR failures=",failures," samples=",samples)
 quit(1 if failures else 0)

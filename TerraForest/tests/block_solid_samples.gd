# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func hull_contains(hulls:Array,point:Vector3)->bool:
 for hull:PackedFloat64Array in hulls:
  var inside:=true
  for i in range(0,hull.size(),4):
   inside=inside and Vector3(hull[i],hull[i+1],hull[i+2]).dot(point)<=hull[i+3]+0.000001
  if inside:return true
 return false
func _initialize():
 GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
 var blocks=ClassDB.instantiate("NativeBlockWorld")
 var notifications:Array=[]
 blocks.cells_changed.connect(func(bounds:AABB):notifications.append(bounds))
 blocks.set_cells(PackedInt32Array([0,0,0,1]))
 check(not notifications.is_empty() and notifications.back()==AABB(Vector3.ZERO,Vector3.ONE),"One block notifies only its unit bounds")
 # Independent interior/exterior points distinguish real shapes from cell AABBs.
 var fixtures:Array=[
  [Vector3(.1,.9,.1),Vector3(1.1,.5,.5)],
  [Vector3(.5,.25,.5),Vector3(.5,.75,.5)],
  [Vector3(.5,.8,.9),Vector3(.5,.8,.1)],
  [Vector3(.5,.2,.8),Vector3(.5,.8,.2)],
  [Vector3(.5,.8,.5),Vector3(.1,.5,.5)],
  [Vector3(.5,.5,.5),Vector3(.9,.9,.9)],
  [Vector3(.5,.9,.5),Vector3(.95,.5,.95)]]
 for shape in range(1,8):
  for rotation in 4:
   check(blocks.set_cells(PackedInt32Array([0,0,0,shape+rotation*8])),"Authored shape accepted")
   var points:=PackedVector3Array()
   for original:Vector3 in fixtures[shape-1]:
    var point:=original
    for turn in rotation:point=Vector3(1-point.z,point.y,point.x)
    points.append(point)
   check(blocks.sample_solid(points)==PackedByteArray([1,0]),"Shape %d rotation %d preserves its empty space"%[shape,rotation])
   var hit:Dictionary=blocks.raycast_cells(points[0]+Vector3.UP*2,points[0]-Vector3.UP*2)
   check(not hit.is_empty() and blocks.sample_solid(PackedVector3Array([hit.position-Vector3.UP*0.001]))==PackedByteArray([1]),"Picking remains consistent with occupied shape")
   var exported:Dictionary=blocks.solid_hulls(AABB(Vector3.ZERO,Vector3.ONE))
   check(exported.ok and hull_contains(exported.hulls,points[0]) and not hull_contains(exported.hulls,points[1]),"Exported hull matches authored shape")
 blocks.set_cells(PackedInt32Array([0,0,0,1]))
 blocks.transform=Transform3D(Basis(Vector3.UP,.4).scaled(Vector3(2,3,4)),Vector3(10,20,30))
 check(blocks.sample_solid(PackedVector3Array([blocks.transform*Vector3(.5,.5,.5),blocks.transform*Vector3(1.5,.5,.5)]))==PackedByteArray([1,0]),"Transformed block samples use world coordinates")
 var transformed_bounds:AABB=blocks.transform*AABB(Vector3.ZERO,Vector3.ONE)
 var transformed:Dictionary=blocks.solid_hulls(transformed_bounds)
 check(transformed.ok and hull_contains(transformed.hulls,blocks.transform*Vector3(.5,.5,.5)) and not hull_contains(transformed.hulls,blocks.transform*Vector3(1.5,.5,.5)),"Hull export applies nonuniform world transform")
 check(not blocks.solid_hulls(AABB(Vector3.ZERO,Vector3(100,100,100))).ok,"Hull export rejects oversized batch")
 check(blocks.sample_solid(PackedVector3Array([Vector3(NAN,0,0)])).is_empty(),"Invalid batch fails without partial output")
 var excessive:=PackedVector3Array();excessive.resize(4097)
 check(blocks.sample_solid(excessive).is_empty(),"Sampling has a bounded batch size")
 blocks.transform=Transform3D.IDENTITY
 var packet:PackedByteArray=blocks.capture_region(Vector3i.ZERO)
 check(blocks.unload_region(packet),"Region unload succeeds")
 check(blocks.sample_solid(PackedVector3Array([Vector3(.5,.5,.5),Vector3(2,.5,.5),Vector3(64.5,.5,.5)]))==PackedByteArray([2,2,0]),"Unavailable region is distinct from empty space")
 var unavailable:Dictionary=blocks.solid_hulls(AABB(Vector3.ZERO,Vector3.ONE))
 check(not unavailable.ok and unavailable.unavailable,"Hull export never treats unloaded solids as air")
 blocks.free()
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/block_solid_samples.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"shape_rotations":28}));file.close()
 print("BLOCK_SOLID_SAMPLES failures=",failures);quit(failures)

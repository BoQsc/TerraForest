# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize():
 GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
 var blocks=ClassDB.instantiate("NativeBlockWorld")
 # Independent interior/exterior points distinguish real shapes from cell AABBs.
 var fixtures:Array=[
  [Vector3(.1,.9,.1),Vector3(1.1,.5,.5)],
  [Vector3(.5,.25,.5),Vector3(.5,.75,.5)],
  [Vector3(.5,.8,.9),Vector3(.5,.8,.1)],
  [Vector3(.5,.2,.8),Vector3(.5,.8,.2)],
  [Vector3(.5,.8,.5),Vector3(.1,.5,.5)],
  [Vector3(.5,.5,.5),Vector3(.9,.9,.9)]]
 for shape in range(1,7):
  for rotation in 4:
   check(blocks.set_cells(PackedInt32Array([0,0,0,shape+rotation*8])),"Authored shape accepted")
   var points:=PackedVector3Array()
   for original:Vector3 in fixtures[shape-1]:
    var point:=original
    for turn in rotation:point=Vector3(1-point.z,point.y,point.x)
    points.append(point)
   check(blocks.sample_solid(points)==PackedByteArray([1,0]),"Shape %d rotation %d preserves its empty space"%[shape,rotation])
 blocks.set_cells(PackedInt32Array([0,0,0,1]))
 blocks.transform=Transform3D(Basis(Vector3.UP,.4).scaled(Vector3(2,3,4)),Vector3(10,20,30))
 check(blocks.sample_solid(PackedVector3Array([blocks.transform*Vector3(.5,.5,.5),blocks.transform*Vector3(1.5,.5,.5)]))==PackedByteArray([1,0]),"Transformed block samples use world coordinates")
 check(blocks.sample_solid(PackedVector3Array([Vector3(NAN,0,0)])).is_empty(),"Invalid batch fails without partial output")
 var excessive:=PackedVector3Array();excessive.resize(4097)
 check(blocks.sample_solid(excessive).is_empty(),"Sampling has a bounded batch size")
 blocks.transform=Transform3D.IDENTITY
 var packet:PackedByteArray=blocks.capture_region(Vector3i.ZERO)
 check(blocks.unload_region(packet),"Region unload succeeds")
 check(blocks.sample_solid(PackedVector3Array([Vector3(.5,.5,.5),Vector3(2,.5,.5),Vector3(64.5,.5,.5)]))==PackedByteArray([2,2,0]),"Unavailable region is distinct from empty space")
 blocks.free()
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/block_solid_samples.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"shape_rotations":24}));file.close()
 print("BLOCK_SOLID_SAMPLES failures=",failures);quit(failures)

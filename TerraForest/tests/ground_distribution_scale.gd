# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
 GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
 var scatter=ClassDB.instantiate("NativeGroundCover")
 var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256)
 var valid:=true
 for seed in [0,42,1703,2147483647]:
  for owner in [Vector2i.ZERO,Vector2i(62,62),Vector2i(30,30),Vector2i(0,62),Vector2i(62,0)]:
   var anchors:=PackedVector3Array()
   for z in 12:
    for x in 12:anchors.append(Vector3(owner.x*32-5+x*4,0,owner.y*32-5+z*4))
   for layer in 16:
    var data:Dictionary=scatter.candidates(owner,seed,layer,anchors)
    digest.update(var_to_bytes(data))
    valid=valid and data==scatter.candidates(owner,seed,layer,anchors)
    for point:Vector3 in data.points:
     valid=valid and point.is_finite() and point.x>=owner.x*32 and point.x<(owner.x+1)*32 and point.z>=owner.y*32 and point.z<(owner.y+1)*32
     valid=valid and point.x>=2 and point.z>=2 and point.x<1998 and point.z<1998
 var position_hash:=digest.finish().hex_encode()
 print("POSITION_SHA256 ",position_hash)
 check(position_hash=="ad79424d62afe690c4b8321c73c36a5121a55b7ccb8bf522ce8ac65fc22c3e6a","placement matches captured pre-optimization output")
 check(valid,"all seeds, corner owners and maximum anchors preserve deterministic world bounds")
 var clean:=PackedVector3Array([Vector3(970,0,970),Vector3(980,0,980)])
 var dirty:=PackedVector3Array([Vector3(NAN,0,0),clean[0],Vector3(0,INF,0),clean[1]])
 check(scatter.candidates(Vector2i(30,30),42,4,clean)==scatter.candidates(Vector2i(30,30),42,4,dirty),"invalid anchors remain ignored without changing nearest-anchor order")
 for anchor_count in [0,36,144]:
  var times:Array=[];var count:=0
  for repeat in 3:
   for z in range(26,35):
    for x in range(26,35):
     var anchors:=PackedVector3Array()
     for a in anchor_count:anchors.append(Vector3(x*32-5+(a%12)*4,0,z*32-5+(a/12)*4))
     var start:=Time.get_ticks_usec()
     for layer in 16:
      var data:Dictionary=scatter.candidates(Vector2i(x,z),42,layer,anchors)
      count+=data.ids.size()
     times.append((Time.get_ticks_usec()-start)/1000.0)
  times.sort()
  check(count==3*81*1024,"candidate count remains bounded at anchor count %d"%anchor_count)
  print("SCATTER_COST anchors=",anchor_count," owner_median_ms=",times[times.size()/2]," owner_p95_ms=",times[int(times.size()*.95)]," owner_max_ms=",times.back())
 print("DISTRIBUTION_SCALE failures=",failures);quit(1 if failures else 0)

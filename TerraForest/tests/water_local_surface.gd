# SPDX-License-Identifier: 0BSD
extends SceneTree
# Replay receipt-owned first-response data captured from normal gameplay.
func _initialize()->void:
 var path:=""
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--water-local-regions="):path=arg.trim_prefix("--water-local-regions=")
 if path.is_empty():push_error("A local gameplay capture is required");quit(1);return
 var data:Dictionary=FileAccess.open(path,FileAccess.READ).get_var()
 var water=ClassDB.instantiate("NativeRegionalWater")
 var failures:=0
 if not water.restore_snapshot(data.snapshot):failures+=1
 for step in 1000:
  var packet:Dictionary=water.next_mesh_batch(false)
  if packet.is_empty():break
  if packet.get("complete",false):water.commit_mesh_batch(packet.batch)
  if packet.has("failure"):print(packet.failure);failures+=1;break
 var point:Vector3=data.point
 var tested:=0;var discontinuities:=0
 for offset in range(1,15):
  var z:=floorf(point.z*2)*.5+offset*.5
  var a:=Vector3(point.x,point.y+2,z-.0002);var b:=Vector3(point.x,point.y+2,z+.0002)
  var left:Dictionary=water.raycast_surface(a,a-Vector3.UP*5)
  var right:Dictionary=water.raycast_surface(b,b-Vector3.UP*5)
  if left.get("hit",false) and right.get("hit",false):
   tested+=1
   if absf(left.point.y-right.point.y)>.001:discontinuities+=1
 if tested<10 or discontinuities:failures+=1
 print("LOCAL_LAYER_SEAMS tested=",tested," discontinuities=",discontinuities)
 for axis:Vector3 in [Vector3.RIGHT,Vector3.BACK]:
  var samples:Array=[]
  for offset in range(-24,25):
   var from:=point+axis*offset*.5+Vector3.UP*2
   var hit:Dictionary=water.raycast_surface(from,from-Vector3.UP*5)
   if hit.get("hit",false):
    var probe:Vector3=hit.point-Vector3.UP*.001
    samples.append([offset*.5,hit.point.y,str(hit.normal),water.depth_at(probe)])
   else:samples.append([offset*.5,null])
  print("LOCAL_SURFACE axis=",axis," ",JSON.stringify(samples))
 print("WATER_LOCAL_SURFACE failures=",failures);quit(failures)

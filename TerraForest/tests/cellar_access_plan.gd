# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 var failures:=0
 for seed_value in [0,1,42,50,141,1703,9999]:
  var site:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,13).sites[1].position
  var catalog=preload("res://addons/structures/cellar_catalog.gd")
  var asset:Resource=catalog.cottage()
  var plan:Dictionary=preload("res://addons/structures/site_plan.gd").prepare(asset,Vector3i(site+Vector3(20,0,20)),0,int(site.y))
  plan=catalog.connect_access(plan,site)
  var ok:bool=plan.ok and plan.street_lines.size()==6 and plan.street_lines[0]==site+Vector3(28,0,0)
  # Every path sample must start on the naturally flat owner site, avoiding
  # arbitrary cuts/fills that could conceal poorly fitted approaches.
  var core=ClassDB.instantiate("TerrainCore")
  var codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
  core.execute(codec.command(6,[seed_value,13]))
  for i in range(0,plan.street_lines.size(),2):
   var a:Vector3=plan.street_lines[i];var b:Vector3=plan.street_lines[i+1]
   ok=ok and a.y==site.y and b.y==site.y and plan.bounds.has_point(a) and plan.bounds.has_point(b)
   if i>0:ok=ok and a==plan.street_lines[i-1]
   var across:Vector3=(b-a).normalized().cross(Vector3.UP)*0.75
   for step in range(ceili(a.distance_to(b))+1):
    for side in [-1,0,1]:
     var point:Vector3=a.lerp(b,float(step)/maxi(1,ceili(a.distance_to(b))))+across*side
     var request:PackedByteArray=codec.point_command(point)
     var reply:PackedByteArray=core.execute(request)
     ok=ok and codec.reply_ok(reply) and absf(reply.decode_float(12)-site.y)<0.05

  var anchors=ClassDB.instantiate("NativeRoadAnchors")
  for i in range(0,plan.street_lines.size(),2):
   var stored:PackedByteArray=anchors.encode(plan.street_lines.slice(i,i+2),plan.street_width)
   ok=ok and not stored.is_empty() and anchors.decode(stored).get("ok",false)
  if not ok:failures+=1
  print("PASS " if ok else "FAIL ","cellar connected plan seed=",seed_value)
 var storage=ClassDB.instantiate("NativeRoadAnchors")
 var ends:=PackedVector3Array([Vector3(100,40,100),Vector3(101,40,100)])
 for width in [1.0,1.5,4.0,64.0]:
  var blob:PackedByteArray=storage.encode(ends,width)
  if blob.is_empty() or not storage.validate_snapshot(blob):failures+=1
 for width in [0.99,64.01,NAN,INF]:
  if not storage.encode(ends,width).is_empty():failures+=1
 print("CELLAR_ACCESS_PLAN failures=",failures);quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends SceneTree
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
const Routes=preload("res://addons/structures/regional_route_planner.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[42,17]))
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(42,16)
 var town:Dictionary=Planner.locate(core,layout.sites[3].position)
 if not town.ok:print("TOWN_FAILED");quit(1);return
 var result:Dictionary=Routes.central_connection(core,town,layout)
 print("REGIONAL_ROUTE ",result.get("reason","")," points=",result.get("points",[]).size()," nodes=",result.get("nodes",0)," attempts=",result.get("attempts",0))
 if result.ok:
  var revision:=0
  for segment:Dictionary in result.segments:
   var packet:=Codec.graded_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,segment.material)
   packet.resize(48);packet.encode_float(44,segment.shoulder)
   var reply:PackedByteArray=core.execute(packet)
   if not Codec.reply_ok(reply):print("ROUTE_EDIT_FAILED");quit(1);return
   revision=reply.decode_u32(12)
  var probes:=PackedVector3Array()
  for i in range(1,result.points.size()):
   var a:Vector3=result.points[i-1];var b:Vector3=result.points[i]
   var span:Vector3=b-a;var across:=Vector3(-span.z,0,span.x).normalized()
   var count:int=ceili(span.length()/2)
   for j in count+1:
    for side in [-2.5,0,2.5]:
     var p:Vector3=a.lerp(b,float(j)/count)+across*side
     probes.append(p-Vector3.UP*0.5);probes.append(p+Vector3.UP*0.5)
  var mismatches:=0
  for offset in range(0,probes.size(),512):
   var batch:PackedVector3Array=probes.slice(offset,mini(probes.size(),offset+512))
   var query:=Codec.command(31,[revision,batch.size()]);query.append_array(batch.to_byte_array())
   var reply:PackedByteArray=core.execute(query)
   if not Codec.reply_ok(reply):quit(1);return
   for i in batch.size():
    var d:float=reply.decode_float(20+i*4)
    if ((offset+i)%2==0 and d>=0) or ((offset+i)%2==1 and d<=0):mismatches+=1
  print("ROUTE_SURFACE probes=",probes.size()," mismatches=",mismatches)
  if mismatches>0:quit(1);return
  var file=FileAccess.open("res://reports/regional_route.json",FileAccess.WRITE)
  var points:Array=[]
  for p:Vector3 in result.points:points.append([p.x,p.y,p.z])
  file.store_string(JSON.stringify({"start":str(result.points[0]),"finish":str(result.points[-1]),"points":points},"  "))
 print("REGIONAL_ROUTE failures=",0 if result.ok else 1)
 quit(0 if result.ok else 1)

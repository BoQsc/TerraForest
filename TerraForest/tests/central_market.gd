# SPDX-License-Identifier: 0BSD
extends SceneTree
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[42,17]))
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(42,16)
 var north:Dictionary=Planner.locate(core,layout.sites[3].position)
 var plan:Dictionary=preload("res://addons/structures/central_market.gd").locate(core,layout.sites[0].position,Planner.earthworks(north).bounds)
 if not plan.ok:print("MARKET_FAILED ",plan);quit(1);return
 var route:Dictionary=preload("res://addons/structures/regional_route_planner.gd").central_connection(core,north,layout,plan)
 if not route.ok:print("MARKET_ROUTE_FAILED ",route);quit(1);return
 var revision:=0
 var works:Array=route.segments+Planner.earthworks(north).segments+Planner.earthworks(plan).segments
 for segment:Dictionary in works:
  var packet:=Codec.graded_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,segment.material)
  packet.resize(48);packet.encode_float(44,segment.shoulder)
  if segment.has("coefficients"):
   packet.resize(56);packet.encode_u32(48,segment.coefficients.size()/4);packet.encode_u32(52,segment.curve_index)
   for value:float in segment.coefficients:
    var offset:int=packet.size();packet.resize(offset+4);packet.encode_float(offset,value)
  var reply:PackedByteArray=core.execute(packet)
  if not Codec.reply_ok(reply):print("MARKET_EDIT_FAILED");quit(1);return
  revision=reply.decode_u32(12)
 var points:=PackedVector3Array()
 for site:Dictionary in [north,plan]:
  for lot:Dictionary in site.lots:points.append_array(lot.asset.foundation_samples(lot.origin,lot.rotation,0))
 var unsupported:=0
 for start in range(0,points.size(),512):
  var batch:PackedVector3Array=points.slice(start,mini(points.size(),start+512))
  var query:=Codec.command(30,[revision,batch.size(),8]);query.append_array(batch.to_byte_array())
  var reply:PackedByteArray=core.execute(query)
  if not Codec.reply_ok(reply):quit(1);return
  for i in batch.size():
   if reply.decode_float(20+i*4)>=0:unsupported+=1
 var cellars:=0
 for lot:Dictionary in plan.lots:
  if not lot.asset.get_meta("cellar_clearance",false):continue
  cellars+=1
  if lot.origin.y+5!=int(lot.survey.grade) or absf(lot.entrance.segment.start.y-lot.survey.grade)>0.001:
   print("CELLAR_GRADE_FAILED");quit(1);return
  var interior:=PackedVector3Array()
  for x in [-1,0,1]:
   for y in [2,3,4,5]:
    for z in [-2,0,2]:interior.append(Vector3(lot.origin)+Vector3(x+0.5,y,z+0.5))
  var probe:=Codec.command(31,[revision,interior.size()]);probe.append_array(interior.to_byte_array())
  var result:PackedByteArray=core.execute(probe)
  if not Codec.reply_ok(result):quit(1);return
  for i in interior.size():
   if result.decode_float(20+i*4)<=0:print("CELLAR_NOT_EXCAVATED ",interior[i]);quit(1);return
 if cellars!=1:print("CELLAR_COUNT_FAILED ",cellars);quit(1);return
 print("PASS one connected cellar with excavated interior and surface-level approach")
 var surfaces:=PackedVector3Array()
 var roads:Array=north.roads+plan.roads
 for i in range(1,route.points.size()):roads.append({"start":route.points[i-1],"finish":route.points[i],"linear":true})
 for road:Dictionary in roads:
  var span:Vector3=road.finish-road.start;var across:=Vector3(-span.z,0,span.x).normalized()
  var count:int=maxi(1,ceili(Vector2(span.x,span.z).length()/2))
  for i in count+1:
   var t:float=float(i)/count
   for side in [-2,0,2]:
    var p:Vector3=road.start.lerp(road.finish,t)+across*side
    if not road.get("linear",false):p.y=lerpf(road.start.y,road.finish.y,smoothstep(0,1,t))
    surfaces.append(p-Vector3.UP*0.5);surfaces.append(p+Vector3.UP*0.5)
 var surface_failures:=0
 for start in range(0,surfaces.size(),512):
  var batch:PackedVector3Array=surfaces.slice(start,mini(surfaces.size(),start+512))
  var query:=Codec.command(31,[revision,batch.size()]);query.append_array(batch.to_byte_array())
  var reply:PackedByteArray=core.execute(query)
  if not Codec.reply_ok(reply):quit(1);return
  for i in batch.size():
   var d:float=reply.decode_float(20+i*4)
   if ((start+i)%2==0 and d>=0) or ((start+i)%2==1 and d<=0):surface_failures+=1
 print("MARKET_ROADS probes=",surfaces.size()," mismatches=",surface_failures)
 if surface_failures>0:quit(1);return
 print("MARKET_COMBINED edits=",works.size()," support_points=",points.size()," unsupported=",unsupported," route_points=",route.points.size())
 if unsupported>0:quit(1);return
 print("CENTRAL_MARKET ",plan.get("reason","")," lots=",plan.get("lots",[]).size()," center=",plan.get("center",Vector3.ZERO))
 print("CENTRAL_MARKET failures=",0 if plan.ok else 1);quit(0 if plan.ok else 1)

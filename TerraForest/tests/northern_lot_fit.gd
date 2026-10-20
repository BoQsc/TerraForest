# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Lots=preload("res://addons/structures/northern_lots.gd")
func _initialize()->void:
 var failures:=0
 var generator:int=16 if "--sited" in OS.get_cmdline_user_args() else 15 if "--routed" in OS.get_cmdline_user_args() else 14 if "--natural" in OS.get_cmdline_user_args() else 13
 for seed_value in [0,1,42,50,141,1703,9999]:
  var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,generator)
  var center:Vector3=layout.sites[3].position
  var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,generator]))
  var lots:Array=Lots.recipe(center);var surveys:Array=[]
  for lot:Dictionary in lots:
   var points:PackedVector3Array=lot.asset.foundation_samples(lot.origin,lot.rotation,0)
   var low:=INF;var high:=-INF
   for offset in range(0,points.size(),64):
    var batch:PackedVector3Array=points.slice(offset,mini(offset+64,points.size()))
    var packet:=Codec.command(17,[batch.size()]);packet.append_array(batch.to_byte_array())
    var reply:PackedByteArray=core.execute(packet)
    if not Codec.reply_ok(reply):failures+=1;continue
    for i in batch.size():
     var height:float=reply.decode_float(20+i*12)
     low=minf(low,height);high=maxf(high,height)
   surveys.append({"ok":is_finite(low) and is_finite(high),"min_height":low,"max_height":high})
  var roads:Array=Lots.street_segments(center)
  for road:Dictionary in roads:
   for endpoint:Vector3 in [road.start,road.finish]:
    var connected:=false
    for other:Dictionary in roads:
     if other==road:continue
     var span:Vector3=other.finish-other.start
     var near:Vector3=other.start+span*clampf((endpoint-other.start).dot(span)/span.length_squared(),0,1)
     connected=connected or near.distance_to(endpoint)<0.01
    if not connected:print("LOOP_DANGLING_END ",endpoint);failures+=1
   for lot:Dictionary in lots:
    for point:Vector3 in lot.asset.foundation_samples(lot.origin,lot.rotation,0):
     point.y=center.y
     var span:Vector3=road.finish-road.start
     var near:Vector3=road.start+span*clampf((point-road.start).dot(span)/span.length_squared(),0,1)
     if near.distance_to(point)<road.half_width+0.5:print("LOOP_BUILDING_OVERLAP ",point);failures+=1;break
  var road_points:PackedVector3Array=Lots.street_probe(center).foundation_samples(Vector3i(center),0,0)
  var road_low:=INF;var road_high:=-INF
  for offset in range(0,road_points.size(),64):
   var batch:PackedVector3Array=road_points.slice(offset,mini(offset+64,road_points.size()))
   var query:=Codec.command(17,[batch.size()]);query.append_array(batch.to_byte_array())
   var reply:PackedByteArray=core.execute(query)
   if not Codec.reply_ok(reply):failures+=1;continue
   for i in batch.size():
    road_low=minf(road_low,reply.decode_float(20+i*12));road_high=maxf(road_high,reply.decode_float(20+i*12))
  var road_quality:Dictionary=preload("res://addons/world_runtime/world_building_quality.gd").site({"ok":is_finite(road_low) and is_finite(road_high),"min_height":road_low,"max_height":road_high,"grade":center.y},"Loop roads")
  print("LOOP_ROAD_FIT seed=",seed_value," quality=",road_quality)
  if road_quality.status!="pass":failures+=1
  var plan:Dictionary=Lots.assemble(lots,center,surveys)
  if not plan.ok:print("LOT_FIT_REJECT seed=",seed_value," detail=",plan);failures+=1;continue
  var paving:PackedInt32Array=plan.sidewalk_asset.get_records()
  for i in range(0,paving.size(),4):
   var point:Vector3=Vector3(plan.sidewalk_origin)+Vector3(paving[i]+0.5,1,paving[i+2]+0.5)
   for road:Dictionary in roads:
    var span:Vector3=road.finish-road.start
    var near:Vector3=road.start+span*clampf((point-road.start).dot(span)/span.length_squared(),0,1)
    if point.distance_to(near)<road.half_width:print("SIDEWALK_ROAD_OVERLAP ",point);failures+=1
  if seed_value==42:
   var revision:=0
   for segment:Dictionary in plan.segments:
    var edit:=Codec.graded_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,segment.material)
    edit.resize(48);edit.encode_float(44,segment.shoulder)
    var result:PackedByteArray=core.execute(edit)
    if not Codec.reply_ok(result):print("LOT_NATIVE_EDIT_REJECT ",segment);failures+=1
    else:revision=result.decode_u32(12)
   var supports:=PackedVector3Array()
   for lot:Dictionary in plan.lots:supports.append_array(lot.asset.foundation_samples(lot.origin,lot.rotation,0))
   supports.append_array(plan.sidewalk_asset.foundation_samples(plan.sidewalk_origin,0,0))
   supports.append_array(plan.common.asset.foundation_samples(plan.common.origin,0,0))
   var unsupported:=0
   for offset in range(0,supports.size(),512):
    var batch:PackedVector3Array=supports.slice(offset,mini(offset+512,supports.size()))
    var query:=Codec.command(30,[revision,batch.size(),8]);query.append_array(batch.to_byte_array())
    var reply:PackedByteArray=core.execute(query)
    if not Codec.reply_ok(reply):failures+=1;continue
    for i in batch.size():
     if reply.decode_float(20+i*4)>=0:unsupported+=1;print("UNSUPPORTED_LOT_POINT ",batch[i])
   print("LOT_NATIVE_SUPPORT samples=",supports.size()," unsupported=",unsupported)
   if unsupported>0:failures+=1
  var maximum_fill:=0.0;var maximum_cut:=0.0
  for quality:Dictionary in plan.qualities:
   maximum_fill=maxf(maximum_fill,quality.max_fill);maximum_cut=maxf(maximum_cut,quality.max_cut)
  print("LOT_FIT seed=",seed_value," max_fill=",maximum_fill," max_cut=",maximum_cut," segments=",plan.segments.size()," qualities=",plan.qualities)
 print("NORTHERN_LOT_FIT failures=",failures);quit(1 if failures else 0)

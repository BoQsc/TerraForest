# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
func _initialize()->void:
 var failures:=0
 var core=ClassDB.instantiate("TerrainCore")
 if not Codec.reply_ok(core.execute(Codec.command(6,[42,17]))):print("RAW_PROFILE_REJECTED");quit(1);return
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(42,16)
 var plan:Dictionary=Planner.locate(core,layout.sites[3].position)
 if not plan.ok:print("PLAN_REJECTED ",plan);quit(1);return
 var edits:Dictionary=Planner.earthworks(plan)
 if not edits.ok:print("EARTHWORKS_REJECTED ",edits);quit(1);return
 var revision:=0
 for segment:Dictionary in edits.segments:
  var packet:=Codec.graded_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,segment.material)
  packet.resize(48);packet.encode_float(44,segment.shoulder)
  if segment.has("coefficients"):
   packet.resize(56);packet.encode_u32(48,segment.coefficients.size()/4);packet.encode_u32(52,segment.curve_index)
   for value:float in segment.coefficients:
    var offset:int=packet.size();packet.resize(offset+4);packet.encode_float(offset,value)
  var reply:PackedByteArray=core.execute(packet)
  if not Codec.reply_ok(reply):failures+=1;print("NATIVE_EDIT_REJECT ",segment);continue
  revision=reply.decode_u32(12)
 var supports:=PackedVector3Array()
 for lot:Dictionary in plan.lots:supports.append_array(lot.asset.foundation_samples(lot.origin,lot.rotation,0))
 var unsupported:=0
 for start in range(0,supports.size(),512):
  var batch:PackedVector3Array=supports.slice(start,mini(start+512,supports.size()))
  var packet:=Codec.command(30,[revision,batch.size(),8]);packet.append_array(batch.to_byte_array())
  var reply:PackedByteArray=core.execute(packet)
  if not Codec.reply_ok(reply):failures+=1;continue
  for i in batch.size():
   if reply.decode_float(20+i*4)>=0:
    if unsupported<8:print("UNSUPPORTED ",batch[i])
    unsupported+=1
 failures+=unsupported
 var probes:=PackedVector3Array()
 for road:Dictionary in plan.roads:
  var span:Vector3=road.finish-road.start
  var across:=Vector3(-span.z,0,span.x).normalized()
  for step in 9:
   for side in [-3,0,3]:
    var p:Vector3=road.start.lerp(road.finish,step/8.0)+across*side
    p.y=lerpf(road.start.y,road.finish.y,smoothstep(0.0,1.0,step/8.0))
    probes.append(p-Vector3.UP*0.5);probes.append(p+Vector3.UP*0.5)
 var misplaced:=0
 for start in range(0,probes.size(),512):
  var batch:PackedVector3Array=probes.slice(start,mini(start+512,probes.size()))
  var packet:=Codec.command(31,[revision,batch.size()]);packet.append_array(batch.to_byte_array())
  var reply:PackedByteArray=core.execute(packet)
  if not Codec.reply_ok(reply):failures+=1;continue
  for i in batch.size():
   var value:float=reply.decode_float(20+i*4)
   if ((start+i)%2==0 and value>=0) or ((start+i)%2==1 and value<=0):
    if misplaced<8:print("ROAD_SURFACE_MISMATCH ",batch[i]," density=",value)
    misplaced+=1
 failures+=misplaced
 var saved:PackedByteArray=core.execute(Codec.command(4)).slice(12)
 var clone=ClassDB.instantiate("TerrainCore");var load_packet:=Codec.command(5);load_packet.append_array(saved)
 if not Codec.reply_ok(clone.execute(load_packet)) or clone.execute(Codec.command(4)).slice(12)!=saved:failures+=1
 print("TERRAIN_LOT_EARTHWORKS segments=",edits.segments.size()," support_samples=",supports.size()," unsupported=",unsupported," road_mismatches=",misplaced," save_bytes=",saved.size()," failures=",failures)
 quit(1 if failures else 0)

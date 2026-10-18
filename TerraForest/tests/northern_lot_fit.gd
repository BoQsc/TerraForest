# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Lots=preload("res://addons/structures/northern_lots.gd")
func _initialize()->void:
 var failures:=0
 for seed_value in [0,1,42,50,141,1703,9999]:
  var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,13)
  var center:Vector3=layout.sites[3].position
  var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,13]))
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
  var plan:Dictionary=Lots.assemble(lots,center,surveys)
  if not plan.ok:print("LOT_FIT_REJECT seed=",seed_value," detail=",plan);failures+=1;continue
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

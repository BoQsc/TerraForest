# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:
 var failures:=0;var violations:=0;var summaries:Array=[]
 for seed_value in [0,1,42,50,141,1703,9999]:
  var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,16]))
  var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,16)
  for index in layout.sites.size():
   var site:Dictionary=layout.sites[index];var points:=PackedVector3Array()
   var extent:int=ceili(site.radius)
   for x in range(-extent,extent+1,4):
    for z in range(-extent,extent+1,4):
     if Vector2(x,z).length()<=site.radius:points.append(site.position+Vector3(x,0,z))
   var max_fill:=0.0;var max_cut:=0.0;var low:=INF;var high:=-INF
   for start in range(0,points.size(),256):
    var batch:PackedVector3Array=points.slice(start,mini(start+256,points.size()))
    var query:=Codec.command(37,[batch.size()]);query.append_array(batch.to_byte_array())
    var reply:PackedByteArray=core.execute(query)
    if not Codec.reply_ok(reply) or reply.size()!=12+batch.size()*8:failures+=1;continue
    for i in batch.size():
     var raw:float=reply.decode_float(12+i*8);var developed:float=reply.decode_float(16+i*8)
     low=minf(low,raw);high=maxf(high,raw)
     max_fill=maxf(max_fill,developed-raw);max_cut=maxf(max_cut,raw-developed)
    # Survey must neither mutate the world nor differ from the actual surface.
    var height_query:=Codec.command(7);height_query.append_array(PackedVector3Array([batch[0]]).to_byte_array())
    var actual:PackedByteArray=core.execute(height_query)
    if actual.decode_float(12)!=reply.decode_float(16):failures+=1
   var accepted:bool=max_fill<=2 and max_cut<=3
   if not accepted:violations+=1
   var summary:Dictionary={"seed":seed_value,"site":index,"samples":points.size(),"fill":max_fill,"cut":max_cut,"raw_relief":high-low,"quality_accepted":accepted}
   summaries.append(summary);print("EARTHWORKS ",JSON.stringify(summary))
  for bad in [Codec.command(37,[0]),Codec.command(37,[257]),Codec.command(37,[1])]:
   if Codec.reply_ok(core.execute(bad)):failures+=1
 var file:=FileAccess.open("res://reports/regional_earthworks.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"sites":summaries,"quality_violations":violations,"protocol_failures":failures}, "  "))
 print("REGIONAL_EARTHWORKS quality_violations=",violations," protocol_failures=",failures)
 # A successful audit reports the current rejection honestly; it is not a quality pass.
 quit(1 if failures or (violations and "--enforce-quality" in OS.get_cmdline_user_args()) else 0)

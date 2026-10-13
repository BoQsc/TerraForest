# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func _initialize():call_deferred("run")
func run():
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var solid=ClassDB.instantiate("TerrainCore");solid.execute(Codec.command(6,[1703,Codec.MATERIAL_FIELD_GENERATOR]))
 var revision:int=solid.execute(Codec.command(0)).decode_u32(12)
 var rows:Array=[]
 for edge:float in [1.0,2.0,4.0]:
  for offset:float in [0.0,0.5]:
   var field=ClassDB.instantiate("TerrainCore");field.execute(Codec.command(6,[1703,Codec.MATERIAL_FIELD_GENERATOR]))
   var low:=Vector3(24,12,24)+Vector3.ONE*offset
   var receipt:Dictionary=field.material_box(solid,low,low+Vector3.ONE*edge,true,revision)
   var reply:PackedByteArray=field.execute(Codec.command(1,[16,16,16,1]))
   var vertices:int=reply.decode_u32(40);var indices:int=reply.decode_u32(44)
   var points:PackedVector3Array=Codec._packed_channel(reply,52,vertices,12,TYPE_PACKED_VECTOR3_ARRAY)
   var ids:PackedInt32Array=Codec._packed_channel(reply,52+vertices*56,indices,4,TYPE_PACKED_INT32_ARRAY)
   var volume:=0.0
   var edges:Dictionary={}
   for i in range(0,ids.size(),3):
    var a:=points[ids[i]]-low;var b:=points[ids[i+1]]-low;var c:=points[ids[i+2]]-low
    volume+=a.dot(b.cross(c))/6.0
    for j in 3:
     var ka:=str(points[ids[i+j]]);var kb:=str(points[ids[i+(j+1)%3]])
     var key:String=ka+"/"+kb if ka<kb else kb+"/"+ka
     edges[key]=edges.get(key,0)+1
   volume=abs(volume)
   var closed:=indices>0
   for count:int in edges.values():closed=closed and count==2
   var expected:=edge*edge*edge
   var ok:bool=receipt.accepted and closed and abs(volume-expected)<=expected*0.01
   if not ok:failures+=1
   var row:Dictionary={"edge_m":edge,"offset_m":offset,"expected_m3":expected,"rendered_m3":volume,"closed":closed,"triangles":indices/3,"passed":ok}
   rows.append(row);print("PASS " if ok else "FAIL ",JSON.stringify(row))
 DirAccess.make_dir_recursive_absolute("res://reports")
 var f:=FileAccess.open("res://reports/terrain_material_volume.json",FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failures,"cases":rows},"  "));f.close()
 print("TERRAIN_MATERIAL_VOLUME failures=",failures);quit(failures)

# SPDX-License-Identifier: 0BSD
extends RefCounted
# One-time generation metadata. The native terrain field owns layout and grading.
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
static func describe(seed_value:int)->Dictionary:
 if seed_value<0 or seed_value>2147483647:return {}
 if not ClassDB.class_exists("TerrainCore"):GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var core=ClassDB.instantiate("TerrainCore")
 if not Codec.reply_ok(core.execute(Codec.command(6,[seed_value,7]))):return {}
 var data:PackedByteArray=core.execute(Codec.command(34))
 if not Codec.reply_ok(data) or data.size()!=168 or data.decode_u32(12)!=5 or data.decode_u32(116)!=4:return {}
 var sites:Array[Dictionary]=[];var roads:Array[Dictionary]=[]
 for i in 5:
  var at:=16+i*20
  sites.append({"id":i,"position":Vector3(data.decode_float(at),data.decode_float(at+4),data.decode_float(at+8)),"radius":data.decode_float(at+12),"kind":"city" if data.decode_u32(at+16)==1 else "town"})
 for i in 4:
  var at:=120+i*12
  roads.append({"from":data.decode_u32(at),"to":data.decode_u32(at+4),"half_width":data.decode_float(at+8)})
 return {"version":1,"generator":7,"seed":seed_value,"sites":sites,"roads":roads}

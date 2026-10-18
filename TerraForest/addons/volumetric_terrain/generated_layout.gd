# SPDX-License-Identifier: 0BSD
extends RefCounted
# One-time generation metadata. The native terrain field owns layout and grading.
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
static func describe(seed_value:int,generator:int=7)->Dictionary:
 if generator not in [7,8,9,10,11] or seed_value<0 or seed_value>2147483647:return {}
 if not ClassDB.class_exists("TerrainCore"):GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var core=ClassDB.instantiate("TerrainCore")
 if not Codec.reply_ok(core.execute(Codec.command(6,[seed_value,generator]))):return {}
 var data:PackedByteArray=core.execute(Codec.command(34))
 if not Codec.reply_ok(data) or data.size()!=168 or data.decode_u32(12)!=5 or data.decode_u32(116)!=4:return {}
 var sites:Array[Dictionary]=[];var roads:Array[Dictionary]=[]
 for i in 5:
  var at:=16+i*20
  sites.append({"id":i,"position":Vector3(data.decode_float(at),data.decode_float(at+4),data.decode_float(at+8)),"radius":data.decode_float(at+12),"kind":"city" if data.decode_u32(at+16)==1 else "town"})
 for i in 4:
  var at:=120+i*12
  roads.append({"from":data.decode_u32(at),"to":data.decode_u32(at+4),"half_width":data.decode_float(at+8)})
 var underground:Array[Dictionary]=[]
 if generator>=10:
  var poi:PackedByteArray=core.execute(Codec.command(35))
  if not Codec.reply_ok(poi) or poi.size()!=76 or poi.decode_u32(12)!=1 or poi.decode_u32(16)!=1:return {}
  var entrance:=Vector3(poi.decode_float(32),poi.decode_float(36),poi.decode_float(40))
  var low:=Vector3(poi.decode_float(44),poi.decode_float(48),poi.decode_float(52))
  var high:=Vector3(poi.decode_float(56),poi.decode_float(60),poi.decode_float(64))
  underground.append({"id":poi.decode_u32(20),"owner_site":poi.decode_u32(24),"kind":"mine","entrance":entrance,"bounds":AABB(low,high-low),"first_primitive":poi.decode_u32(68),"primitive_count":poi.decode_u32(72)})
 return {"version":1,"generator":generator,"seed":seed_value,"sites":sites,"roads":roads,"underground":underground}

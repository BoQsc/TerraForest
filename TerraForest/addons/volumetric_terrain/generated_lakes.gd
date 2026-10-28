# SPDX-License-Identifier: 0BSD
extends RefCounted
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
static func describe(core:RefCounted,generator:int)->Dictionary:
 var definitions:PackedByteArray=core.execute(Codec.command(27))
 if not Codec.reply_ok(definitions) or definitions.size()<16:return {"ok":false}
 var count:int=definitions.decode_u32(12)
 if count>16 or definitions.size()!=16+count*44:return {"ok":false}
 var records:Array=[]
 for i in count:
  var offset:=16+i*44
  records.append({"id":i+1,"origin":Vector3(definitions.decode_float(offset),definitions.decode_float(offset+4),definitions.decode_float(offset+8)),"cells":Vector3i(definitions.decode_u32(offset+12),definitions.decode_u32(offset+16),definitions.decode_u32(offset+20)),"spacing":definitions.decode_float(offset+24),"level":definitions.decode_float(offset+28),"seed":Vector3(definitions.decode_float(offset+32),definitions.decode_float(offset+36),definitions.decode_float(offset+40))})
 return core.fit_generated_lakes(records) if generator in [19,21,23] else {"ok":true,"records":records,"rejected":[],"height_samples":0}

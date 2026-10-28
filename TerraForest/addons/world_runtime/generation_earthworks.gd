# SPDX-License-Identifier: 0BSD
extends RefCounted
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
static func packets(segments:Array,deposits:Array=[])->Array:
 if segments.is_empty() and deposits.is_empty() or segments.size()+deposits.size()>16384:return []
 var result:Array=[]
 var ordered:Array=[]
 for segment:Dictionary in segments:
  if int(segment.material)!=4:ordered.append(segment)
 for segment:Dictionary in segments:
  if int(segment.material)==4:ordered.append(segment)
 for segment:Dictionary in ordered:
  var packet:PackedByteArray
  if segment.has("coefficients"):
   packet=Codec.curved_road_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,segment.coefficients,segment.curve_index)
   if packet.is_empty():return []
   packet.encode_u32(40,segment.material);packet.encode_float(44,segment.shoulder)
  else:
   packet=Codec.graded_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,segment.material)
   if segment.shoulder!=0.0:packet.resize(48);packet.encode_float(44,segment.shoulder)
   if segment.get("rectangular",false):packet.resize(52);packet.encode_u32(48,1)
  result.append(packet)
 for deposit:Dictionary in deposits:
  var packet:=Codec.brush(deposit.position+Vector3.UP*.25,(deposit.start+deposit.finish)*.5,1.6,4,true,deposit.material)
  packet.encode_u32(0,41)
  result.append(packet)
 return result

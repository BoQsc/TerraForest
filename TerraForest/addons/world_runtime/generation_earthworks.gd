# SPDX-License-Identifier: 0BSD
extends RefCounted
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
static func packets(segments:Array)->Array:
 if segments.is_empty() or segments.size()>4096:return []
 var result:Array=[]
 for segment:Dictionary in segments:
  var packet:PackedByteArray
  if segment.has("coefficients"):
   packet=Codec.curved_road_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,segment.coefficients,segment.curve_index)
   if packet.is_empty():return []
   packet.encode_u32(40,segment.material);packet.encode_float(44,segment.shoulder)
  else:
   packet=Codec.graded_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,segment.material)
   if segment.shoulder!=0.0:packet.resize(48);packet.encode_float(44,segment.shoulder)
  result.append(packet)
 return result

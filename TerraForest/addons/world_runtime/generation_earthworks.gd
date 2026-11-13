# SPDX-License-Identifier: 0BSD
extends RefCounted
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
static func ordered_segments(segments:Array)->Array:
 if segments.size()>16384:return []
 var ordered:Array=[]
 for segment:Dictionary in segments:
  if segment.get("phase","") not in ["","excavation","surface_clearance"]:return []
  if segment.get("arched",false) and (segment.get("phase","")!="excavation" or not segment.get("cut_only",false) or segment.get("rectangular",false) or segment.get("level_caps",false) or segment.get("shoulder",0)!=0 or segment.has("coefficients")):return []
  if segment.get("phase","")=="surface_clearance" and (not segment.get("cut_only",false) or not segment.get("rectangular",false)):return []
  if int(segment.material)!=4 and segment.get("phase","")=="":ordered.append(segment)
 for segment:Dictionary in segments:
  if int(segment.material)==4 and segment.get("phase","")=="":ordered.append(segment)
 # Interior voids are final cuts. Material sorting must never let an access road
 # refill a cellar/garage after its clearance was authored.
 for segment:Dictionary in segments:
  if segment.get("phase","")=="excavation":ordered.append(segment)
 for segment:Dictionary in segments:
  if segment.get("phase","")=="surface_clearance":ordered.append(segment)
 return ordered

static func packets(segments:Array,deposits:Array=[])->Array:
 if segments.is_empty() and deposits.is_empty() or segments.size()+deposits.size()>16384:return []
 var result:Array=[]
 var ordered:=ordered_segments(segments)
 if ordered.size()!=segments.size():return []
 for segment:Dictionary in ordered:
  var packet:PackedByteArray
  if segment.has("coefficients"):
   packet=Codec.curved_road_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,curve_prefix(segment),segment.curve_index)
   if packet.is_empty():return []
   packet.encode_u32(40,segment.material);packet.encode_float(44,segment.shoulder)
  else:
   packet=Codec.graded_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,segment.material)
   if segment.shoulder!=0.0:packet.resize(48);packet.encode_float(44,segment.shoulder)
   var profile:int=(1 if segment.get("rectangular",false) else 0)|(2 if segment.get("level_caps",false) else 0)|(4 if segment.get("cut_only",false) else 0)|(8 if segment.get("arched",false) else 0)
   if profile:packet.resize(52);packet.encode_u32(48,profile)
  result.append(packet)
 for deposit:Dictionary in deposits:
  var packet:=Codec.brush(deposit.position+Vector3.UP*.25,(deposit.start+deposit.finish)*.5,1.6,4,true,deposit.material)
  packet.encode_u32(0,41)
  result.append(packet)
 return result

static func curve_prefix(segment:Dictionary)->PackedFloat64Array:
 var coefficients:PackedFloat64Array=segment.coefficients
 var index:int=segment.curve_index
 if coefficients.size()%4!=0 or coefficients.size()>256 or index<0 or index>=coefficients.size()/4:return coefficients
 var span:=Vector2(segment.finish.x-segment.start.x,segment.finish.z-segment.start.z).length()
 if span<1:return coefficients
 # Native edits sample a bounding box expanded by width + shoulder + SDF_BAND
 # (4 m) + 1 m, with one further metre for floor rounding. Its projection onto
 # any horizontal road axis is at most sqrt(2) times that expansion. Retain all
 # curve sections reachable by those samples, including the rounded end cap.
 # Keep the prefix/index unchanged: removing earlier sections changes floating
 # point addition in the native field and would not preserve exact voxel bytes.
 var following:=ceili(sqrt(2.0)*(float(segment.half_width)+float(segment.shoulder)+6.0)/span)+2
 return coefficients.slice(0,mini(coefficients.size(),(index+following)*4))

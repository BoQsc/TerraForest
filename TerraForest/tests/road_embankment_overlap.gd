# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func density(core:RefCounted,p:Vector3)->float:
 var q:=Codec.point_command(p);q.encode_u32(0,26);return core.execute(q).decode_float(16)
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,2]))
 var roads:Array=[]
 for yz:Vector2 in [Vector2(180,400),Vector2(176,408)]:
  roads.append({"start":Vector3(400,yz.x,yz.y),"finish":Vector3(432,yz.x,yz.y),"half_width":4.0,"depth":1.0,"clearance":12.0,"shoulder":0.0,"material":4,"bounds":AABB(Vector3(380,160,380),Vector3(80,40,60))})
 var plan:Dictionary={"segments":roads.duplicate(),"bounds":roads[0].bounds}
 var ok:bool=preload("res://addons/structures/site_plan.gd")._support_roads(plan,roads)
 for segment:Dictionary in plan.segments:
  var packet:=Codec.graded_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,segment.material)
  packet.resize(48);packet.encode_float(44,segment.shoulder)
  ok=Codec.reply_ok(core.execute(packet)) and ok
 # A lower adjacent road's shoulder must not excavate the higher road bed.
 for z in [400,402,403]:
  ok=ok and density(core,Vector3(416,179,z))<0 and density(core,Vector3(416,181,z))>0
 ok=ok and density(core,Vector3(416,175,408))<0 and density(core,Vector3(416,177,408))>0
 print("ROAD_EMBANKMENT_OVERLAP failures=",0 if ok else 1)
 quit(0 if ok else 1)

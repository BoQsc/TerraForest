# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Plan=preload("res://addons/structures/site_plan.gd")
func density(core:RefCounted,p:Vector3)->float:
 var q:=Codec.point_command(p);q.encode_u32(0,26);return core.execute(q).decode_float(16)
func _initialize()->void:
 var center:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(42,13).sites[3].position
 # Freeze the original failing tower case; current neighborhood recipes may change.
 var lot:Dictionary={"asset":preload("res://addons/structures/furniture_catalog.gd").furnished_tower(3),"origin":Vector3i(center)+Vector3i(-24,0,68),"rotation":2}
 var origin:Vector3i=lot.origin;origin.y=56
 var bounds:AABB=lot.asset.placement_bounds(origin,lot.rotation)
 var baseline=ClassDB.instantiate("TerrainCore");baseline.execute(Codec.command(6,[42,13]))
 var points:=PackedVector3Array()
 for x in range(int(bounds.position.x)-20,int(bounds.end.x)+21):
  for z in range(int(bounds.position.z)-20,int(bounds.end.z)+21):
   if x>=bounds.position.x and x<=bounds.end.x and z>=bounds.position.z and z<=bounds.end.z:continue
   var query:=Codec.command(17,[1]);query.append_array(PackedVector3Array([Vector3(x,0,z)]).to_byte_array())
   var reply:PackedByteArray=baseline.execute(query)
   points.append(Vector3(x,reply.decode_float(20)-0.25,z))
 var removed:Array=[]
 for width in [24.0,4.0]:
  var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[42,13]))
  var plan:Dictionary=Plan.foundation(lot.asset,origin,lot.rotation,56,width)
  for segment:Dictionary in plan.segments:
   var packet:=Codec.graded_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,segment.material)
   packet.resize(48);packet.encode_float(44,segment.shoulder)
   if not Codec.reply_ok(core.execute(packet)):print("LOT_GRADING_FOOTPRINT failures=1 edit rejected");quit(1);return
  var count:=0
  for point in points:
   if density(baseline,point)<0 and density(core,point)>0:count+=1
  removed.append(count)
 var ok:bool=removed[1]<removed[0]
 print("LOT_GRADING_FOOTPRINT failures=",0 if ok else 1," outside_surface_samples_removed wide=",removed[0]," narrow=",removed[1]," samples=",points.size())
 quit(0 if ok else 1)

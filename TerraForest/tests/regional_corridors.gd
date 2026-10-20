# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:
 var generator:int=16 if "--sited" in OS.get_cmdline_user_args() else 15
 var failures:=0;var max_grade:=0.0;var max_error:=0.0;var bent:=0
 for seed_value in [0,1,42,50,141,1703,9999]:
  var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,generator]))
  var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,generator)
  if layout.is_empty():failures+=1;continue
  for road:Dictionary in layout.roads:
   var points:PackedVector3Array=road.points
   if points[0]!=layout.sites[road.from].position or points[-1]!=layout.sites[road.to].position:failures+=1
   var axis:Vector3=points[-1]-points[0];axis.y=0;axis=axis.normalized()
   var lateral:=0.0
   for p:Vector3 in points:lateral=maxf(lateral,absf((p-points[0]).dot(Vector3(-axis.z,0,axis.x))))
   if lateral>2:bent+=1
   for k in range(1,points.size()):
    var span:Vector3=points[k]-points[k-1]
    var grade:float=absf(span.y)/Vector2(span.x,span.z).length();max_grade=maxf(max_grade,grade)
    if grade>0.1201:failures+=1
    for sample_index in 9:
     var p:Vector3=points[k-1].lerp(points[k],sample_index/8.0)
     var query:=Codec.command(7);query.append_array(PackedVector3Array([p]).to_byte_array())
     var reply:PackedByteArray=core.execute(query)
     if not Codec.reply_ok(reply):failures+=1;continue
     var error:float=absf(reply.decode_float(12)-p.y);max_error=maxf(max_error,error)
     if error>0.5:
      if failures<8:print("ROAD_MISMATCH seed=",seed_value," road=",road.to," station=",k," point=",p," ground=",reply.decode_float(12))
      failures+=1
  var saved:PackedByteArray=core.execute(Codec.command(4)).slice(12)
  var clone=ClassDB.instantiate("TerrainCore");var load_command:=Codec.command(5);load_command.append_array(saved)
  if not Codec.reply_ok(clone.execute(load_command)) or clone.execute(Codec.command(36))!=core.execute(Codec.command(36)):failures+=1
 if bent<7:failures+=1
 print("CORRIDOR_PROFILE bent_roads=",bent," max_grade=",max_grade," surface_error=",max_error)
 print("REGIONAL_CORRIDORS failures=",failures);quit(1 if failures else 0)

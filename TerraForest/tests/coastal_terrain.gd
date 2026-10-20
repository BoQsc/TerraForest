# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
func _initialize()->void:
 var old=ClassDB.instantiate("TerrainCore");var coast=ClassDB.instantiate("TerrainCore")
 old.execute(Codec.command(6,[42,17]))
 if not Codec.reply_ok(coast.execute(Codec.command(6,[42,18]))):quit(1);return
 var inland:=PackedVector3Array([Vector3(906,0,855),Vector3(1132,0,526),Vector3(72,0,1008),Vector3(24,0,960),Vector3(24,0,1056)])
 if Planner.heights(old,inland)!=Planner.heights(coast,inland):print("COAST_INLAND_CHANGED");quit(1);return
 var shore:=Planner.heights(coast,PackedVector3Array([Vector3(2,0,1008),Vector3(39,0,1008),Vector3(24,0,970),Vector3(24,0,1046)]))
 if shore[0]>=40 or shore[1]<=40 or shore[2]<=40 or shore[3]<=40:print("COAST_BOUNDS ",shore);quit(1);return
 # Dry beach keeps some supported roots; wet beach stays clear. Query twice
 # to catch nondeterministic placement that could flicker during streaming.
 var points:=PackedVector3Array()
 for z in range(990,1026,6):
  for x in range(6,46,4):points.append(Vector3(x+0.25,0,z+0.25))
 var query:=Codec.command(17,[points.size()]);query.append_array(points.to_byte_array())
 var roots:PackedByteArray=coast.execute(query)
 if not Codec.reply_ok(roots) or roots!=coast.execute(query):quit(1);return
 var dry_roots:=0;var wet_roots:=0;var rejected_dry:=0
 for i in points.size():
  var height:=roots.decode_float(20+i*12)
  var supported:=roots.decode_float(20+points.size()*12+i*12)>0.0
  if height<=40.15 and supported:wet_roots+=1
  if height>40.15 and height<44.5:
   if supported:dry_roots+=1
   else:rejected_dry+=1
 if dry_roots==0 or wet_roots!=0 or rejected_dry==0:
  print("COAST_ROOTS_FAILED ",dry_roots," / ",wet_roots," / ",rejected_dry);quit(1);return
 print("COAST_ROOTS dry=",dry_roots," wet=",wet_roots," dry_openings=",rejected_dry)
 var bytes:PackedByteArray=coast.execute(Codec.command(4)).slice(12)
 var restored=ClassDB.instantiate("TerrainCore");var packet:=Codec.command(5);packet.append_array(bytes)
 if not Codec.reply_ok(restored.execute(packet)) or restored.execute(Codec.command(4)).slice(12)!=bytes:quit(1);return
 print("COASTAL_TERRAIN failures=0 shore=",shore);quit()

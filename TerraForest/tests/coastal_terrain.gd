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
 var bytes:PackedByteArray=coast.execute(Codec.command(4)).slice(12)
 var restored=ClassDB.instantiate("TerrainCore");var packet:=Codec.command(5);packet.append_array(bytes)
 if not Codec.reply_ok(restored.execute(packet)) or restored.execute(Codec.command(4)).slice(12)!=bytes:quit(1);return
 print("COASTAL_TERRAIN failures=0 shore=",shore);quit()

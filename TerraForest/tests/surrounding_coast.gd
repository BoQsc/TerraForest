# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
 for seed_value:int in [0,42,1703,2147483647]:
  var original=ClassDB.instantiate("TerrainCore");original.execute(Codec.command(6,[seed_value,17]))
  var coast=ClassDB.instantiate("TerrainCore")
  check(Codec.reply_ok(coast.execute(Codec.command(6,[seed_value,19]))),"coast profile accepted seed %d"%seed_value)
  var edges:=PackedVector3Array();var rim:=PackedVector3Array();var interior:=PackedVector3Array()
  for distance in range(0,2001,20):
   edges.append_array(PackedVector3Array([Vector3(0,0,distance),Vector3(2000,0,distance),Vector3(distance,0,0),Vector3(distance,0,2000)]))
  for distance in range(140,1861,20):
   rim.append_array(PackedVector3Array([Vector3(140,0,distance),Vector3(1860,0,distance),Vector3(distance,0,140),Vector3(distance,0,1860)]))
  for x in range(240,1761,80):
   for z in range(240,1761,80):interior.append(Vector3(x,0,z))
  # Planner batches native survey calls; roots have a separate 64-point limit.
  var shore:=Planner.heights(coast,edges);var dry:=Planner.heights(coast,rim)
  check(shore.size()==edges.size() and Array(shore).max()<40.0,"entire perimeter including all corners below sea")
  check(dry.size()==rim.size() and Array(dry).min()>40.0,"continuous dry inner rim excludes inland flooding")
  check(Planner.heights(coast,interior)==Planner.heights(original,interior),"interior unchanged outside 240m coast band")
  var seam:=PackedVector3Array()
  for distance in range(240,1761,80):
   for edge:Vector3 in [Vector3(240,0,distance),Vector3(1760,0,distance),Vector3(distance,0,240),Vector3(distance,0,1760)]:
    seam.append(edge-Vector3(0.01,0,0.01));seam.append(edge+Vector3(0.01,0,0.01))
  var heights:=Planner.heights(coast,seam);var jump:=0.0
  for i in range(0,heights.size(),2):jump=maxf(jump,absf(heights[i+1]-heights[i]))
  check(jump<0.1,"coast/interior join continuous")
  var bytes:PackedByteArray=coast.execute(Codec.command(4)).slice(12)
  var restored=ClassDB.instantiate("TerrainCore");var packet:=Codec.command(5);packet.append_array(bytes)
  check(Codec.reply_ok(restored.execute(packet)) and restored.execute(Codec.command(4)).slice(12)==bytes,"profile identity survives snapshot")
 print("SURROUNDING_COAST failures=",failures)
 quit(1 if failures else 0)

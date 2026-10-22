# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[42,13]))
 var p:=Vector3(1019.25,0,1019.25)
 var h:float=core.execute(Codec.point_command(p)).decode_float(12)
 var above:=Vector3(p.x,h+3,p.z);var cave:=Vector3(p.x,h-12,p.z)
 core.execute(Codec.brush(cave,cave,3,1,false,3))
 var points:=PackedVector3Array([above,cave,Vector3(p.x,h-2,p.z)])
 var result:Dictionary=core.survey_water_visibility(points)
 var failures:=0
 if not result.get("ok",false) or result.visible!=PackedByteArray([1,0,0]):failures+=1
 # Open the ceiling: the same underground point must now be visible from above.
 for y in range(floori(cave.y),ceili(above.y)+1,2):
  var center:=Vector3(p.x,y,p.z);core.execute(Codec.brush(center,center,4,1,false,3))
 var opened:Dictionary=core.survey_water_visibility(points)
 if not opened.get("ok",false) or opened.visible!=PackedByteArray([1,1,1]):failures+=1
 var copy=ClassDB.instantiate("TerrainCore");var saved:PackedByteArray=core.execute(Codec.command(4));var load:=Codec.command(5);load.append_array(saved.slice(12));copy.execute(load)
 if copy.survey_water_visibility(points).visible!=opened.visible:failures+=1
 var excessive:=PackedVector3Array();excessive.resize(257)
 for invalid:PackedVector3Array in [PackedVector3Array(),excessive,PackedVector3Array([Vector3(NAN,2,2)]),PackedVector3Array([Vector3(2000,2,2)])]:
  if core.survey_water_visibility(invalid).get("ok",false):failures+=1
 print("SURVEY_WATER_VISIBILITY failures=",failures," closed=",result.get("visible",[])," opened=",opened.get("visible",[])," native_ms=",opened.get("generation_ms",-1))
 quit(1 if failures else 0)

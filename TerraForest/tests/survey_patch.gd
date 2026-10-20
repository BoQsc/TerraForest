# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[42,13]))
 var before:Dictionary=core.survey_patch(256,128,128,4,4)
 var center:=Vector3(1019.5,100,1019.5)
 var h:float=core.execute(Codec.point_command(center)).decode_float(12);center.y=h
 var edit:PackedByteArray=core.execute(Codec.brush(center,center,14,1,false,3))
 var after:Dictionary=core.survey_patch(256,128,128,4,4)
 var failures:=0
 if not Codec.reply_ok(edit) or not before.ok or not after.ok or before.pixels==after.pixels:failures+=1
 var copy=ClassDB.instantiate("TerrainCore");var saved:PackedByteArray=core.execute(Codec.command(4));var load:=Codec.command(5);load.append_array(saved.slice(12));copy.execute(load)
 if copy.survey_patch(256,128,128,4,4).pixels!=after.pixels:failures+=1
 if core.survey_patch(256,255,255,4,4).get("ok",false) or core.survey_patch(256,0,0,5,4).get("ok",false):failures+=1
 print("SURVEY_PATCH failures=",failures," before_ms=",before.generation_ms," after_ms=",after.generation_ms)
 quit(1 if failures else 0)

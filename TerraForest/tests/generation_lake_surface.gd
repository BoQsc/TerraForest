# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
 var failures:=0;var results:Array=[]
 for seed_value in [0,42,1703]:
  var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,19]))
  var definitions:Dictionary=preload("res://addons/volumetric_terrain/generated_lakes.gd").describe(core,19)
  var before:PackedByteArray=core.execute(Codec.command(4));var began:=Time.get_ticks_usec()
  var result:Dictionary=core.survey_generated_lake_surfaces(definitions.records)
  var elapsed:=(Time.get_ticks_usec()-began)/1000.0
  if not result.get("ok",false) or result.points.is_empty() or result.points.size()>25600 or core.execute(Codec.command(4))!=before:failures+=1
  if result!=core.survey_generated_lake_surfaces(definitions.records):failures+=1
  results.append({"seed":seed_value,"lakes":definitions.records.size(),"points":result.points.size(),"samples":result.samples,"ms":elapsed})
  if core.survey_generated_lake_surfaces([{}]).get("ok",false):failures+=1
 FileAccess.open("res://reports/generation_lake_surface.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"cases":results,"scope":"2m connected surface survey for generated bowl preview; no water volume, runtime or edited-world equivalence claim"},"  "))
 print("GENERATION_LAKE_SURFACE failures=",failures," ",JSON.stringify(results));quit(1 if failures else 0)

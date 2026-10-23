# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:
 var core=ClassDB.instantiate("TerrainCore")
 var rows:=[]
 for seed_value in [0,42,1703]:
  core.execute(Codec.command(6,[seed_value,19]))
  for size in [64,256,512]:
   var result:Dictionary=core.survey_overview(size)
   var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(result.pixels)
   rows.append({"seed":seed_value,"size":size,"digest":hash.finish().hex_encode(),"ms":result.generation_ms,"workers":result.get("workers",1)})
 var path:="res://reports/generation_survey_serial.json" if "--record-serial" in OS.get_cmdline_user_args() else "res://reports/generation_survey_parallel.json"
 var failures:=0
 if not "--record-serial" in OS.get_cmdline_user_args():
  var before:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generation_survey/serial_hashes.json"))
  for i in rows.size():
   if rows[i].digest!=before[i].digest:failures+=1
 var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(rows,"  "));file.close()
 print("GENERATION_SURVEY_EQUIVALENCE failures=",failures," rows=",rows)
 quit(1 if failures else 0)

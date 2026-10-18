# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var core=ClassDB.instantiate("TerrainCore")
 var failures:=0
 for seed_value in [1703,1,42,9999]:
  core.execute(Codec.command(6,[seed_value,12]))
  var d:PackedByteArray=core.execute(Codec.command(27))
  var level:=d.decode_float(44)
  var center:=Vector3(d.decode_float(48),level,d.decode_float(56))
  var h:float=core.execute(Codec.point_command(center)).decode_float(12)
  var near:float=core.execute(Codec.point_command(center+Vector3(60,0,0))).decode_float(12)
  var rim:float=core.execute(Codec.point_command(center+Vector3(80,0,0))).decode_float(12)
  var ok:bool=d.size()==192 and absf(h-level+5)<.01 and near<level and rim>level+2.9
  var bounds:=Vector3i(d.decode_u32(28),d.decode_u32(32),d.decode_u32(36))
  ok=ok and bounds==Vector3i(68,4,68) and d.decode_float(40)==2
  print("PASS " if ok else "FAIL ","large closed shallow basin seed=",seed_value)
  if not ok:failures+=1
 print("REGIONAL_LAKE_LAYOUT failures=",failures);quit(1 if failures else 0)

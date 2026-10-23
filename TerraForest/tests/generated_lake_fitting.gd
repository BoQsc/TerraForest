# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize():
 var failures:=0
 var core=ClassDB.instantiate("TerrainCore")
 for seed_value in [0,1,42,1703,9999,2147483647]:
  core.execute(Codec.command(6,[seed_value,19]))
  var bytes:PackedByteArray=core.execute(Codec.command(27));var records=[]
  for i in bytes.decode_u32(12):
   var at=16+i*44
   records.append({"id":i+1,"origin":Vector3(bytes.decode_float(at),bytes.decode_float(at+4),bytes.decode_float(at+8)),"cells":Vector3i(bytes.decode_u32(at+12),bytes.decode_u32(at+16),bytes.decode_u32(at+20)),"spacing":bytes.decode_float(at+24),"level":bytes.decode_float(at+28),"seed":Vector3(bytes.decode_float(at+32),bytes.decode_float(at+36),bytes.decode_float(at+40))})
  var fitted:Dictionary=core.fit_generated_lakes(records)
  if not fitted.ok or fitted.records.is_empty() or fitted!=core.fit_generated_lakes(records):failures+=1;continue
  for record in fitted.records:
   var height:float=core.execute(Codec.point_command(record.seed)).decode_float(12)
   if height>=record.seed.y or record.seed.y>=record.level or not AABB(record.origin,Vector3(record.cells)*record.spacing).has_point(record.seed):failures+=1
  print("FITTED seed=",seed_value," accepted=",fitted.records.size()," rejected=",fitted.rejected)
 if core.fit_generated_lakes([{}]).ok or core.fit_generated_lakes([12]).ok:failures+=1
 print("GENERATED_LAKE_FITTING failures=",failures);quit(1 if failures else 0)

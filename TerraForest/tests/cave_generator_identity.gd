# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const BASE="res://docs/evidence/cave_generator_v6/legacy.bin"
var failures:=0
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func fingerprint(core:RefCounted,generator:int)->PackedByteArray:
 core.execute(Codec.command(6,[1703,generator]))
 var data:PackedByteArray=core.execute(Codec.command(25));data.append_array(core.execute(Codec.command(4)))
 for x in range(817,850,2):
  for y in range(130,160,2):
   var query:=Codec.point_command(Vector3(x,y,398));query.encode_u32(0,26);data.append_array(core.execute(query))
 return data
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var core=ClassDB.instantiate("TerrainCore")
 var data:=PackedByteArray()
 for generator in range(1,6):data.append_array(fingerprint(core,generator))
 if "--capture-legacy" in OS.get_cmdline_user_args():
  DirAccess.make_dir_recursive_absolute("res://docs/evidence/cave_generator_v6")
  var file:=FileAccess.open(BASE,FileAccess.WRITE);file.store_buffer(data);file.close()
  print("CAVE_LEGACY_CAPTURE bytes=",data.size());quit();return
 check(data==FileAccess.get_file_as_bytes(BASE),"generator1-5 descriptors, snapshots and sampled densities match prechange binary")
 check(Codec.reply_ok(core.execute(Codec.command(6,[1703,6]))),"new cave profile accepted")
 var descriptors:PackedByteArray=core.execute(Codec.command(25))
 check(descriptors.decode_u32(20)==20,"same bounded twenty capsule representation")
 var saved:PackedByteArray=core.execute(Codec.command(4)).slice(12)
 var new_key:Dictionary=core.geometry_cache_key(832,384,16,1)
 core.execute(Codec.command(6,[1703,4]))
 check(new_key!=core.geometry_cache_key(832,384,16,1),"new geometry cannot reuse legacy generator cache identity")
 var packet:=Codec.command(5);packet.append_array(saved)
 check(Codec.reply_ok(core.execute(packet)) and core.execute(Codec.command(25))==descriptors,"saved generator6 restores exact cave descriptors")
 check(core.execute(Codec.command(4)).slice(12)==saved,"new snapshot roundtrips exactly")
 core.execute(Codec.command(6,[1703,6]))
 check(core.execute(Codec.command(25))==descriptors,"same seed regenerates same new cave network")
 core.execute(Codec.command(6,[1704,6]))
 check(core.execute(Codec.command(25))!=descriptors,"different seed changes new cave network")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/cave_generator_identity.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures}));file.close()
 print("CAVE_GENERATOR_IDENTITY failures=",failures);quit(1 if failures else 0)

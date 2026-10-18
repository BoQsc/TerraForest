# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:
 var old=ClassDB.instantiate("TerrainCore");var current=ClassDB.instantiate("TerrainCore")
 var ok:bool=Codec.reply_ok(old.execute(Codec.command(6,[42,12]))) and Codec.reply_ok(current.execute(Codec.command(6,[42,13])))
 var descriptors:PackedByteArray=current.execute(Codec.command(25))
 # Header identifies the generator; primitive payload must retain geometry.
 ok=ok and descriptors.slice(20)==old.execute(Codec.command(25)).slice(20)
 var checks:=0
 for x in range(1500,1651,5):
  for z in range(990,1101,5):
   for y in [29.5,30.0,31.5,40.0]:
    var point:=Vector3(x,y,z)
    var packet:=Codec.point_command(point);packet.encode_u32(0,26)
    var a:PackedByteArray=old.execute(packet);var b:PackedByteArray=current.execute(packet)
    ok=ok and Codec.reply_ok(a) and Codec.reply_ok(b) and a.decode_float(16)==b.decode_float(16)
    checks+=1
 var saved:PackedByteArray=current.execute(Codec.command(4)).slice(12)
 var key:Dictionary=current.geometry_cache_key(1600,1040,16,1)
 ok=ok and key!=old.geometry_cache_key(1600,1040,16,1)
 var packet:=Codec.command(5);packet.append_array(saved)
 ok=ok and Codec.reply_ok(old.execute(packet)) and old.execute(Codec.command(4)).slice(12)==saved and old.execute(Codec.command(25))==descriptors
 print("RESOURCE_MINE_IDENTITY failures=",0 if ok else 1," density_samples=",checks)
 quit(0 if ok else 1)

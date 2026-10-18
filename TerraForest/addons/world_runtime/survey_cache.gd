# SPDX-License-Identifier: 0BSD
extends RefCounted
# CPU-only derived cartography. Use an isolated native core; no live terrain lock.
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const VERSION:=1
const SIZE:=256
const BYTES:=SIZE*SIZE*4
static func digest(data:PackedByteArray)->PackedByteArray:
 var hash_context:=HashingContext.new();hash_context.start(HashingContext.HASH_SHA256);hash_context.update(data);return hash_context.finish()
static func build(seed_value:int,generator:int,cache_root:String="user://cartography")->Dictionary:
 var started:=Time.get_ticks_usec()
 var path:=cache_root+"/survey_%d_%d_%d.bin"%[VERSION,generator,seed_value]
 var pixels:=PackedByteArray();var hit:=false;var native_ms:=0.0
 if FileAccess.file_exists(path):
  var file:=FileAccess.open(path,FileAccess.READ)
  if file!=null and file.get_length()==BYTES+32:
   var expected_digest:=file.get_buffer(32);var candidate:=file.get_buffer(BYTES)
   if digest(candidate)==expected_digest:pixels=candidate;hit=true
 if pixels.is_empty():
  var core=ClassDB.instantiate("TerrainCore")
  if core==null or not Codec.reply_ok(core.execute(Codec.command(6,[seed_value,generator]))):return {"ok":false}
  var result:Dictionary=core.survey_overview(SIZE)
  if not result.ok:return {"ok":false}
  pixels=result.pixels;native_ms=result.generation_ms
  DirAccess.make_dir_recursive_absolute(cache_root)
  var temporary:=path+".tmp_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
  var file:=FileAccess.open(temporary,FileAccess.WRITE)
  if file!=null:
   file.store_buffer(digest(pixels));file.store_buffer(pixels);file.close()
   DirAccess.rename_absolute(temporary,path)
 return {"ok":true,"pixels":pixels,"cache_hit":hit,"native_ms":native_ms,"worker_ms":(Time.get_ticks_usec()-started)/1000.0}

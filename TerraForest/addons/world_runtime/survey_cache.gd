# SPDX-License-Identifier: 0BSD
extends RefCounted
# CPU-only derived cartography. Use an isolated native core; no live terrain lock.
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const VERSION:=3
const SIZE:=256
const BYTES:=SIZE*SIZE*4
const HEADER_BYTES:=24
static func digest(data:PackedByteArray)->PackedByteArray:
 var hash_context:=HashingContext.new();hash_context.start(HashingContext.HASH_SHA256)
 if not data.is_empty():hash_context.update(data)
 return hash_context.finish()
static func cache_path(seed_value:int,generator:int,cache_root:String)->String:
 return cache_root+"/survey_%d_%d_%d.bin"%[VERSION,generator,seed_value]
static func identity(seed_value:int,generator:int)->PackedByteArray:
 var header:PackedByteArray="TFMAP003".to_utf8_buffer();header.resize(HEADER_BYTES)
 header.encode_s64(8,seed_value);header.encode_s32(16,generator);header.encode_u32(20,SIZE)
 return header
static func read_pixels(path:String,header:PackedByteArray)->PackedByteArray:
 if not FileAccess.file_exists(path):return PackedByteArray()
 var file:=FileAccess.open(path,FileAccess.READ)
 if file==null or file.get_length()!=HEADER_BYTES+BYTES+32:return PackedByteArray()
 if file.get_buffer(HEADER_BYTES)!=header:return PackedByteArray()
 var expected:=file.get_buffer(32);var pixels:=file.get_buffer(BYTES)
 if digest(header+pixels)!=expected:return PackedByteArray()
 return pixels
static func build(seed_value:int,generator:int,cache_root:String="user://cartography")->Dictionary:
 var started:=Time.get_ticks_usec()
 var path:=cache_path(seed_value,generator,cache_root)
 var header:=identity(seed_value,generator)
 var pixels:=read_pixels(path,header);var hit:=not pixels.is_empty();var native_ms:=0.0
 var persisted:=hit
 if not hit:
  var core=ClassDB.instantiate("TerrainCore")
  if core==null or not Codec.reply_ok(core.execute(Codec.command(6,[seed_value,generator]))):return {"ok":false}
  var result:Dictionary=core.survey_overview(SIZE)
  if not result.ok:return {"ok":false}
  pixels=result.pixels;native_ms=result.generation_ms
  DirAccess.make_dir_recursive_absolute(cache_root)
  var temporary:=path+".tmp_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
  var file:=FileAccess.open(temporary,FileAccess.WRITE)
  if file!=null:
   file.store_buffer(header);file.store_buffer(digest(header+pixels));file.store_buffer(pixels);file.close()
   if read_pixels(temporary,header)==pixels:
    persisted=DirAccess.rename_absolute(temporary,path)==OK
   if FileAccess.file_exists(temporary):DirAccess.remove_absolute(temporary)
 return {"ok":true,"pixels":pixels,"cache_hit":hit,"cache_persisted":persisted,"native_ms":native_ms,"worker_ms":(Time.get_ticks_usec()-started)/1000.0}
static func prepare(seed_value:int,generator:int,cache_root:String="user://cartography")->Dictionary:
 var result:=build(seed_value,generator,cache_root)
 if not result.get("ok",false):return result
 var reopened:=build(seed_value,generator,cache_root)
 var verified:bool=reopened.get("cache_hit",false) and reopened.get("pixels")==result.pixels
 result.erase("pixels")
 result["ok"]=verified
 result["reopen_verified"]=verified
 return result

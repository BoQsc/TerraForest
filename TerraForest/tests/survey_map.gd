# SPDX-License-Identifier: 0BSD
extends SceneTree
const Cache=preload("res://addons/world_runtime/survey_cache.gd")
func _initialize()->void:
 var failures:=0
 var core=ClassDB.instantiate("TerrainCore")
 for size in [0,63,1025,2147483647]:
  if core.survey_overview(size).ok:failures+=1
 var path:="user://map_check_%d"%OS.get_process_id()
 var first:Dictionary=Cache.build(42,13,path)
 var second:Dictionary=Cache.build(42,13,path)
 if not first.ok or not second.ok or first.cache_hit or not second.cache_hit or first.pixels!=second.pixels or first.pixels.size()!=256*256*4:failures+=1
 var different:Dictionary=Cache.build(43,13,path)
 if not different.ok or different.pixels==first.pixels:failures+=1
 # Correct-length corrupted bytes must be regenerated rather than displayed.
 var file:=FileAccess.open(Cache.cache_path(42,13,path),FileAccess.WRITE)
 var bad:=PackedByteArray();bad.resize(256*256*4+32+Cache.HEADER_BYTES);bad.fill(0);file.store_buffer(bad);file.close()
 var repaired:Dictionary=Cache.build(42,13,path)
 if not repaired.ok or repaired.cache_hit or repaired.pixels!=first.pixels:failures+=1
 var repaired_hit:Dictionary=Cache.build(42,13,path)
 if not repaired_hit.cache_hit or repaired_hit.pixels!=first.pixels:failures+=1
 # A valid checksum from another seed must not be accepted under this key.
 var other:=FileAccess.get_file_as_bytes(Cache.cache_path(43,13,path))
 file=FileAccess.open(Cache.cache_path(42,13,path),FileAccess.WRITE);file.store_buffer(other);file.close()
 var swapped:Dictionary=Cache.build(42,13,path)
 if not swapped.ok or swapped.cache_hit or swapped.pixels!=first.pixels:failures+=1
 var prepared:Dictionary=Cache.prepare(42,13,path)
 if not prepared.ok or not prepared.reopen_verified or prepared.has("pixels"):failures+=1
 var detailed:Dictionary=Cache.build(42,13,path,1024)
 var detailed_hit:Dictionary=Cache.build(42,13,path,1024)
 if not detailed.ok or detailed.pixels.size()!=1024*1024*4 or detailed.cache_hit or not detailed_hit.cache_hit or detailed_hit.pixels!=detailed.pixels:failures+=1
 if not Cache.build(42,13,path).cache_hit:failures+=1
 for name in DirAccess.get_files_at(path):DirAccess.remove_absolute(path+"/"+name)
 DirAccess.remove_absolute(path)
 print("SURVEY_MAP failures=",failures," native_ms=",first.native_ms," cold_ms=",first.worker_ms," cached_ms=",second.worker_ms)
 quit(1 if failures else 0)

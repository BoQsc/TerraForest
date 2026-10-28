# SPDX-License-Identifier: 0BSD
extends RefCounted
const Survey=preload("res://addons/world_runtime/survey_cache.gd")
const BYTES:=256*256*4
const MAGIC:="TFEDIT01"
const ROOT:="user://cartography/edited"
static func header(identity:String)->PackedByteArray:
 return MAGIC.to_utf8_buffer()+Survey.digest(("base=%d|"%Survey.VERSION+identity).to_utf8_buffer())
static func path_for(slot:String,folder:String)->String:
 return folder+"/"+Survey.digest(slot.to_utf8_buffer()).hex_encode()+".bin"
static func read(slot:String,identity:String,folder:String=ROOT,size:int=256)->Dictionary:
 var result:Dictionary={"hit":false}
 if identity.is_empty() or size not in [256,512,1024]:return result
 var file:=FileAccess.open(path_for(slot,folder),FileAccess.READ)
 if file==null or file.get_length()!=40+32+size*size*4:return result
 var expected:=header(identity)
 if file.get_buffer(40)!=expected:return result
 var checksum:=file.get_buffer(32);var pixels:=file.get_buffer(size*size*4)
 if Survey.digest(expected+pixels)!=checksum:return result
 return {"hit":true,"pixels":pixels}
static func write(slot:String,identity:String,pixels:PackedByteArray,folder:String=ROOT,limit:int=64,size:int=256)->Dictionary:
 var result:Dictionary={"persisted":false}
 if identity.is_empty() or size not in [256,512,1024] or pixels.size()!=size*size*4 or limit<1 or limit>64:return result
 if DirAccess.make_dir_recursive_absolute(folder)!=OK:return result
 var path:=path_for(slot,folder);var temporary:=path+".tmp_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
 var file:=FileAccess.open(temporary,FileAccess.WRITE)
 if file==null:return result
 var h:=header(identity);file.store_buffer(h);file.store_buffer(Survey.digest(h+pixels));file.store_buffer(pixels)
 var error:=file.get_error();file.close()
 if error==OK:result.persisted=DirAccess.rename_absolute(temporary,path)==OK
 if FileAccess.file_exists(temporary):DirAccess.remove_absolute(temporary)
 if not result.persisted:return result
 trim(folder,path,limit)
 return result

# Re-key only a bounded, verified derived raster after canonical publication.
# The identity header is content-based and deliberately contains no world name.
static func promote(source:String,destination:String,folder:String=ROOT)->Dictionary:
 var result:Dictionary={"promoted":false}
 if source==destination:return result
 var file:=FileAccess.open(path_for(source,folder),FileAccess.READ)
 if file==null:return result
 var bytes:=file.get_length()-72
 if bytes not in [BYTES,512*512*4,1024*1024*4]:return result
 var h:=file.get_buffer(40);var expected:=file.get_buffer(32);var pixels:=file.get_buffer(bytes);file.close()
 if h.slice(0,8)!=MAGIC.to_utf8_buffer() or Survey.digest(h+pixels)!=expected:return result
 var target:=path_for(destination,folder);var pending:=target+".tmp_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
 file=FileAccess.open(pending,FileAccess.WRITE)
 if file==null:return result
 file.store_buffer(h);file.store_buffer(expected);file.store_buffer(pixels);var error:=file.get_error();file.close()
 if error==OK:result.promoted=DirAccess.rename_absolute(pending,target)==OK
 if FileAccess.file_exists(pending):DirAccess.remove_absolute(pending)
 if result.promoted:trim(folder,target,64)
 return result

static func trim(folder:String,keep:String,limit:int)->void:
 # Dedicated disposable cache. Caller limits entries for its fixed raster size.
 # Only this folder is pruned; saves are never enumerated or deleted.
 var files:Array=[]
 for name in DirAccess.get_files_at(folder):
  if name.length()!=68 or not name.ends_with(".bin") or not name.trim_suffix(".bin").is_valid_hex_number():continue
  var candidate:=folder+"/"+name
  if candidate!=keep:files.append({"path":candidate,"time":FileAccess.get_modified_time(candidate)})
 files.sort_custom(func(a,b):return a.time<b.time)
 for i in maxi(0,files.size()+1-limit):DirAccess.remove_absolute(files[i].path)

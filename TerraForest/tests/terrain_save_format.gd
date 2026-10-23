# SPDX-License-Identifier: 0BSD
extends SceneTree
const Backend=preload("res://addons/volumetric_terrain/terrain_backend.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func wait_result(backend:RefCounted,kind:String)->Dictionary:
 var deadline:=Time.get_ticks_msec()+10000
 while Time.get_ticks_msec()<deadline:
  for value:Dictionary in backend.poll():
   if value.get("kind")==kind:return value
  await process_frame
 return {}
func open_backend(path:String)->RefCounted:
 var backend:=Backend.new();backend.disk_cache.enabled=false;backend.save_path=path
 backend.snapshot_codec=ClassDB.instantiate("NativeWorldArchive")
 check(backend.start(false)==OK,"terrain persistence worker starts")
 return backend
func run()->void:
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,19]))
 var point:=Vector3(1200,0,1200);point.y=core.execute(Codec.point_command(point)).decode_float(12)-0.6
 check(Codec.reply_ok(core.execute(Codec.brush(point,point,2.5,0,false,1))),"edited format 2 fixture prepared")
 var legacy:PackedByteArray=core.execute(Codec.command(4)).slice(12)
 var path:="user://worlds/terrain_format_%d_%d.trw"%[OS.get_process_id(),Time.get_ticks_usec()]
 DirAccess.make_dir_recursive_absolute(path.get_base_dir())
 var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(legacy);file.close()
 var backend:RefCounted=open_backend(path)
 var startup:Dictionary=await wait_result(backend,"startup");print("FORMAT_STARTUP ",startup.get("message","missing"))
 check(not startup.is_empty() and backend.write_allowed and backend.world_generator==19,"legacy terrain opens with exact generator identity")
 check(backend.native.execute(Codec.command(4)).slice(12)==legacy,"legacy load preserves terrain pages and revision")
 check(backend.submit({"kind":"save"}),"normal asynchronous world save admitted")
 var result:Dictionary=await wait_result(backend,"message")
 print("FORMAT_SAVE ",result)
 check(result.get("success",false),"normal asynchronous world save publishes")
 backend.disable_snapshot_writes();backend.stop()
 var archive=ClassDB.instantiate("NativeWorldArchive")
 var decoded:Dictionary=archive.decode(archive.read(ProjectSettings.globalize_path(path)))
 check(decoded.get("ok",false) and decoded.sections.terrain.decode_u32(4)==3,"actual compound save uses format 3")
 check(FileAccess.get_file_as_bytes(path+".bak")==legacy,"migration retains original raw archive backup")
 backend=open_backend(path)
 check(not (await wait_result(backend,"startup")).is_empty() and backend.write_allowed and backend.world_generator==19,"fresh worker opens new compound save with exact generator identity")
 check(backend.native.execute(Codec.command(4)).slice(12)==legacy,"save and fresh worker reopen preserve exact edited terrain")
 backend.disable_snapshot_writes();backend.stop()
 for suffix in ["",".bak",".lock"]:DirAccess.remove_absolute(path+suffix)
 print("TERRAIN_SAVE_FORMAT failures=",failures);quit(1 if failures else 0)

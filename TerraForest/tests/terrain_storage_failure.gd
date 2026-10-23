# SPDX-License-Identifier: 0BSD
extends SceneTree
const Backend=preload("res://addons/volumetric_terrain/terrain_backend.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
class RejectArchive extends RefCounted:
 var raw:RefCounted
 func encode(sections:Dictionary)->PackedByteArray:return raw.encode(sections)
 func publish(_path:String,_bytes:PackedByteArray)->int:return ERR_FILE_CANT_WRITE
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func write(path:String,b:PackedByteArray)->void:
 var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(b);file.close()
func _initialize()->void:run.call_deferred()
func run()->void:
 var folder:=ProjectSettings.globalize_path("user://terrain_failure_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
 DirAccess.make_dir_recursive_absolute(folder)
 var path:=folder.path_join("world.trw");var archive=ClassDB.instantiate("NativeWorldArchive")
 check(archive.acquire(path),"compound root lease acquired")
 var backend:=Backend.new();backend.native=ClassDB.instantiate("TerrainCore");backend.save_path=path;backend.snapshot_codec=archive
 backend.native.execute(Codec.command(6,[1703,19]));var point:=Vector3(1208,0,1208)
 point.y=backend.native.execute(Codec.point_command(point)).decode_float(12)-0.6
 backend.native.execute(Codec.brush(point,point,2.5,0,false,1))
 var terrain:PackedByteArray=backend.native.execute(Codec.command(4,[3])).slice(12)
 var sections:={"terrain":terrain,"future_addon":PackedByteArray([9,8,7])}
 var first:Dictionary=backend._publish_frozen(sections,terrain,path,archive)
 check(first.success,"production publisher selects terrain checkpoint atomically with addon state")
 var canonical:PackedByteArray=archive.read(path);var decoded:Dictionary=archive.decode(canonical)
 check(decoded.ok and decoded.sections.terrain.size()==40,"actual canonical root contains small terrain reference")
 check(backend._load()=="World loaded" and backend.components.future_addon==sections.future_addon,"production loader expands terrain and preserves unknown addon bytes")
 check(backend.native.execute(Codec.command(4,[3])).slice(12)==terrain,"production restore has exact terrain density and materials")
 check(backend.snapshot_id==first.snapshot_id,"save completion and reopen share checkpoint-bound cache identity")
 var index:=FileAccess.get_file_as_bytes(path+".terrain/"+decoded.sections.terrain.slice(8).hex_encode()+".tindex")
 var at:=40+int(index.decode_u32(24))*4+int(index.decode_u32(28))*8
 var pack_path:=path+".terrain/"+index.slice(at+40,at+72).hex_encode()+".tpack"
 var pack:=FileAccess.get_file_as_bytes(pack_path);var broken:=pack.duplicate();broken[int(index.decode_u32(at+72))]^=1;write(pack_path,broken)
 check(backend._load().begins_with("ERROR: terrain checkpoint") and not backend.write_allowed,"corrupt region blocks startup and further saves")
 check(backend._save().begins_with("ERROR:") and archive.read(path)==canonical,"failed load protects canonical root")
 check(backend.native.execute(Codec.command(4,[3])).slice(12)==terrain,"failed load cannot partially replace native terrain")
 check(not backend._publish_frozen(sections,terrain,path,archive).success and archive.read(path)==canonical,"corrupt inherited dependency aborts publication before root replacement")
 write(pack_path,pack)
 check(DirAccess.rename_absolute(path+".terrain",path+".missing")==OK,"test temporarily removes named sidecar")
 check(backend._load().begins_with("ERROR: terrain checkpoint") and not DirAccess.dir_exists_absolute(path+".terrain"),"missing sidecar fails closed without creating empty storage")
 check(DirAccess.rename_absolute(path+".missing",path+".terrain")==OK and backend._load()=="World loaded","restored exact sidecar permits reopen")
 backend.native.execute(Codec.brush(point-Vector3.UP,point-Vector3.UP,1.5,0,false,1))
 var later:PackedByteArray=backend.native.execute(Codec.command(4,[3])).slice(12)
 var reject:=RejectArchive.new();reject.raw=archive
 check(not backend._publish_frozen({"terrain":later,"future_addon":sections.future_addon},later,path,reject).success and archive.read(path)==canonical,"root publication failure leaves previous checkpoint selected despite staged new pack")
 archive.release()
 var copied:Dictionary=archive.clone_world(folder,"world","copy")
 check(copied.ok,"ordinary native clone includes terrain sidecar")
 var other:Dictionary=archive.decode(archive.read(folder.path_join("copy.trw")))
 check(preload("res://tests/terrain_storage_support.gd").expand(folder.path_join("copy.trw"),other.sections.terrain)==terrain,"cloned world restores the selected checkpoint, excluding unpublished edits")
 for name:String in ["world.trw","copy.trw"]:preload("res://tests/terrain_storage_support.gd").cleanup(folder.path_join(name))
 for file:String in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(file))
 DirAccess.remove_absolute(folder)
 print("TERRAIN_STORAGE_FAILURE failures=",failures);quit(1 if failures else 0)

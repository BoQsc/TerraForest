# SPDX-License-Identifier: 0BSD
extends "res://tests/terrain_generation_staging.gd"
const Backend=preload("res://addons/volumetric_terrain/terrain_backend.gd")
class RejectArchive extends RefCounted:
 var raw:RefCounted
 func encode(sections:Dictionary)->PackedByteArray:return raw.encode(sections)
 func publish(_path:String,_bytes:PackedByteArray)->int:return ERR_FILE_CANT_WRITE
func run()->void:
 var folder:=ProjectSettings.globalize_path("user://generation_handoff_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(folder)
 var path:=folder.path_join("world.trw");var archive:RefCounted=ClassDB.instantiate("NativeWorldArchive")
 check(archive.acquire(path),"unpublished compound root has exclusive owner")
 var packets:Array=[]
 for i in 8:
  var p:=Vector3(64+i*32,128,64);packets.append(Codec.graded_bed(p,p+Vector3(4,0,0),1,1,0,1))
 var backend:=Backend.new();backend.native=fresh();backend.snapshot_codec=archive;backend.disk_cache.enabled=false;backend.save_path=path;backend.world_generator=5
 check(backend.configure_initial_earthworks(packets,"f".repeat(64)) and backend._load()=="New world","production loader performs native staged generation")
 check(backend.native.residency_stats().active and backend._initial_terrain_checkpoint.size()==40 and not FileAccess.file_exists(path),"baked terrain is paged while canonical world remains unpublished")
 var original:=fresh();original.bake_generated_earthworks(packets)
 check(raw(backend.native)==raw(original),"production initialization preserves exact ordinary bake")
 var p:=Vector3(66,128,64);check(Codec.reply_ok(backend.native.execute(Codec.brush(p,p,1,0,false,1))),"additional gameplay edit enters unpublished field")
 var expected:=raw(backend.native);var dirty:int=backend.native.capture_storage_snapshot().stats().dirty_pages
 var denied:=RejectArchive.new();denied.raw=archive;backend.snapshot_codec=denied
 check(backend._save().begins_with("ERROR:") and not FileAccess.file_exists(path) and backend.native.capture_storage_snapshot().stats().dirty_pages==dirty and dirty>0,"failed first outer publication preserves private lineage and unsaved edits")
 backend.snapshot_codec=archive
 check(backend._save().begins_with("World saved and verified") and backend.native.capture_storage_snapshot().stats().dirty_pages==0,"first compound save publishes from private checkpoint then acknowledges")
 var decoded:Dictionary=archive.decode(archive.read(path))
 check(decoded.get("ok",false) and decoded.sections.terrain.size()==40,"canonical archive selects compact final terrain checkpoint")
 var loaded:=Backend.new();loaded.native=fresh();loaded.snapshot_codec=archive;loaded.save_path=path;loaded.disk_cache.enabled=false
 check(loaded._load()=="World loaded" and loaded.native.residency_stats().active and raw(loaded.native)==expected,"ordinary fresh loader restores exact staged terrain and later edit")
 backend=null;loaded=null;original=null;archive.release()
 var copied:Dictionary=archive.clone_world(folder,"world","copy")
 check(copied.get("ok",false),"production world publication copies final staged checkpoint")
 var other:=Backend.new();other.native=fresh();other.snapshot_codec=archive;other.save_path=folder.path_join("copy.trw");other.disk_cache.enabled=false
 check(other._load()=="World loaded" and raw(other.native)==expected,"published destination reopens exact final field")
 other=null;archive=null
 for name:String in ["world.trw","copy.trw"]:preload("res://tests/terrain_storage_support.gd").cleanup(folder.path_join(name))
 for name:String in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(name))
 DirAccess.remove_absolute(folder)
 print("TERRAIN_GENERATION_HANDOFF failures=",failures);quit(1 if failures else 0)

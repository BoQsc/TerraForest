# SPDX-License-Identifier: 0BSD
extends "res://tests/water_region_store.gd"
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Backend=preload("res://addons/volumetric_terrain/terrain_backend.gd")
func write_bytes(path:String,bytes:PackedByteArray)->void:
 var f:=FileAccess.open(path,FileAccess.WRITE);f.store_buffer(bytes);f.close()
func _initialize()->void:
 var folder:=ProjectSettings.globalize_path("user://water_failure_check_"+str(Time.get_ticks_usec()))
 DirAccess.make_dir_recursive_absolute(folder)
 var path:=folder.path_join("world.trw");var archive=ClassDB.instantiate("NativeWorldArchive");check(archive.acquire(path),"isolated archive leased")
 var backend=Backend.new();backend.save_path=path;backend.snapshot_codec=archive;backend.native=ClassDB.instantiate("TerrainCore")
 backend.native.execute(Codec.command(6,[42,19]))
 var terrain:PackedByteArray=backend.native.execute(Codec.command(4)).slice(12)
 var sections:Dictionary={"terrain":terrain,"volumetric_water":packet(125000)}
 var converted:Dictionary=backend._water_storage_sections(sections,path,true)
 check(not converted.is_empty(),"production save adapter creates checkpoint")
 if converted.is_empty():archive.release();quit(1);return
 var canonical:PackedByteArray=archive.encode(converted);check(archive.publish(path,canonical)==OK,"canonical fixture published")
 check(backend._load()=="World loaded" and backend.write_allowed,"production load accepts complete checkpoint")
 var store=ClassDB.instantiate("NativeWaterRegionStore");check(store.open_store(path+".water"),"exclusive sidecar lease acquired")
 backend.write_allowed=true
 check(backend._load().begins_with("ERROR: water checkpoint") and not backend.write_allowed,"competing sidecar owner blocks load and writes")
 check(backend._save().begins_with("ERROR:") and archive.read(path)==canonical,"failed load cannot overwrite canonical save")
 store.close()
 var checkpoint:PackedByteArray=converted.volumetric_water.slice(16,48)
 check(store.open_store(path+".water"),"sidecar inspection opens")
 var page:Dictionary=store.checkpoint_page(checkpoint,0,1);var digest:PackedByteArray=page.digests;store.close()
 var blob_path:=path+".water/"+digest.hex_encode()+".water"
 var original:PackedByteArray=FileAccess.get_file_as_bytes(blob_path)
 write_bytes(blob_path,PackedByteArray([1,2,3]));backend.write_allowed=true
 check(backend._load().begins_with("ERROR: water checkpoint") and not backend.write_allowed,"corrupt blob blocks production load and writes")
 check(archive.read(path)==canonical,"corrupt sidecar leaves canonical bytes unchanged")
 write_bytes(blob_path,original);backend.write_allowed=true
 check(backend._load()=="World loaded","repair of dependency permits exact load")
 var checkpoint_path:=path+".water/"+checkpoint.hex_encode()+".checkpoint"
 var manifest:PackedByteArray=FileAccess.get_file_as_bytes(checkpoint_path)
 check(DirAccess.remove_absolute(checkpoint_path)==OK,"test removes only its own checkpoint")
 backend.write_allowed=true
 check(backend._load().begins_with("ERROR: water checkpoint") and not backend.write_allowed,"missing manifest blocks production load")
 write_bytes(checkpoint_path,manifest)
 # A save-time exclusive lease failure must report failure before outer publication.
 check(store.open_store(path+".water"),"save-failure injection lease acquired")
 var result:Dictionary=backend._publish_frozen(sections,terrain,path,archive)
 check(not result.success and archive.read(path)==canonical,"frozen save failure retains canonical archive")
 store.close();archive.release()
 print("WATER_STORAGE_FAILURE failures=",failures);quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
 for addon in ["world_runtime","volumetric_water"]:
  var type_name:="NativeWorldArchive" if addon=="world_runtime" else "NativeWaterRegionStore"
  if not ClassDB.class_exists(type_name):GDExtensionManager.load_extension("res://addons/"+addon+"/"+addon+".gdextension")
 run.call_deferred()
func run()->void:
 var source:=""
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--water-fixture="):source=arg.trim_prefix("--water-fixture=")
 if not source.begins_with("StartupBench_") or not source.is_valid_identifier():quit(2);return
 var path:="user://worlds/"+source+".trw"
 var before:=FileAccess.get_sha256(path)
 var archive=ClassDB.instantiate("NativeWorldArchive")
 var root:Dictionary=archive.decode(archive.read(ProjectSettings.globalize_path(path)))
 if not root.get("ok",false):quit(2);return
 var original:PackedByteArray=root.sections.volumetric_water
 var folder:=ProjectSettings.globalize_path("user://generated_water_packs_"+Crypto.new().generate_random_bytes(8).hex_encode())
 var store=ClassDB.instantiate("NativeWaterRegionStore")
 check(store.open_store(folder),"isolated region store opens")
 var packed:PackedByteArray=store.pack_generated_snapshot(original)
 check(packed.size()>80 and packed.size()<4096,"generated world uses a small root reference")
 check(store.unpack_generated_snapshot(packed)==original,"all ordinary lake quantities, contacts and flags roundtrip byte-exactly")
 check(store.expand_water_snapshot(packed)==original,"generation verifier and map certificate adapter decode new format")
 check(store.pack_generated_snapshot(original)==packed,"repeat publication has stable identity")
 var empty:PackedByteArray=ClassDB.instantiate("NativeRegionalWater").capture_snapshot(ClassDB.instantiate("NativeLakeCatalog").encode([]))
 check(store.unpack_generated_snapshot(store.pack_generated_snapshot(empty))==empty,"empty world keeps an explicit valid catalog")
 check(store.pack_generated_snapshot(PackedByteArray([1,2,3])).is_empty(),"invalid input cannot publish a root")
 store.close();store=ClassDB.instantiate("NativeWaterRegionStore")
 check(store.open_store(folder) and store.unpack_generated_snapshot(packed)==original,"fresh store reopens the immutable packs")
 var broken:=packed.duplicate();broken.encode_u64(8,1)
 check(store.unpack_generated_snapshot(broken).is_empty(),"malformed root rejected")
 broken=packed.duplicate();broken[48]^=1
 check(store.unpack_generated_snapshot(broken).is_empty(),"full reconstructed snapshot identity checked")
 var files:=DirAccess.get_files_at(folder);var damaged:=""
 for name:String in files:
  if name.ends_with(".wpack"):damaged=folder.path_join(name);break
 if not damaged.is_empty():
  var bytes:=FileAccess.get_file_as_bytes(damaged)
  var corrupt:=bytes.duplicate();corrupt[0]^=1
  var file:=FileAccess.open(damaged,FileAccess.WRITE);file.store_buffer(corrupt);file.close()
  check(store.unpack_generated_snapshot(packed).is_empty(),"corrupt distant region pack fails closed")
  file=FileAccess.open(damaged,FileAccess.WRITE);file.store_buffer(bytes);file.close()
  check(store.unpack_generated_snapshot(packed)==original,"restoring exact pack recovers without changing the root")
 store.close()
 check(FileAccess.get_sha256(path)==before,"source world remains byte-identical")
 print("GENERATED_WATER_PACKS failures=",failures," root_bytes=",packed.size()," original_bytes=",original.size()," store=",folder)
 quit(0 if failures==0 else 1)

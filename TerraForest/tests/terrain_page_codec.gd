# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func seal(bytes:PackedByteArray)->PackedByteArray:
 var h:=2166136261
 for i in range(bytes.size()-4):h=((h^bytes[i])*16777619)&0xffffffff
 bytes.encode_u32(bytes.size()-4,h);return bytes
func fixture(kind:int)->PackedByteArray:
 var bytes:=PackedByteArray();bytes.resize(36+12292);bytes.fill(0)
 bytes.encode_u32(0,0x32575254);bytes.encode_u32(4,2);bytes.encode_u32(8,42);bytes.encode_u32(12,1);bytes.encode_u32(20,1);bytes.encode_u32(24,1);bytes.encode_u32(28,5);bytes.encode_u32(32,1+16+126*(16+126*2))
 var random:=42
 for i in range(4096):
  random=(random*1664525+1013904223)&0xffffffff
  var density:int=1234 if kind==0 else ((random>>8)&65535 if kind==1 else i%64)
  bytes.encode_u16(36+i*2,density);bytes[36+8192+i]=3 if kind==0 else ((random>>24)&255 if kind==1 else i%7)
 return seal(bytes)
func _initialize()->void:
 var folder:=ProjectSettings.globalize_path("user://terrain_codec_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
 var store=ClassDB.instantiate("NativeTerrainRegionStore");check(store.open_store(folder,true),"isolated codec store opens")
 var encodings:Array=[]
 for kind in range(3):
  var native=ClassDB.instantiate("TerrainCore");var command:=Codec.command(5);command.append_array(fixture(kind))
  check(Codec.reply_ok(native.execute(command)),"independently framed legacy fixture is accepted by authoritative reader %d"%kind)
  var expected:PackedByteArray=native.execute(Codec.command(4,[3])).slice(12)
  var reference:PackedByteArray=store.publish_snapshot(expected)
  check(not reference.is_empty() and store.expand_snapshot(reference)==expected,"lossless codec preserves all density and material bytes %d"%kind)
  var index:=FileAccess.get_file_as_bytes(folder.path_join(reference.slice(8).hex_encode()+".tindex"))
  var pack:=FileAccess.get_file_as_bytes(folder.path_join(index.slice(84,116).hex_encode()+".tpack"))
  var offset:=int(index.decode_u32(116));encodings.append(pack.decode_u32(offset+20))
 check(encodings==[1,0,2],"constant, high entropy and patterned fields exercise runs, raw fallback and FastLZ")
 store.close()
 for file:String in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(file))
 DirAccess.remove_absolute(folder)
 print("TERRAIN_PAGE_CODEC failures=",failures," encodings=",encodings);quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
 var baseline:="";var candidate:=""
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--baseline-world="):baseline=arg.trim_prefix("--baseline-world=")
  if arg.begins_with("--candidate-world="):candidate=arg.trim_prefix("--candidate-world=")
 var launch=preload("res://demo/world_launch.gd")
 if not launch.valid_slot(baseline) or not launch.valid_slot(candidate):quit(2);return
 var archive=ClassDB.instantiate("NativeWorldArchive")
 var a:Dictionary=archive.decode(FileAccess.get_file_as_bytes("user://worlds/"+baseline+".trw"))
 var b:Dictionary=archive.decode(FileAccess.get_file_as_bytes("user://worlds/"+candidate+".trw"))
 var failures:=0
 if not a.get("ok",false) or not b.get("ok",false):failures+=1
 else:
  var helper=preload("res://tests/terrain_storage_support.gd")
  var codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
  var left=ClassDB.instantiate("TerrainCore");var right=ClassDB.instantiate("TerrainCore")
  var command:=codec.command(5);command.append_array(helper.expand("user://worlds/"+baseline+".trw",a.sections.terrain))
  var other:=codec.command(5);other.append_array(helper.expand("user://worlds/"+candidate+".trw",b.sections.terrain))
  var terrain_equal:bool=codec.reply_ok(left.execute(command)) and codec.reply_ok(right.execute(other)) and left.execute(codec.command(4))==right.execute(codec.command(4))
  if not terrain_equal:failures+=1
  print("SAVED_TERRAIN_EQUAL ",terrain_equal)
  var left_structures:=expanded_structures(baseline,a.sections.structures)
  var right_structures:=expanded_structures(candidate,b.sections.structures)
  var structures_equal:bool=not left_structures.is_empty() and left_structures==right_structures
  if not structures_equal:failures+=1
  print("SAVED_STRUCTURES_EQUAL ",structures_equal)
  var left_water:=expanded_water(baseline,a.sections.volumetric_water)
  var right_water:=expanded_water(candidate,b.sections.volumetric_water)
  var water:Dictionary=compare_water(left_water,right_water)
  if not water.ok:failures+=1
  print("SAVED_WATER_EQUIVALENCE ",JSON.stringify(water))
 print("GENERATION_SAVED_EQUIVALENCE failures=",failures)
 quit(1 if failures else 0)

func expanded_structures(slot:String,bytes:PackedByteArray)->PackedByteArray:
 var codec=ClassDB.instantiate("NativeStructuresSnapshot")
 var reference:Dictionary=codec.inspect_reference(bytes)
 if not reference.get("ok",false) or not codec.configure_assets(PackedStringArray(reference.models.keys())):return PackedByteArray()
 var adapter=ClassDB.instantiate("NativeRegionWorldArchive")
 var raw=ClassDB.instantiate("NativeWorldArchive")
 var path:=ProjectSettings.globalize_path("user://worlds/"+slot+".trw")
 if not adapter.configure(raw,codec) or not adapter.acquire(path):return PackedByteArray()
 var decoded:Dictionary=adapter.decode(adapter.read(path));adapter.release()
 return decoded.sections.structures if decoded.get("ok",false) else PackedByteArray()

func expanded_water(slot:String,bytes:PackedByteArray)->PackedByteArray:
 var store=ClassDB.instantiate("NativeWaterRegionStore")
 if not store.open_store(ProjectSettings.globalize_path("user://worlds/"+slot+".trw.water")):return PackedByteArray()
 var result:PackedByteArray=store.expand_water_snapshot(bytes);store.close()
 return result

func water_records(bytes:PackedByteArray)->Dictionary:
 # Decode only the native-validated v13 fixture format, including every contact,
 # structure and vacancy byte. Unknown versions fail this comparison closed.
 if bytes.size()<32 or bytes.decode_u32(0)!=0x31575256 or bytes.decode_u32(4)!=13:return {}
 var start:=32+bytes.decode_u32(8);var rows:Dictionary={};var keys:Array=[]
 for n in bytes.decode_u32(12):
  var record:=bytes.slice(start+n*9076,start+(n+1)*9076);var key:=record.decode_u64(0)
  rows[key]={"record":record};keys.append(key)
 var offset:=start+keys.size()*9076
 for key in keys:
  start=offset;var present:=bytes.decode_u32(offset);offset+=4
  if present:
   for cell in 512:
    var count:=bytes.decode_u32(offset);offset+=4+count*36
  rows[key].contacts=bytes.slice(start,offset)
 for key in keys:
  start=offset;var count:=bytes.decode_u32(offset);offset+=4
  for cell in count:
   var size:=bytes.decode_u32(offset+4);offset+=8+size*8
  rows[key].structures=bytes.slice(start,offset)
 for key in keys:
  start=offset;var count:=bytes.decode_u32(offset);offset+=4+count*8
  rows[key].vacancies=bytes.slice(start,offset)
 return rows if offset==bytes.size() else {}

func empty_ocean_cap(row:Dictionary)->bool:
 # Streaming/building invalidation can retain additional empty ocean caps.
 # y >= 40 m is above the native sea surface. Never ignore wet regions,
 # removed-water vacancies, pending edits/settling, or lower ocean overrides.
 var bytes:PackedByteArray=row.record
 if bytes.decode_u32(8)!=1 or bytes.decode_u32(12)!=9 or ((bytes.decode_u64(0)>>12)&4095)<10 or row.vacancies!=PackedByteArray([0,0,0,0]):return false
 for cell in 512:
  if bytes.decode_u64(20+cell*12)!=0:return false
 return true

func compare_water(a:PackedByteArray,b:PackedByteArray)->Dictionary:
 var exact:bool=not a.is_empty() and a==b
 var result:Dictionary={"ok":exact,"raw_bytes_equal":exact,"empty_ocean_caps_before":[],"empty_ocean_caps_after":[]}
 if exact:return result
 var aa:=water_records(a);var bb:=water_records(b)
 if aa.is_empty() or bb.is_empty() or a.decode_u64(16)!=b.decode_u64(16) or a.slice(32,32+a.decode_u32(8))!=b.slice(32,32+b.decode_u32(8)):return result
 for key in aa:
  if bb.has(key):
   if aa[key]!=bb[key]:return result
  else:
   if not empty_ocean_cap(aa[key]):return result
   result.empty_ocean_caps_before.append(key)
 for key in bb:
  if not aa.has(key):
   if not empty_ocean_cap(bb[key]):return result
   result.empty_ocean_caps_after.append(key)
 result.ok=true;return result

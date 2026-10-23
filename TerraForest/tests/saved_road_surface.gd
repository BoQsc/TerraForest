# SPDX-License-Identifier: 0BSD
extends "res://tests/road_vegetation.gd"
func run()->void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
 var slot:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
 if not slot.is_valid_identifier():quit(2);return
 var archive=ClassDB.instantiate("NativeWorldArchive")
 var decoded:Dictionary=archive.decode(FileAccess.get_file_as_bytes("user://worlds/"+slot+".trw"))
 if not decoded.get("ok",false):quit(2);return
 var payload:PackedByteArray=preload("res://tests/terrain_storage_support.gd").expand("user://worlds/"+slot+".trw",decoded.sections.terrain)
 var core=ClassDB.instantiate("TerrainCore");var command:=Codec.command(5);command.append_array(payload)
 check(Codec.reply_ok(core.execute(command)),"saved terrain restores")
 var seed_value:int=payload.decode_u32(8);var generator:int=payload.decode_u32(28)
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,generator)
 print("ROAD_IDENTITY ",seed_value," ",generator," ",layout.sites)
 for road:Dictionary in layout.roads:
  var a:Vector3=layout.sites[road.from].position;var b:Vector3=layout.sites[road.to].position
  var direction:Vector3=b-a;direction.y=0;direction=direction.normalized()
  var side:=Vector3(-direction.z,0,direction.x)
  for lane in [-0.6,0.0,0.6]:
   var points:=PackedVector3Array()
   for i in range(1,20):points.append(a.lerp(b,float(i)/20)+side*float(road.half_width)*lane)
   var sampled:=sample(core,points)
   check(not sampled.is_empty() and sampled.normals.count(Vector3.ZERO)==points.size(),"saved arterial %d lane %s rejects vegetation roots"%[road.to,str(lane)])
 print("SAVED_ROAD_SURFACE failures=",failures);quit(1 if failures else 0)

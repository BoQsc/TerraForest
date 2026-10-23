# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func run()->void:
 var slot:="workflow_66068_179427"
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--profile-world="):slot=arg.trim_prefix("--profile-world=")
 if not slot.is_valid_identifier():quit(2);return
 var path:=ProjectSettings.globalize_path("user://worlds/"+slot+".trw")
 var archive:RefCounted=ClassDB.instantiate("NativeWorldArchive")
 var original:PackedByteArray=archive.read(path)
 var world:Dictionary=archive.decode(original)
 if not check(world.get("ok",false),"profile source opens read-only"):quit(1);return
 var core:RefCounted=ClassDB.instantiate("TerrainCore")
 if not check(core.mount_storage_checkpoint(path+".terrain",world.sections.terrain),"profile field mounts native paging"):quit(1);return
 core.execute(Codec.command(18,[1]))
 var workload:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence/terrain_residency/mining/held_mining_flight.json"))
 var rows:Array=[]
 for phase:Dictionary in workload.phases:
  for record:Dictionary in phase.edits.slice(0,5):
   var d:Dictionary=record.descriptor
   var a:=Vector3(d.a[0],d.a[1],d.a[2]);var b:=Vector3(d.b[0],d.b[1],d.b[2])
   var began:=Time.get_ticks_usec();var edited:PackedByteArray=core.execute(Codec.brush(a,b,d.radius,0,d.add,1));var field_us:=Time.get_ticks_usec()-began
   check(Codec.reply_ok(edited),"recorded edit accepted")
   var size:=256 if phase.phase=="held_flight_0" else 128
   var x:=floori(b.x/size)*size;var z:=floori(b.z/size)*size
   var before:Dictionary=core.residency_stats()
   began=Time.get_ticks_usec();var packet:PackedByteArray=core.execute(Codec.command(1,[x,z,size,size/32,0]));var wall_us:=Time.get_ticks_usec()-began
   var stages:PackedByteArray=core.execute(Codec.command(19));var timings:Array=[]
   for i in 4:timings.append(stages.decode_float(12+i*4))
   var after:Dictionary=core.residency_stats()
   check(Codec.reply_ok(packet),"edited mesh builds")
   var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(packet)
   rows.append({"phase":phase.phase,"key":[x,z,size],"a":a,"b":b,"field_us":field_us,"wall_us":wall_us,"native_ms":timings,"page_faults":after.faults-before.faults,"page_fault_us":after.profiled_fault_us-before.profiled_fault_us,"triangles":packet.decode_u32(44)/3 if packet.size()>48 else -1,"packet_sha256":digest.finish().hex_encode()})
 check(archive.read(path)==original,"profile leaves saved world unchanged")
 FileAccess.open("res://reports/terrain_mining_stage_profile.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rows":rows,"scope":"Native replay of actual held-mining edit descriptors with the observed 256m/128m coarse owners; extraction/simplify/blocks/shading and measured successful cold page faults. Not full UI or latency acceptance."},"  "))
 print("TERRAIN_MINING_STAGE_PROFILE failures=",failures);quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends "res://tests/terrain_generation_staging.gd"
func hit(core:RefCounted,command:PackedByteArray)->Dictionary:
 var value:=Codec.decode_density_ray(core.execute(command));value.erase("revision");return value
func run()->void:
 var path:=ProjectSettings.globalize_path("user://generation_capacity_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
 var packets:Array=[];var probes:Array=[]
 for i in 2112:
  var p:=Vector3(64+(i%60)*32,128,64+(i/60)*32)
  var packet:=Codec.graded_bed(p,p+Vector3(4,0,0),1,1,0,1);packets.append(packet)
  if i%64==0 or i==2111:
   var local:=fresh();check(Codec.reply_ok(local.execute(packet)),"independent grade reference")
   var ray:=Codec.density_ray_command(p+Vector3(1,4,0),p+Vector3(1,-4,0),512,0,true)
   probes.append({"ray":ray,"hit":hit(local,ray)});local=null
 var core:=fresh();var result:Dictionary=core.bake_generated_earthworks_staged(packets,path,1024,96)
 var stats:Dictionary=core.residency_stats()
 check(result.get("ok",false) and result.get("completed")==2112 and stats.catalog_pages>16384,"one native generation job authors beyond the former history cap")
 if not result.get("ok",false):print(result);quit(1);return
 check(result.resident_high<=1024 and result.capture_sample_bytes_high<=1024*12288 and stats.evictions>0,"bake samples and immutable capture payload stay bounded")
 var store:RefCounted=ClassDB.instantiate("NativeTerrainRegionStore");check(store.open_store(path,false),"large staging data opens read-only")
 check(store.verify_snapshot(result.checkpoint).get("ok",false),"complete generated checkpoint verifies")
 var cold:=fresh();check(cold.mount_storage_checkpoint(path,result.checkpoint,32),"large baked field cold mounts with only 32 resident pages")
 var exact:=true
 for probe:Dictionary in probes:exact=exact and probe.hit.get("status")=="hit" and hit(cold,probe.ray)==probe.hit
 check(exact and cold.residency_stats().resident_high<=32,"34 distributed earliest/latest probes retain exact independent grade hits and normals")
 result.erase("checkpoint")
 FileAccess.open("res://reports/terrain_generation_capacity.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"bake":result,"runtime":stats,"cold":cold.residency_stats(),"scope":"One native staged generation job: 2112 grading commands / 16896 authored pages; 1024-page resident and capture bounds, full product validation and 34 independent cold density/normal references. No rendered world/FPS or universal capacity proof."},"  "))
 core=null;cold=null;store.close();store=null;clear_store(path)
 print("TERRAIN_GENERATION_CAPACITY failures=",failures);quit(1 if failures else 0)

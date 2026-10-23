# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func same_hit(a:PackedByteArray,b:PackedByteArray)->bool:
 var left:=Codec.decode_density_ray(a);var right:=Codec.decode_density_ray(b)
 left.erase("revision");right.erase("revision")
 return left.get("status")=="hit" and left==right
func run()->void:
 var started:=Time.get_ticks_usec()
 var path:=ProjectSettings.globalize_path("user://terrain_capacity_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
 var store:RefCounted=ClassDB.instantiate("NativeTerrainRegionStore");check(store.open_store(path,true),"capacity store opens")
 var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,5]))
 var capture=core.capture_storage_snapshot();var reference:PackedByteArray=store.publish_capture(capture)
 check(reference.size()==40 and core.mount_storage_checkpoint(path,reference,1024),"empty field mounts bounded pager")
 var first_ray:=PackedByteArray();var last_ray:=PackedByteArray();var first_reply:=PackedByteArray();var last_reply:=PackedByteArray()
 var probes:Array[Dictionary]=[]
 var peak:=0;var completed:=0
 for batch in 22:
  for j in 96:
   var i:=batch*96+j
   var p:=Vector3(64+(i%60)*32,128,64+(i/60)*32)
   var reply:PackedByteArray=core.execute(Codec.brush(p,p,1,1,true,1))
   if not Codec.reply_ok(reply):failures+=1;print("FAIL edit ",i," ",core.residency_stats());break
   if i==0:
    first_ray=Codec.density_ray_command(p+Vector3.UP*4,p-Vector3.UP*4,512,0,true);first_reply=core.execute(first_ray)
   last_ray=Codec.density_ray_command(p+Vector3.UP*4,p-Vector3.UP*4,512,0,true);last_reply=core.execute(last_ray)
   if i%64==0:probes.append({"ray":last_ray,"reply":last_reply})
   completed+=1
  peak=maxi(peak,core.residency_stats().resident_pages)
  capture=core.capture_storage_snapshot()
  var next:PackedByteArray=store.publish_capture(capture,reference)
  if next.size()!=40 or not core.commit_storage_snapshot(capture,next):failures+=1;print("FAIL checkpoint ",batch);break
  reference=next
  if failures:break
  await process_frame
 var stats:Dictionary=core.residency_stats()
 check(completed==2112 and stats.catalog_pages>16384,"authored history grows beyond former 16384-page capacity")
 check(peak<=1024 and stats.resident_pages<=1024 and stats.evictions>0,"resident samples remain capped at 1024 through growth")
 check(same_hit(core.execute(first_ray),first_reply) and same_hit(core.execute(last_ray),last_reply),"earliest and latest placed fields retain identical hits and normals")
 var last_key:Dictionary=core.geometry_cache_key(64,64,16,1)
 var fresh:RefCounted=ClassDB.instantiate("TerrainCore")
 check(fresh.mount_storage_checkpoint(path,reference,32),"fresh process owner mounts history beyond old cap with 32 resident pages")
 check(same_hit(fresh.execute(first_ray),first_reply) and same_hit(fresh.execute(last_ray),last_reply) and fresh.geometry_cache_key(64,64,16,1).get("key")==last_key.get("key"),"cold distant density and mesh-content identity retained")
 var distributed:=true
 for probe:Dictionary in probes:distributed=distributed and same_hit(fresh.execute(probe.ray),probe.reply)
 check(distributed and fresh.residency_stats().resident_pages<=32,"33 distributed cold probes preserve exact edits under the 32-page bound")
 check(store.verify_snapshot(reference).get("ok",false) and fresh.capture_storage_snapshot().stats().dirty_pages==0,"large checkpoint verifies and unchanged capture has no sample copy")
 var report:={"failures":failures,"completed":completed,"milliseconds":(Time.get_ticks_usec()-started)/1000.0,"peak_resident_pages":peak,"runtime":stats,"reopened":fresh.residency_stats(),"storage":store.stats(),"scope":"2112 independent native field additions with periodic durable checkpoints, history beyond 16384 pages, bounded LRU, cold density/normal/content parity; no renderer/FPS or thermal qualification."}
 FileAccess.open("res://reports/terrain_residency_capacity.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 core=null;fresh=null;capture=null;store.close();store=null
 for name:String in DirAccess.get_files_at(path):DirAccess.remove_absolute(path.path_join(name))
 DirAccess.remove_absolute(path)
 print("TERRAIN_RESIDENCY_CAPACITY failures=",failures);quit(1 if failures else 0)

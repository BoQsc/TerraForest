# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func raw(core:RefCounted)->PackedByteArray:
 var reply:PackedByteArray=core.execute(Codec.command(4,[3]));return reply.slice(12) if Codec.reply_ok(reply) else PackedByteArray()
func run()->void:
 var path:=ProjectSettings.globalize_path("user://terrain_residency_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
 var original:RefCounted=ClassDB.instantiate("TerrainCore");original.execute(Codec.command(6,[1703,19]))
 var points:Array[Vector3]=[]
 for i in 96:
  var p:=Vector3(128+(i%12)*128,0,256+(i/12)*128);p.y=original.execute(Codec.point_command(p)).decode_float(12)-1
  points.append(p)
  if not Codec.reply_ok(original.execute(Codec.brush(p,p,2.5,0,false,1))):failures+=1
 var expected:=raw(original)
 var store:RefCounted=ClassDB.instantiate("NativeTerrainRegionStore");check(store.open_store(path,true),"checkpoint store opens")
 var capture=original.capture_storage_snapshot();var reference:PackedByteArray=store.publish_capture(capture)
 check(reference.size()==40 and original.commit_storage_snapshot(capture,reference),"source checkpoint committed")
 var core:RefCounted=ClassDB.instantiate("TerrainCore")
 check(core.mount_storage_checkpoint(path,reference,16),"native field mounts verified checkpoint without expansion")
 check(core.residency_stats().resident_pages==0 and core.residency_stats().catalog_pages>16,"mount keeps catalog and zero sample pages")
 var exact:=true
 for p:Vector3 in points:
  var ray:=Codec.density_ray_command(p+Vector3.UP*8,p-Vector3.UP*8,512,0,true)
  exact=exact and core.execute(ray)==original.execute(ray)
 check(exact,"all distributed density hits and normals match original terrain exactly")
 var mesh_parity:=true
 for point:Vector3 in points.slice(0,3):
  var command:=Codec.command(1,[floori(point.x/16)*16,floori(point.z/16)*16,16,2])
  mesh_parity=mesh_parity and core.execute(command)==original.execute(command)
 check(mesh_parity,"paged meshes retain exact topology materials normals and lighting")
 var stats:Dictionary=core.residency_stats()
 check(stats.resident_pages<=16 and stats.evictions>0 and stats.eviction_scan_high<=16,"read residency and eviction work stay bounded independently of history")
 check(core.capture_storage_snapshot().stats().sample_bytes==0,"cold unchanged capture loads no samples")
 check(raw(core)==expected,"paged traversal serializes byte-exact original field")
 var p:Vector3=points[0]-Vector3.UP
 check(Codec.reply_ok(core.execute(Codec.brush(p,p,2.0,0,false,1))),"edit faults and pins touched pages")
 var local=core.capture_storage_snapshot();var changed_raw:=raw(core)
 check(local.stats().dirty_pages>0 and local.stats().dirty_pages<=16,"local dirty samples remain pinned")
 var next:PackedByteArray=store.publish_capture(local,reference)
 check(next.size()==40 and store.expand_snapshot(next)==changed_raw,"incremental save merges evicted history exactly")
 check(Codec.reply_ok(core.execute(Codec.brush(p-Vector3.UP,p-Vector3.UP,2.0,0,false,1))),"newer edit occurs during frozen publication")
 check(core.commit_storage_snapshot(local,next) and core.capture_storage_snapshot().stats().dirty_pages>0,"older publication leaves newer resident samples dirty and pinned")
 check(core.mount_storage_checkpoint(path,next,16) and raw(core)==changed_raw,"fresh paged reopen retains edit and distant history")
 # Admission failure cannot expose any partially changed density/material values.
 var before:=raw(core)
 var rejected:PackedByteArray=core.execute(Codec.brush(points[0],points[0],40,0,false,1))
 check(not Codec.reply_ok(rejected) and raw(core)==before,"oversized pinned edit is rejected atomically at resident budget")
 check(core.residency_stats().resident_pages<=16,"rejected allocation preserves resident bound")
 # A page fault must report damaged authoritative storage, never regenerate the
 # original base field. Mount itself must also preserve the prior world on failure.
 var damaged:RefCounted=ClassDB.instantiate("TerrainCore")
 check(damaged.mount_storage_checkpoint(path,next,16),"cold corruption fixture mounts exact saved checkpoint")
 var backups:Dictionary={}
 for name:String in DirAccess.get_files_at(path):
  if not name.ends_with(".tpack"):continue
  var target:=path.path_join(name);var source_bytes:=FileAccess.get_file_as_bytes(target);backups[target]=source_bytes
  var broken:=source_bytes.duplicate();broken[0]^=1;var file:=FileAccess.open(target,FileAccess.WRITE);file.store_buffer(broken);file.close()
 var failed_read:PackedByteArray=damaged.execute(Codec.command(4,[3]))
 check(not Codec.reply_ok(failed_read),"damaged cold dependency fails the native read instead of returning base terrain")
 check(not Codec.reply_ok(damaged.execute(Codec.density_ray_command(points[0]+Vector3.UP*8,points[0]-Vector3.UP*8,512,0,true))),"damaged cold density query reports an error instead of a plausible hit")
 check(not core.mount_storage_checkpoint(path,next,16),"damaged checkpoint cannot replace live native world")
 for target:String in backups:
  var file:=FileAccess.open(target,FileAccess.WRITE);file.store_buffer(backups[target]);file.close()
 check(raw(core)==before,"rejected mount leaves original field and page catalog unchanged")
 check(raw(damaged)==before,"restoring exact immutable products permits the failed page fault to recover")
 var report:={"failures":failures,"catalog_pages":core.residency_stats().catalog_pages,"read_travel":stats,"final":core.residency_stats(),"scope":"Native cold mount, exact density/normal traversal, bounded sample residency, dirty-page pinning, incremental save and rejected-edit rollback. Production integration and beyond-16384 history still required."}
 FileAccess.open("res://reports/terrain_residency.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 core=null;damaged=null;original=null;store.close();store=null
 for name:String in DirAccess.get_files_at(path):DirAccess.remove_absolute(path.path_join(name))
 DirAccess.remove_absolute(path)
 print("TERRAIN_RESIDENCY failures=",failures);quit(1 if failures else 0)

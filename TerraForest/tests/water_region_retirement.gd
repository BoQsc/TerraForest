# SPDX-License-Identifier: 0BSD
extends "res://tests/water_region_io.gd"
func publish_meshes(water:RefCounted)->bool:
 for i in 128:
  var batch:Dictionary=water.next_mesh_batch()
  if batch.is_empty():return true
  if batch.get("complete",false) and not water.commit_mesh_batch(batch.batch):return false
 return false
func run()->void:
 var folder:=ProjectSettings.globalize_path("user://water_retirement_"+str(Time.get_ticks_usec()))
 var store=ClassDB.instantiate("NativeWaterRegionStore");check(store.open_store(folder),"store opens")
 var io=ClassDB.instantiate("NativeWaterRegionIO");check(io.configure(store,1,8*1024*1024),"bounded worker starts")
 var water=ClassDB.instantiate("NativeRegionalWater");var p:=Vector3i(1,9,250);var data:PackedByteArray=packet(125000)
 check(water.restore_region_snapshot(p,data,0,true),"resident fixture")
 check(publish_meshes(water) and water.statistics().query_cache_bytes>0,"initial render and pick geometry published")
 check(not water.retire_region(ClassDB.instantiate("NativeWaterRegionReceipt"),water.survey_revision_id()),"unverified receipt cannot release data")
 var revision:int=water.survey_revision_id()
 check(io.request_write(p,data,0)>0,"snapshot submitted")
 var reply:Dictionary=await receive(io)
 check(reply.get("ok",false) and reply.has("receipt"),"worker supplies verified receipt")
 if not reply.get("ok",false):io.close();store.close();quit(1);return
 check(water.brush(Vector3(4.25,36.25,1000.25),0.1,-1000)==1000,"edit after capture")
 var newer:PackedByteArray=water.capture_region_snapshot(p)
 check(not water.retire_region(reply.receipt,revision),"stale revision rejected")
 check(not water.retire_region(reply.receipt,water.survey_revision_id()) and water.capture_region_snapshot(p)==newer,"stale packet rejected even with current revision")
 check(io.request_write(p,newer,0)>0,"newer snapshot submitted")
 reply=await receive(io)
 var checkpoint:Dictionary=store.publish_checkpoint(PackedInt32Array([1,9,250]),[reply.digest])
 check(checkpoint.ok,"checkpoint owns saved version")
 check(water.retire_region(reply.receipt,water.survey_revision_id()),"verified unchanged region retires")
 var stats:Dictionary=water.statistics()
 check(stats.regions==0 and stats.deferred_regions==1 and stats.water_ml==0 and stats.resident_cell_bytes==0 and stats.dirty_meshes>0,"retirement releases cells and schedules coherent mesh removal")
 check(publish_meshes(water) and water.statistics().query_cache_bytes==0,"retirement publication clears stale picking geometry")
 check(not water.retire_region(reply.receipt,water.survey_revision_id()),"receipt cannot release region twice")
 var page:Dictionary=water.deferred_region_page(0,1)
 check(page.digests==reply.digest and page.coordinates==PackedInt32Array([1,9,250]),"deferred identity matches durable bytes")
 check(io.request_read(checkpoint.checkpoint,p,0)>0,"reload submitted")
 var loaded:Dictionary=await receive(io)
 check(water.restore_region_snapshot(p,loaded.packet,water.survey_revision_id(),true) and water.capture_region_snapshot(p)==newer,"reload restores exact edited packet")
 check(water.statistics().water_ml==124000 and water.statistics().deferred_regions==0,"reload restores exact quantity once")
 # Empty ownership must survive the same path; it suppresses procedural sea.
 water.brush(Vector3(4.25,36.25,1000.25),0.1,-1000000)
 var empty:PackedByteArray=water.capture_region_snapshot(p);reply=store.publish_region(p,empty)
 check(water.retire_region(reply.receipt,water.survey_revision_id()) and water.statistics().deferred_regions==1,"empty edited region retains ownership on retirement")
 check(water.restore_region_snapshot(p,empty,water.survey_revision_id(),true) and water.statistics().water_ml==0,"empty override reload remains dry")
 io.close();store.close()
 check(not store.publish_region(p,empty).has("receipt"),"failed write cannot issue retirement receipt")
 print("WATER_REGION_RETIREMENT failures=",failures);quit(1 if failures else 0)

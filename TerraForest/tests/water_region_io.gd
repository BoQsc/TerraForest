# SPDX-License-Identifier: 0BSD
extends "res://tests/water_region_store.gd"
func _initialize()->void:run.call_deferred()
func receive(io:RefCounted)->Dictionary:
 var end:=Time.get_ticks_msec()+5000
 while Time.get_ticks_msec()<end:
  var reply:Dictionary=io.poll()
  if not reply.is_empty():return reply
  await process_frame
 return {}
func run()->void:
 var folder:=ProjectSettings.globalize_path("user://water_io_check_"+str(Time.get_ticks_usec()))
 var store=ClassDB.instantiate("NativeWaterRegionStore");check(store.open_store(folder),"isolated store opens")
 var io=ClassDB.instantiate("NativeWaterRegionIO")
 check(io.configure(store,1,8*1024*1024),"bounded worker starts")
 var p:=Vector3i(1,9,250);var bytes:PackedByteArray=packet(125000)
 var ticket:int=io.request_write(p,bytes,0);check(ticket>0,"write queued")
 check(io.request_write(p,bytes,0)==0,"request limit includes unconsumed completion")
 var written:Dictionary=await receive(io)
 check(written.get("ok",false) and written.get("ticket",0)==ticket,"worker returns durable write acknowledgement")
 if not written.get("ok",false):io.close();store.close();quit(1);return
 var checkpoint:Dictionary=store.publish_checkpoint(PackedInt32Array([1,9,250]),[written.digest])
 ticket=io.request_read(checkpoint.checkpoint,p,0)
 check(ticket>0 and io.stats().reserved_bytes==8*1024*1024,"read reserves maximum bounded result")
 check(io.request_read(checkpoint.checkpoint,p,0)==0,"read backpressure rejects excess work")
 var read:Dictionary=await receive(io)
 check(read.get("ok",false) and read.get("packet",PackedByteArray())==bytes,"asynchronous checkpoint read returns exact packet")
 check(io.stats().reserved_bytes==0 and io.stats().outstanding==0,"poll releases reservations")
 check(io.request_read(checkpoint.checkpoint,p,0)>0 and io.cancel_epoch(1),"world transition cancels outstanding epoch")
 var end:=Time.get_ticks_msec()+5000
 while io.stats().outstanding>0 and Time.get_ticks_msec()<end:await process_frame
 check(io.poll().is_empty() and io.stats().outstanding==0,"stale queued or completed results never publish")
 check(io.request_read(checkpoint.checkpoint,p,0)==0,"old epoch submissions rejected")
 check(io.request_read(checkpoint.checkpoint,p,1)>0,"new epoch accepts work")
 read=await receive(io);check(read.get("ok",false) and read.get("epoch",-1)==1,"new epoch completion tagged")
 var missing:PackedByteArray=checkpoint.checkpoint.duplicate();missing[0]^=1
 check(io.request_read(missing,p,1)>0,"failed I/O admitted as bounded job")
 read=await receive(io);check(not read.is_empty() and not read.get("ok",true),"missing checkpoint returns explicit failure")
 check(io.stats().high_bytes<=8*1024*1024,"reservation high-water mark stays bounded")
 io.request_read(checkpoint.checkpoint,p,1);io.close()
 check(io.stats().outstanding==0 and io.stats().reserved_bytes==0 and io.request_read(checkpoint.checkpoint,p,1)==0,"shutdown joins worker and rejects more work")
 store.close();print("WATER_REGION_IO failures=",failures);quit(1 if failures else 0)

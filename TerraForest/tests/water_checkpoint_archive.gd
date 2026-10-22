# SPDX-License-Identifier: 0BSD
extends "res://tests/water_region_io.gd"
func run()->void:
 var folder:=ProjectSettings.globalize_path("user://water_archive_check_"+str(Time.get_ticks_usec()))
 var store=ClassDB.instantiate("NativeWaterRegionStore");check(store.open_store(folder),"isolated store opens")
 var io=ClassDB.instantiate("NativeWaterRegionIO");check(io.configure(store,1,16*1024*1024),"checkpoint worker configured")
 var p:=Vector3i(1,9,250);var keys:=PackedInt32Array([1,9,250]);var original:PackedByteArray=packet(125000)
 check(io.request_write(p,original,0)>0,"region write submitted")
 var reply:Dictionary=await receive(io)
 if not reply.get("ok",false):io.close();store.close();quit(1);return
 var digests:PackedByteArray=reply.digest
 check(io.request_checkpoint(keys,digests,0)>0,"checkpoint submitted after durable region acknowledgement")
 # Packed arrays use copy-on-write; changing caller buffers must not change the job.
 keys[0]=2;digests[0]^=1
 check(io.request_checkpoint(PackedInt32Array(),PackedByteArray(),0)==0,"checkpoint completion occupies bounded queue")
 reply=await receive(io)
 check(reply.get("ok",false) and reply.get("checkpoint_job",false),"frozen checkpoint job succeeds")
 if not reply.get("ok",false):io.close();store.close();quit(1);return
 var first:PackedByteArray=reply.checkpoint
 var archive=ClassDB.instantiate("NativeWorldArchive");var path:=folder.path_join("world.trw")
 check(archive.acquire(path),"compound archive leased")
 var sections:={"terrain":PackedByteArray([7]),"inventory":PackedByteArray([1]),"water_checkpoint":first}
 var old:PackedByteArray=archive.encode(sections)
 check(archive.publish(path,old)==OK,"compound archive selects acknowledged checkpoint")
 check(io.request_write(p,packet(0),0)>0,"new empty override submitted")
 reply=await receive(io)
 check(reply.get("ok",false),"new blob acknowledged without changing canonical save")
 check(archive.read(path)==old,"uncommitted blob does not alter prior saved world")
 var bad:PackedByteArray=reply.digest.duplicate();bad[0]^=1
 check(io.request_checkpoint(PackedInt32Array([1,9,250]),bad,0)>0,"missing-blob checkpoint validation runs on worker")
 var failed:Dictionary=await receive(io)
 check(not failed.get("ok",true) and archive.read(path)==old,"failed newer checkpoint leaves canonical save untouched")
 check(io.request_checkpoint(PackedInt32Array([1,9,250]),reply.digest,0)>0,"valid replacement checkpoint submitted")
 var second:Dictionary=await receive(io);check(second.get("ok",false),"replacement checkpoint acknowledged")
 if second.get("ok",false):
  sections.water_checkpoint=second.checkpoint;sections.inventory=PackedByteArray([0])
  check(archive.publish(path,archive.encode(sections))==OK,"new checkpoint and inventory published together")
  var restored:Dictionary=archive.decode(archive.read(path));var backup:Dictionary=archive.decode(archive.read(path+".bak"))
  check(restored.ok and backup.ok and restored.sections.inventory==PackedByteArray([0]) and backup.sections.inventory==PackedByteArray([1]),"canonical and backup retain corresponding inventory versions")
  check(store.read_region(restored.sections.water_checkpoint,p).get("packet",PackedByteArray())==packet(0),"canonical checkpoint selects empty override")
  check(store.read_region(backup.sections.water_checkpoint,p).get("packet",PackedByteArray())==original,"backup checkpoint still selects original water")
 check(io.request_checkpoint(PackedInt32Array([1]),PackedByteArray(),0)==0,"malformed checkpoint request rejected")
 io.close();archive.release();store.close();print("WATER_CHECKPOINT_ARCHIVE failures=",failures);quit(1 if failures else 0)

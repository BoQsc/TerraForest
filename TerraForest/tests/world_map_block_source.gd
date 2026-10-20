# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func read_region(archive:RefCounted,key:Vector3i,digest:PackedByteArray,checkpoint:PackedByteArray)->RefCounted:
 var result:Dictionary=archive.read_storage_region(key,digest,checkpoint)
 if not result.get("ok",false):return null
 var decoded=ClassDB.instantiate("NativeBlockMapRegion")
 return decoded if decoded.load_packet(result.bytes,digest) else null
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved world loads"):await done();return
 game.set_physics_process(false)
 var blocks=game.structures.blocks;var index:Dictionary=blocks.survey_index()
 var archive:RefCounted=game.terrain.backend.snapshot_codec;var checkpoint:PackedByteArray=game.structures._storage_checkpoint
 var lease:int=archive.retain_read_checkpoint("",checkpoint)
 if not check(lease>0,"map survey retains exact archived checkpoint"):await done();return
 var read_count:=0;var live_count:=0;var points:=0;var peak:=0
 var before:Dictionary=blocks.region_stats()
 for i in index.keys.size()/3:
  var key:=Vector3i(index.keys[i*3],index.keys[i*3+1],index.keys[i*3+2])
  var digest:PackedByteArray=index.checksums.slice(i*32,(i+1)*32);var empty:=PackedByteArray();empty.resize(32);empty.fill(0)
  var decoder:RefCounted
  if digest!=empty:
   var worker:=Thread.new();worker.start(read_region.bind(archive,key,digest,checkpoint),Thread.PRIORITY_LOW)
   while worker.is_alive():await process_frame
   decoder=worker.wait_to_finish();read_count+=1
   if not check(decoder!=null,"archived region decoded without gameplay admission"):break
  else:live_count+=1
  var at:=0
  for n in 65:
   var started:=Time.get_ticks_usec()
   var part:Dictionary=decoder.columns(at) if decoder!=null else blocks.survey_columns(key,at,index.revision)
   peak=maxi(peak,Time.get_ticks_usec()-started)
   if not part.get("ok",false) or part.points.size()>256:
    check(false,"bounded native column survey valid");break
   points+=part.points.size();at=part.offset
   if part.complete:break
 archive.release_read_checkpoint(lease)
 check(read_count>0 and live_count>0 and points>0,"one world survey includes distant archived and nearby live buildings")
 check(blocks.region_stats()==before and blocks.survey_index().revision==index.revision,"map source leaves block storage and residency unchanged")
 print("BLOCK_MAP_SOURCE_PROFILE archived_regions=",read_count," live_regions=",live_count," columns=",points," max_query_us=",peak)
 await done()
func done()->void:
 print("WORLD_MAP_BLOCK_SOURCE failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)

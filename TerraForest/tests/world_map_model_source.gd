# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func decode(bytes:PackedByteArray,digest:PackedByteArray,asset:String,box:AABB)->RefCounted:
 var result=ClassDB.instantiate("NativeModelMapRegion")
 return result if result.load_packet(bytes,digest,asset,box) else null
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved world loads"):await done();return
 game.set_physics_process(false)
 var archive:RefCounted=game.terrain.backend.snapshot_codec
 var reads:=0;var live:=0;var count:=0;var peak:=0
 for asset in game.structures._models:
  var batch=game.structures._models[asset]
  if not check(await wait_for(func():return batch.survey_index().ready,10),"collection transfer settles"):break
  var index:Dictionary=batch.survey_index()
  var checkpoint:PackedByteArray=game.structures._model_checkpoints.get(asset,PackedByteArray())
  if checkpoint.is_empty():
   checkpoint=archive.published_model_index(asset).get("checkpoint",PackedByteArray())
  var lease:int=archive.retain_read_checkpoint(asset,checkpoint) if checkpoint.size()==32 else 0
  var before:Dictionary=batch.region_stats()
  for i in index.keys.size()/3:
   var key:=Vector3i(index.keys[i*3],index.keys[i*3+1],index.keys[i*3+2])
   var digest:PackedByteArray=index.checksums.slice(i*32,(i+1)*32);var empty:=PackedByteArray();empty.resize(32);empty.fill(0)
   var decoder:RefCounted
   if digest!=empty:
    if not check(lease>0,"archived model version retained"):break
    var ticket:int=archive.request_model_region_read(asset,key,digest,checkpoint,game.terrain.epoch)
    if not check(ticket>0,"archive read accepted"):break
    var reply:Dictionary={}
    var deadline:=Time.get_ticks_msec()+10000
    while reply.is_empty() and Time.get_ticks_msec()<deadline:
     reply=archive.take_model_region_read(ticket)
     if reply.is_empty():await process_frame
    if not check(reply.get("ok",false),"archived model packet read"):
     archive.discard_model_region_read(ticket);break
    var worker:=Thread.new();worker.start(decode.bind(reply.bytes,digest,asset,index.prototype_bounds),Thread.PRIORITY_LOW)
    while worker.is_alive():await process_frame
    decoder=worker.wait_to_finish();reads+=1
    if not check(decoder!=null,"archived models decoded without gameplay admission"):break
   else:live+=1
   var cursor:=0
   for n in 3126:
    var started:=Time.get_ticks_usec()
    var part:Dictionary=decoder.bounds(cursor) if decoder!=null else batch.survey_bounds(key,cursor,index.revision)
    peak=maxi(peak,Time.get_ticks_usec()-started)
    if not part.get("ok",false) or part.bounds.size()>32:
     check(false,"bounded model survey succeeds");break
    count+=part.bounds.size();cursor=part.after_id
    if part.complete:break
  if lease>0:archive.release_read_checkpoint(lease)
  check(batch.region_stats()==before and batch.survey_revision_id()==index.revision,"survey preserves collection storage and residency")
 check(reads>0 and live>0 and count>0,"actual world includes archived and resident models")
 print("MODEL_MAP_SOURCE_PROFILE archived=",reads," live=",live," models=",count," max_query_us=",peak)
 await done()
func done()->void:
 print("WORLD_MAP_MODEL_SOURCE failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)

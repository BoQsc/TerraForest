# SPDX-License-Identifier: 0BSD
extends SceneTree
const PublicationBudget=preload("res://addons/volumetric_water/publication_budget.gd")
# Supplies solid terrain outside the cached synthetic lake. Without answering
# these requests, a headless flow test measures a missing worker, not settling.
class SolidTerrain extends RefCounted:
 func execute(command:PackedByteArray)->PackedByteArray:
  var count:=command.decode_u32(8);var reply:=PackedByteArray();reply.resize(20+count*4);reply.fill(0)
  reply.encode_u32(0,0x32505254);reply.encode_u32(12,command.decode_u32(4));reply.encode_u32(16,count)
  for i in count:reply.encode_float(20+i*4,-1.0)
  return reply
var failures:=0
var rows:Array=[]
var connected_rows:Array=[]
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func fixture(count:int,stride:int=3):
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+count*9076);bytes.fill(0)
 bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,2);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,count);bytes.encode_u64(16,count*4000000)
 for i in catalog.size():bytes[32+i]=catalog[i]
 for r in count:
  var base:int=32+catalog.size()+r*9076;var rx:=10+stride*(r/16);var rz:=10+stride*(r%16)
  bytes.encode_u64(base,(rx<<24)|(10<<12)|rz);bytes.encode_u32(base+8,1);bytes.encode_u32(base+12,1);base+=16
  for i in 512:bytes.encode_u16(base+i*12,500);bytes.encode_u16(base+i*12+2,500)
  for z in 8:
   for x in 8:
    var i:=x+8*3+64*z;bytes.encode_u16(base+i*12,0);bytes.encode_u64(base+i*12+4,62500)
  for i in 729:bytes.encode_float(base+6144+i*4,1.0)
 var water=ClassDB.instantiate("NativeRegionalWater")
 if not water.restore_snapshot(bytes):return null
 return water
func publish(water,limit:int,drain:bool=true) -> Dictionary:
 var started:=Time.get_ticks_usec();var packets:=0;var empty:=0;var commit_us:=0;var complete:=false;var batches:=0;var batch_packets:=0;var largest_batch:=0;var first_packets:=0
 for step in limit:
  var packet:Dictionary=water.next_mesh_batch()
  if packet.is_empty():break
  if packet.has("coordinate"):
   packets+=1;batch_packets+=1
   if packet.vertices==0:empty+=1
  if packet.complete:
   var mark:=Time.get_ticks_usec();complete=water.commit_mesh_batch(packet.batch);commit_us+=Time.get_ticks_usec()-mark
   if not complete:break
   batches+=1;largest_batch=maxi(largest_batch,batch_packets)
   if batches==1:first_packets=batch_packets
   batch_packets=0
   if not drain or water.statistics().dirty_meshes==0:break
 return {"complete":complete,"batches":batches,"largest_batch_packets":largest_batch,"first_batch_packets":first_packets,"packets":packets,"empty_packets":empty,"native_us":Time.get_ticks_usec()-started,"commit_us":commit_us,"minimum_frames_at_four_packets":ceili(packets/4.0)}
func connected_run(count:int,repeated:bool=false):
 var water=fixture(count,1)
 var initial:=publish(water,count*28+32)
 var point:=Vector3(41.75,41.75,41.75)
 var removed:int=water.brush(point,0.3,-62500)
 var terrain:=SolidTerrain.new()
 var frames:=0;var first_commit:=0;var packets:=0;var max_call_us:=0;var simulation_us:=0;var mesh_us:=0;var max_dirty:=0;var batch_start_frame:=0;var max_batch_frames:=0
 var edits:=1
 for frame in 240:
  frames=frame+1
  if repeated and frame<60:
   var next_point:=Vector3(41.75,41.75,42.25+frame*0.5)
   removed+=water.brush(next_point,0.3,-62500);edits+=1
  var start:=Time.get_ticks_usec();water.advance(2048);simulation_us+=Time.get_ticks_usec()-start
  for request_slot in 4:
   var request:Dictionary=water.next_request()
   if request.is_empty():break
   var patch=ClassDB.instantiate("NativeWaterTerrainPatch");patch.configure(request.coordinate)
   while patch.sample_terrain(terrain,729,0,0)==0:pass
   check(water.accept_patch(patch),"Connected fixture answers terrain occupancy request")
  var publish_started:=Time.get_ticks_usec()
  for slot in PublicationBudget.MAX_PACKETS:
   start=Time.get_ticks_usec()
   var packet:Dictionary=water.next_mesh_batch()
   var elapsed:=Time.get_ticks_usec()-start;mesh_us+=elapsed;max_call_us=maxi(max_call_us,elapsed)
   if packet.is_empty():break
   if batch_start_frame==0:batch_start_frame=frames
   if packet.has("coordinate"):packets+=1
   if packet.complete:
    max_batch_frames=maxi(max_batch_frames,frames-batch_start_frame+1);batch_start_frame=0
    if not water.commit_mesh_batch(packet.batch):check(false,"Connected batch acknowledgement")
    if first_commit==0 and packets>0:first_commit=frames
   if Time.get_ticks_usec()-publish_started>=PublicationBudget.SOFT_TIME_US:break
  var stats:Dictionary=water.statistics();max_dirty=maxi(max_dirty,stats.dirty_meshes)
  if (not repeated or frame>=60) and stats.active_cells==0 and stats.pending_vertical==0 and stats.dirty_meshes==0 and not stats.mesh_publish_pending:break
 var final:Dictionary=water.statistics()
 check(initial.complete and removed>0 and final.water_ml==count*4000000-removed,"Connected lake edit and flow conserve quantity (%d regions)"%count)
 check(first_commit>0 and first_commit<=4,"Connected lake local edit first publishes within four simulated frames (%d regions)"%count)
 check(final.active_cells==0 and final.dirty_meshes==0,"Connected lake local disturbance becomes idle within 240 frames (%d regions)"%count)
 connected_rows.append({"regions":count,"edit_attempts":edits,"removed_ml":removed,"initial":initial,"settle_frames":frames,"first_commit_frame":first_commit,"packets":packets,"max_dirty":max_dirty,"max_batch_frames":max_batch_frames,"simulation_us":simulation_us,"mesh_us":mesh_us,"max_mesh_call_us":max_call_us,"final":final})
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 for count in [1,16,64,256]:
  var water=fixture(count)
  if water==null:quit(2);return
  var initial:=publish(water,count*28+32)
  var point:=Vector3(41.75,41.6,41.75)
  var edited:int=water.brush(point,0.0,1000)
  var local:=publish(water,100)
  water.advance(1)
  var stats:Dictionary=water.statistics()
  check(initial.complete and local.complete and edited==1000 and stats.water_ml==count*4000000+1000,"Publication and local edit conserve water (%d regions)"%count)
  check(initial.packets<=count*4 and initial.empty_packets==0,"Restore schedules surface owners without empty halo packets (%d regions)"%count)
  check(initial.batches==count and initial.largest_batch_packets==3,"Independent pools publish separately with bounded batch size (%d regions)"%count)
  check(local.packets==1,"Local interior edit rebuilds only one owner (%d regions)"%count)
  rows.append({"regions":count,"initial":initial,"local_edit":local,"query_cache_bytes":stats.query_cache_bytes,"resident_cell_bytes":stats.resident_cell_bytes})
 var scoped=fixture(256)
 var scoped_first:Dictionary=scoped.next_mesh_batch()
 var distant_added:=0
 for r in range(1,256):
  var point:=Vector3((10+3*(r/16))*4+1.75,41.6,(10+3*(r%16))*4+1.75)
  distant_added+=scoped.brush(point,0.0,1000)
 check(not scoped_first.complete and distant_added==255000 and scoped.statistics().mesh_snapshot_bytes==0,"255 unrelated edits retain zero snapshot payload for active pool")
 check(scoped.brush(Vector3(41.75,41.6,41.75),0.0,1000)==1000 and scoped.statistics().mesh_snapshot_bytes>0,"Relevant edit still preserves active pool snapshot")
 check(publish(scoped,16,false).complete and scoped.statistics().mesh_snapshot_bytes==0 and scoped.statistics().water_ml==256*4000000+256000,"Scoped snapshots retire without losing local or distant edits")
 var adjacent=fixture(16,1)
 var connected:=publish(adjacent,256)
 check(connected.complete and connected.batches==1,"Adjacent dirty owners remain in one coherent batch")
 # Start a distant batch, then edit the last queued pool. It must follow the
 # in-flight batch, without waiting for all other independent pools.
 var queued=fixture(256)
 var first:Dictionary=queued.next_mesh_batch()
 check(first.has("coordinate") and not first.complete,"Distant publication is in flight before local edit")
 var late_point:=Vector3(221.75,41.6,221.75)
 check(queued.brush(late_point,0.0,1000)==1000,"Edit last queued pool during distant publication")
 check(queued.statistics().mesh_snapshot_bytes==0,"Distant edit does not copy data for unrelated in-flight pool")
 var finish:=publish(queued,16,false)
 check(finish.complete,"In-flight distant batch commits")
 var next:Dictionary=queued.next_mesh_batch()
 check(next.has("coordinate") and next.coordinate==Vector3i(55,10,55),"Edited pool takes priority over unrelated queued pools")
 var local_finish:=publish(queued,16,false)
 check(local_finish.complete and queued.statistics().dirty_meshes>0,"Edited pool publishes while distant work remains queued")
 for count in [16,64,256]:connected_run(count)
 connected_run(256,true)
 print("CONNECTED_SCALE ",JSON.stringify(connected_rows))
 print("WATER_SCALE ",JSON.stringify(rows))
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file=FileAccess.open("res://reports/water_publication_scale.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"rows":rows,"connected_rows":connected_rows},"  "));file.close()
 quit(failures)

# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:call_deferred("run")
func run()->void:
 for count in [1024,16384,65536]:
  var batch=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch)
  if count==65536:check(batch.configure_appearance_fade(),"exercise custom-data render stride")
  check(batch.configure_asset("test/transient",BoxMesh.new()) and batch.configure_render_streaming(true,128,128,4000000,2,65536),"configure streamed collection")
  var ids:=PackedInt64Array();ids.resize(count)
  var rows:=PackedFloat32Array();rows.resize(count*12);rows.fill(0)
  for i in count:
   ids[i]=i+1;rows[i*12]=1;rows[i*12+5]=1;rows[i*12+10]=1;rows[i*12+3]=float(i%16)
  check(batch.upsert_instances(ids,rows),"populate "+str(count)+" records")
  await process_frame;await process_frame
  check(batch.render_stats().resident_batches>0,"render pages exist before retirement")
  batch.set_removal_protected(1,true)
  check(not batch.begin_transient_clear() and batch.get_ids().size()==count,"protected collection rejects retirement atomically")
  batch.set_removal_protected(1,false)
  var original_bytes:int=batch.render_stats().resident_transform_bytes
  var revision:int=batch.survey_revision_id();var began:=Time.get_ticks_usec()
  var accepted:bool=batch.begin_transient_clear()
  var detach_us:=Time.get_ticks_usec()-began
  check(accepted,"detach full collection")
  var hidden:=true
  for child:Node3D in batch.get_children():hidden=hidden and not child.visible
  check(hidden and batch.get_ids().is_empty() and batch.survey_revision_id()==revision+1,"logical state clears once and retired pages hide immediately")
  check(not batch.begin_transient_clear() and not batch.clear_instances(),"second reset cannot overwrite pending retirement")
  check(not batch.configure_render_streaming(false,128,128,4000000,2,65536) and not batch.configure_appearance_fade(),"render reconfiguration cannot bypass retirement budget")
  check(batch.render_stats().retired_render_bytes==original_bytes and batch.stats().retired_collection_units>0,"retired data remains visible in memory accounting")
  check(not batch.advance_transient_clear(0,1000).ok,"invalid step budget rejected")
  check(batch.upsert_instances(PackedInt64Array([1]),rows.slice(0,12)),"reuse ID while old state retires")
  await process_frame;await process_frame
  check(batch.render_stats().resident_batches==0 and batch.render_stats().retained_render_bytes==original_bytes,"new rendering waits for retired pages to avoid double residency")
  check(batch.advance_transient_clear(1,1).processed==1,"minimum valid budget guarantees forward progress")
  var complete:=false;var calls:=0;var max_us:=0;var bounded:=true
  while not complete and calls<10000:
   var progress:Dictionary=batch.advance_transient_clear(64,1000)
   bounded=bounded and progress.ok and progress.processed<=64
   complete=progress.complete;calls+=1;max_us=maxi(max_us,progress.elapsed_us)
  check(complete and bounded and calls>1,"retirement obeys record cap and drains completely")
  check(batch.get_ids()==PackedInt64Array([1]) and batch.get_instance(1)==rows.slice(0,12),"retirement cannot erase newly placed object with reused ID")
  check(batch.stats().retired_collection_units==0 and batch.render_stats().retired_render_bytes==0,"retirement accounting drains to zero")
  await process_frame;await process_frame
  check(batch.render_stats().resident_instances==1,"new rendering resumes after retirement")
  print("TRANSIENT_RETIRE_PROFILE records=",count," detach_us=",detach_us," calls=",calls," max_step_us=",max_us)
  check(batch.begin_transient_clear(),"prepare partial-retirement shutdown")
  batch.free()
 print("TRANSIENT_COLLECTION_RETIREMENT failures=",failures);quit(1 if failures else 0)

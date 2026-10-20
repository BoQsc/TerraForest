# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var batch=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch)
 check(batch.configure_asset("test/reset",BoxMesh.new()),"configure reset fixture")
 var rows:=PackedFloat32Array([1,0,0,2,0,1,0,3,0,0,1,4,1,0,0,34,0,1,0,3,0,0,1,4])
 check(batch.upsert_instances(PackedInt64Array([1,2]),rows),"populate two render groups")
 check(batch.set_removal_protected(1,true) and not batch.clear_instances() and batch.get_ids().size()==2,"protected contents reject clear without partial removal")
 batch.set_removal_protected(1,false)
 var revision:int=batch.survey_revision_id()
 check(batch.clear_instances() and batch.get_ids().is_empty(),"clear removes every placement")
 check(batch.survey_revision_id()==revision+1,"bulk reset publishes one mutation")
 var stats:Dictionary=batch.render_stats()
 check(batch.get_child_count()==0 and stats.resident_batches==0 and stats.resident_instances==0 and stats.resident_transform_bytes==0 and stats.authored_groups==0 and stats.pending_batches==0 and stats.appearance_records==0,"clear releases rendering indices and accounting")
 check(batch.clear_instances() and batch.survey_revision_id()==revision+1,"empty reset is idempotent")
 check(batch.upsert_instances(PackedInt64Array([1,2]),rows) and batch.get_instance(2)==rows.slice(12),"collection can repopulate with original asset and IDs")
 batch.free();print("STATIC_BATCH_CLEAR failures=",failures);quit(1 if failures else 0)

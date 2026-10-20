# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func collect(query:Callable)->Array:
 var after:=0
 var boxes:Array=[]
 for i in 100:
  var part:Dictionary=query.call(after)
  if not part.get("ok",false):check(false,"query succeeds");return []
  check(part.bounds.size()<=32,"bounded model query")
  boxes.append_array(part.bounds)
  if part.complete:return boxes
  if part.after_id<=after:check(false,"cursor advances");return []
  after=part.after_id
 check(false,"query terminates");return []
func _initialize()->void:call_deferred("run")
func run()->void:
 GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
 var batch=ClassDB.instantiate("NativeStaticBatch");batch.configure_collision_only()
 check(not batch.survey_index().ready,"unconfigured collection is not ready")
 var mesh:=BoxMesh.new();mesh.size=Vector3(2,4,6)
 batch.configure_asset("map/test",mesh)
 var poses:Array[Transform3D]=[];var ids:=PackedInt64Array()
 for i in 70:
  ids.append(i+1)
  poses.append(Transform3D(Basis(Vector3.UP,PI/4).scaled(Vector3(2,1,0.5)),Vector3(1+i*0.1,5,2)))
 check(batch.upsert_transforms(ids,poses),"70 rotated scaled model records inserted")
 var snapshot:PackedByteArray=batch.capture_snapshot()
 check(batch.restore_snapshot(snapshot),"restore validates snapshot identity")
 var identity:String=batch.survey_cache_identity()
 check(not identity.is_empty(),"validated snapshot certifies map identity")
 var index:Dictionary=batch.survey_index()
 var original:=collect(func(cursor):return batch.survey_bounds(Vector3i.ZERO,cursor,index.revision))
 check(original.size()==70 and original[0]==poses[0]*mesh.get_aabb(),"transformed mesh bounds match actual placement")
 var packet:PackedByteArray=batch.capture_region(Vector3i.ZERO);var digest:=packet.slice(packet.size()-32)
 var decoder=ClassDB.instantiate("NativeModelMapRegion")
 check(decoder.load_packet(packet,digest,"map/test",mesh.get_aabb()),"archive decoder accepts exact asset and checksum")
 check(collect(decoder.bounds)==original,"archived and resident model bounds match")
 check(batch.unload_region(packet),"actual region unloads")
 check(batch.survey_cache_identity()==identity,"unload preserves logical map identity")
 check(batch.survey_bounds(Vector3i.ZERO,0,index.revision).get("stale",false),"old revision rejected")
 index=batch.survey_index()
 check(index.keys==PackedInt32Array([0,0,0]) and index.checksums==digest,"unloaded region retained in survey metadata")
 check(batch.survey_bounds(Vector3i.ZERO,0,index.revision).get("unloaded",false),"unloaded data is explicit")
 check(collect(decoder.bounds)==original and batch.region_stats().unloaded_regions==1,"archive survey leaves gameplay residency unchanged")
 check(not decoder.load_packet(packet,digest,"map/other",mesh.get_aabb()) and decoder.bounds(0).is_empty(),"wrong asset clears decoded data")
 var corrupt:=packet.duplicate();corrupt[40]^=1
 check(not decoder.load_packet(corrupt,digest,"map/test",mesh.get_aabb()),"corruption rejected")
 check(decoder.load_packet(packet,digest,"map/test",mesh.get_aabb()) and decoder.bounds(-1).is_empty(),"invalid cursor rejected")
 check(batch.restore_region(packet),"original region restores")
 check(batch.survey_cache_identity()==identity,"admission preserves logical map identity")
 check(batch.begin_region_retirement(packet),"retirement starts")
 check(not batch.survey_index().ready and not batch.survey_bounds(Vector3i.ZERO,0,batch.survey_revision_id()).ready,"in-flight transfer never exposes partial survey")
 batch.cancel_region_retirement()
 for n in 100:
  if not batch.region_admission_stats().active:break
  batch.advance_region_retirement(32,65536,500)
 check(not batch.region_admission_stats().active,"cancelled retirement rollback drained")
 check(batch.survey_cache_identity()==identity,"cancelled transfer preserves certified identity")
 check(batch.begin_region_retirement(packet),"full incremental retirement starts")
 for n in 100:
  if not batch.region_admission_stats().active:break
  batch.advance_region_retirement(32,65536,500)
 check(not batch.region_admission_stats().active and batch.survey_cache_identity()==identity,"completed incremental retirement preserves identity")
 check(batch.begin_region_admission(packet),"incremental readmission starts")
 for n in 100:
  if not batch.region_admission_stats().active:break
  batch.advance_region_admission(32,65536,500)
 check(not batch.region_admission_stats().active and batch.survey_cache_identity()==identity,"completed incremental admission preserves identity")
 check(batch.remove_instances(PackedInt64Array([1])) and batch.survey_cache_identity().is_empty(),"authoring removal clears certification")
 check(batch.restore_snapshot(snapshot) and batch.survey_cache_identity()==identity,"exact validated restoration restores certificate")
 poses[0].origin.x+=1
 check(batch.upsert_transforms(PackedInt64Array([1]),[poses[0]]) and batch.survey_cache_identity().is_empty(),"placement change clears certification")
 batch.free();print("MODEL_MAP_SURVEY failures=",failures);quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func visible_rows(batch:Node)->Dictionary:
 var result:Dictionary={}
 for child in batch.get_children():
  if child is MultiMeshInstance3D and child.visible:
   for i in child.multimesh.instance_count:
    var pose:Transform3D=child.multimesh.get_instance_transform(i)
    var id:=roundi(pose.origin.x*32)+1
    result[id]=child.multimesh.get_instance_custom_data(i)
 return result
func run()->void:
 GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
 var batch=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch)
 check(batch.configure_asset("removal/continuity",BoxMesh.new()) and batch.configure_appearance_fade() and batch.configure_render_streaming(true,80,32,100000,1,8192),"production-size pages and strict one-page upload budget")
 var ids:=PackedInt64Array();var poses:Array[Transform3D]=[]
 for i in 900:ids.append(i+1);poses.append(Transform3D(Basis.IDENTITY,Vector3(i/32.0,0,1)))
 check(batch.upsert_transforms(ids,poses),"dense group installed")
 for frame in 12:await RenderingServer.frame_post_draw
 var expected:=visible_rows(batch)
 check(expected.size()==900,"all pages resident")
 var before:Dictionary=batch.render_stats()
 for id in [1,129,450,899,900,2,128]:
  var start:=Time.get_ticks_usec()
  check(batch.remove_instances(PackedInt64Array([id])),"remove exact identity "+str(id))
  var elapsed:=Time.get_ticks_usec()-start
  expected.erase(id)
  check(visible_rows(batch)==expected,"every survivor visible immediately with original fade "+str(id))
  for frame in 3:
   await RenderingServer.frame_post_draw
   check(visible_rows(batch)==expected,"no missing or duplicate survivor on following frame")
  print("REMOVE_USEC ",elapsed)
 var after:Dictionary=batch.render_stats()
 check(after.uploaded_transform_bytes-before.uploaded_transform_bytes<=7*2*8192,"at most two bounded page uploads per removal")
 check(batch.get_ids().size()==893,"authoritative membership exact")
 # The compact index is no longer sorted: moving its swapped tail must still work.
 var moved:=Transform3D(Basis.IDENTITY,Vector3(29,0,1))
 check(batch.upsert_transforms(PackedInt64Array([898]),[moved]),"move survivor after swap compaction")
 for frame in 10:await RenderingServer.frame_post_draw
 check(batch.get_instance(898)[3]==29.0,"moved survivor retained exact authored transform")
 # Limited residency: compact a visible page using a previously nonresident tail.
 check(batch.configure_render_streaming(true,80,1,8192,1,8192),"single resident page budget")
 for frame in 5:await RenderingServer.frame_post_draw
 var partial_before:=visible_rows(batch).size()
 check(batch.remove_instances(PackedInt64Array([3])),"remove while tail page nonresident")
 check(visible_rows(batch).size()==partial_before,"visible page stays full using compacted tail")
 for frame in 5:await RenderingServer.frame_post_draw
 check(batch.render_stats().resident_transform_bytes<=8192,"partial residency respects byte cap")
 check(batch.remove_instances(batch.get_ids()),"bulk cleanup retains existing path")
 for frame in 3:await RenderingServer.frame_post_draw
 check(visible_rows(batch).is_empty(),"all retired records disappear")
 batch.free();await process_frame
 print("REMOVAL_CONTINUITY failures=",failures);quit(1 if failures else 0)

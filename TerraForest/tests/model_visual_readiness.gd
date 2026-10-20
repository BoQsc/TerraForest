# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func pose(x:float)->PackedFloat32Array:return PackedFloat32Array([1,0,0,x,0,1,0,1,0,0,1,1])
func _initialize()->void:run.call_deferred()
func run()->void:
 GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
 var batch=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch)
 check(batch.configure_asset("test/visual",BoxMesh.new()),"asset configured")
 check(batch.configure_render_streaming(true,16,2,96,1,48),"one-instance pages with bounded uploads")
 var values:=pose(1);values.append_array(pose(2));values.append_array(pose(97))
 check(batch.upsert_instances(PackedInt64Array([1,2,3]),values),"near and distant records")
 var box:=AABB(Vector3(0,0,0),Vector3(4,3,3))
 check(not batch.is_render_region_ready(box),"authored records without pages are not ready")
 for frame in 8:await process_frame
 check(batch.is_render_region_ready(box),"published nearby pages ready")
 check(not batch.is_render_region_ready(AABB(Vector3(96,0,0),Vector3(4,3,3))),"distant records without pages not ready")
 check(not batch.is_render_region_ready(AABB()),"invalid bounds rejected")
 batch.position=Vector3(1000,0,0)
 check(batch.is_render_region_ready(AABB(Vector3(1000,0,0),Vector3(4,3,3))),"world-space query respects collection transform")
 batch.position=Vector3.ZERO;batch.set_render_focus(Vector3(97,1,1))
 for frame in 8:await process_frame
 var packet:PackedByteArray=batch.capture_region(Vector3i.ZERO)
 check(batch.unload_region(packet),"cold records retire to metadata")
 check(not batch.is_render_region_ready(box),"unloaded metadata rejects readiness despite no queued near uploads")
 check(batch.restore_region(packet),"restore exact region")
 batch.set_render_focus(Vector3.ZERO)
 check(not batch.is_render_region_ready(box),"restored records await publication")
 for frame in 8:await process_frame
 check(batch.is_render_region_ready(box),"restored pages become ready")
 batch.free()
 print("MODEL_VISUAL_READINESS failures=",failures);quit(1 if failures else 0)

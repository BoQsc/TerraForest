# SPDX-License-Identifier: 0BSD
extends SceneTree
class Context extends Node:
 var game
 var structures
 var _models:Dictionary={}
 var epoch:=1
 var density_revision:=0
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var context:=Context.new();context.game=context;context.structures=context
 var batch=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch);batch.configure_collision_only()
 var mesh:=BoxMesh.new();mesh.size=Vector3(10,2,10);batch.configure_asset("map/test",mesh)
 batch.upsert_instances(PackedInt64Array([1]),PackedFloat32Array([1,0,0,100,0,1,0,40,0,0,1,100]))
 batch.restore_snapshot(batch.capture_snapshot())
 context._models={"map/test":batch}
 var survey=load("res://addons/world_runtime/survey_models.gd").new();survey.atlas=context;survey.terrain=context;survey.assets=["map/test"]
 var stamp:String=survey.current_stamp();var signature:String=survey.fast_identity()
 var packet:PackedByteArray=batch.capture_region(Vector3i(3,1,3))
 check(batch.unload_region(packet) and survey.current_stamp()==stamp and survey.fast_identity()==signature,"paging out does not invalidate map or certificate")
 check(batch.restore_region(packet) and survey.current_stamp()==stamp and survey.fast_identity()==signature,"paging in does not invalidate map or certificate")
 mesh.size.x+=1
 check(survey.current_stamp()!=stamp and survey.fast_identity()!=signature,"in-place prototype bounds change invalidates both identities")
 mesh.size.x-=1
 check(survey.current_stamp()==stamp and survey.fast_identity()==signature,"restored bounds recover exact identities")
 batch.remove_instances(PackedInt64Array([1]))
 check(survey.current_stamp()!=stamp and survey.fast_identity().is_empty(),"unsaved authoring invalidates runtime and disk shortcut")
 survey.free();batch.free();context.free()
 print("MODEL_MAP_IDENTITY failures=",failures);quit(1 if failures else 0)

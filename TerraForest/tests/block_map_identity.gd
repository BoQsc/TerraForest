# SPDX-License-Identifier: 0BSD
extends SceneTree
class Context extends Node:
 var game
 var structures
 var blocks
 var epoch:=1
 var density_revision:=0
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
 var context:=Context.new();context.game=context;context.structures=context
 var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld");root.add_child(blocks);context.blocks=blocks
 blocks.set_cells(PackedInt32Array([1,1,1,1,80,1,1,1]))
 var survey=load("res://addons/world_runtime/survey_blocks.gd").new();survey.atlas=context;survey.terrain=context
 var stamp:String=survey.current_stamp();var content:int=blocks.survey_content_revision_id();var cursor:int=blocks.survey_revision_id()
 check(blocks.survey_cache_identity().is_empty(),"new authored world uses a native content stamp before checkpoint certification")
 var packet:PackedByteArray=blocks.capture_region(Vector3i.ZERO)
 check(blocks.unload_region(packet) and survey.current_stamp()==stamp and blocks.survey_content_revision_id()==content,"exact eviction preserves logical content and current map stamp")
 check(blocks.survey_revision_id()!=cursor,"eviction still invalidates residency-sensitive survey cursors")
 check(blocks.restore_region(packet,PackedByteArray()) and survey.current_stamp()==stamp,"exact admission preserves the unsaved-world map stamp")
 blocks.set_cells(PackedInt32Array([1,1,1,2]))
 check(survey.current_stamp()!=stamp and blocks.survey_content_revision_id()!=content,"authored cell changes invalidate the content stamp")
 stamp=survey.current_stamp();content=blocks.survey_content_revision_id()
 blocks.set_cells(PackedInt32Array([1,1,1,2]))
 check(survey.current_stamp()==stamp and blocks.survey_content_revision_id()==content,"no-op authoring preserves the logical stamp")
 var current:PackedByteArray=blocks.capture_region(Vector3i.ZERO)
 check(blocks.restore_region(packet,current) and survey.current_stamp()!=stamp,"replacing resident content invalidates the stamp")
 survey.free();blocks.free();context.free()
 print("BLOCK_MAP_IDENTITY failures=",failures);quit(1 if failures else 0)

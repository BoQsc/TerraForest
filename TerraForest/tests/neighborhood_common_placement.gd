# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
 var failures:=0
 var world=preload("res://addons/structures/structures_world.gd").new();root.add_child(world)
 if not world.prepare():quit(1);return
 if preload("res://addons/structures/furniture_catalog.gd").register(world).size()!=3 or preload("res://addons/structures/storage_catalog.gd").register(world).is_empty():quit(1);return
 var placement=ClassDB.instantiate("NativePrefabPlacement")
 var recipe:Dictionary=preload("res://addons/structures/neighborhood_common.gd").build(Vector3(100,40,100))
 for turn in 4:
  var origin:Vector3i=recipe.origin+Vector3i(turn*100,0,0)
  var result:Dictionary=placement.place(world.blocks,recipe.asset,origin,turn,world.model_collections(),[])
  print("COMMON_TRANSACTION rotation=",turn," result=",result)
  if not result.ok:failures+=1
 if world.blocks.stats().cells!=184*4 or world.model("furniture/table/v1").get_ids().size()!=8 or world.model("furniture/chair/v1").get_ids().size()!=16 or world.model("storage/wooden_chest/v1").get_ids().size()!=4:failures+=1
 var saved:PackedByteArray=world.capture_snapshot()
 if not world.restore_snapshot(saved) or world.capture_snapshot()!=saved:failures+=1
 world.free();await process_frame
 print("NEIGHBORHOOD_COMMON_PLACEMENT failures=",failures)
 quit(1 if failures else 0)

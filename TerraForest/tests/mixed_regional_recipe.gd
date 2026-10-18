# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
 var catalog=preload("res://addons/structures/furniture_catalog.gd")
 var sources:Array[Resource]=[catalog.enclosed_cottage(),catalog.furnished_tower(3)]
 var recipe=preload("res://addons/structures/regional_districts.gd")
 var failures:=0
 for seed_value in [0,1,42,50,141,155,285,348,350,454,789,1703,2147483647]:
  var selected:Dictionary=recipe.mixed_layout_seed(sources,seed_value)
  var ok:bool=selected.get("ok",false) and selected==recipe.mixed_layout_seed(sources,seed_value)
  var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
  if ok:ok=asset.compose_settlement(sources,2,8,3,selected.seed,2)
  var doors:=0;var rails:=0
  if ok:
   for model:Dictionary in asset.get_model_attachments():
    if model.model=="architecture/wooden_door/v1":doors+=1
    if model.model=="architecture/metal_guardrail/v1":rails+=1
  ok=ok and doors==8 and rails>0 and rails<40
  if seed_value in [42,1703]:ok=ok and selected.seed==seed_value
  print("PASS " if ok else "FAIL ","mixed central seed=",seed_value," choice=",selected," doors=",doors," rails=",rails)
  if not ok:failures+=1
 print("MIXED_REGIONAL_RECIPE failures=",failures);quit(1 if failures else 0)

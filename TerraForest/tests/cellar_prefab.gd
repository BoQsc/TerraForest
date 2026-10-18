# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
 var asset:Resource=preload("res://addons/structures/cellar_catalog.gd").cottage()
 var failures:=0
 if asset==null:print("FAIL cellar prefab");quit(1);return
 for rotation in 4:
  var plan:Dictionary=preload("res://addons/structures/site_plan.gd").prepare(asset,Vector3i(1000,50,1000),rotation,50)
  var ok:bool=plan.ok and plan.target.y==45 and plan.segments[-1].start.y==46 and plan.segments[-1].clearance==5
  print("PASS " if ok else "FAIL ","cellar surface/floor alignment rotation=",rotation)
  if not ok:failures+=1
 var records:PackedInt32Array=asset.get_records()
 var hatch_clear:=true
 for i in range(0,records.size(),4):
  if records[i] in [1,2] and records[i+2] in [2,3] and records[i+1] in [5,6]:hatch_clear=false
 if not hatch_clear:failures+=1
 print("CELLAR_PREFAB failures=",failures);quit(1 if failures else 0)

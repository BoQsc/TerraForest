# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
 var failures:=0
 for floors in [2,3,4,16]:
  var asset:Resource=preload("res://addons/structures/furniture_catalog.gd").furnished_tower(floors)
  var cells:Dictionary={};var records:PackedInt32Array=asset.get_records()
  for i in range(0,records.size(),4):cells[Vector3i(records[i],records[i+1],records[i+2])]=records[i+3]
  var ok:=true
  for x in range(-8,9):
   for z in range(-8,9):ok=ok and cells.get(Vector3i(x,0,z),0)==65
  for level in range(1,floors):
   for x in range(-1,2):
    for z in range(0,4):ok=ok and cells.get(Vector3i(x,level*4,z),0)!=65
  if not ok:failures+=1
  print("PASS " if ok else "FAIL ","tower floors=",floors," sealed ground slab and open upper stair shafts")
 print("TOWER_GROUND_FLOOR failures=",failures);quit(1 if failures else 0)

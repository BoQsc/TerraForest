# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 var shop:Resource=preload("res://addons/structures/workshop_catalog.gd").village_shop()
 var world:Node3D=ClassDB.instantiate("NativeBlockWorld")
 var geometry:Resource=ClassDB.instantiate("NativeBlockPrefab")
 var ok:bool=shop!=null and geometry.configure(shop.get_records()) and world.place_prefab(geometry,Vector3i.ZERO,0)
 # Door, central customer aisle and rear stores must remain traversable.
 for z in range(-7,9):
  for y in [1,2]:ok=ok and world.get_cell(Vector3i(0,y,z))==0
  ok=ok and world.get_cell(Vector3i(0,0,z))!=0
 var doors:=0;var stores:=0
 for model:Dictionary in shop.get_model_attachments():
  if model.model=="architecture/wooden_door/v1":doors+=1
  if model.model=="storage/wooden_chest/v1":stores+=1
 ok=ok and doors==1 and stores==2
 var path:="user://village_shop_test.res"
 ok=ok and ResourceSaver.save(shop,path)==OK
 var restored:Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
 ok=ok and restored.get_records()==shop.get_records() and restored.get_model_attachments()==shop.get_model_attachments()
 DirAccess.remove_absolute(path)
 world.free()
 print("VILLAGE_SHOP failures=",0 if ok else 1)
 quit(0 if ok else 1)

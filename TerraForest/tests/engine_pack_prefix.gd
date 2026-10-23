# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 var launch=preload("res://demo/world_launch.gd")
 var failures:=0
 var runtime=ClassDB.instantiate("NativeWorldArchive")
 var actual:PackedStringArray=runtime.process_arguments()
 if not "--script" in actual or not "res://tests/engine_pack_prefix.gd" in actual:failures+=1
 var rows:Array=[
  [PackedStringArray(),"C:/Project",PackedStringArray(["--path","C:/Project"])],
  [PackedStringArray(),"",PackedStringArray()],
  [PackedStringArray(["--headless","--main-pack","C:/Game folder/TerraForest.pck"]),"",PackedStringArray(["--main-pack","C:/Game folder/TerraForest.pck"])],
  [PackedStringArray(["--main-pack=C:/Game/TerraForest.pck"]),"C:/Source",PackedStringArray(["--main-pack","C:/Game/TerraForest.pck"])]
 ]
 for row:Array in rows:
  if launch.engine_prefix_for(row[0],row[1])!=row[2]:failures+=1
 print("ENGINE_PACK_PREFIX failures=",failures);quit(1 if failures else 0)

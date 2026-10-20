# SPDX-License-Identifier: 0BSD
extends SceneTree
const Cache=preload("res://addons/world_runtime/survey_patch_cache.gd")
func _initialize()->void:
 var root_path:="user://test_map_cache_%d"%OS.get_process_id()
 var data:=PackedByteArray();data.resize(Cache.BYTES);data.fill(81)
 var failures:=0
 if not Cache.write("world","terrain-A",data,root_path,3).persisted:failures+=1
 if Cache.read("world","terrain-A",root_path).get("pixels")!=data:failures+=1
 if Cache.read("world","terrain-B",root_path).hit:failures+=1
 var path:=Cache.path_for("world",root_path);var file:=FileAccess.open(path,FileAccess.READ_WRITE);file.seek(100);file.store_8(0);file.close()
 if Cache.read("world","terrain-A",root_path).hit:failures+=1
 if not Cache.write("world","terrain-B",data,root_path,3).persisted or not Cache.read("world","terrain-B",root_path).hit:failures+=1
 if Cache.read("world","terrain-A",root_path).hit:failures+=1
 file=FileAccess.open(path,FileAccess.WRITE);file.store_8(1);file.close()
 if Cache.read("world","terrain-B",root_path).hit:failures+=1
 for i in 5:
  if not Cache.write(str(i),"terrain-B",data,root_path,3).persisted:failures+=1
 if DirAccess.get_files_at(root_path).size()!=3:failures+=1
 if Cache.write("bad","",data,root_path).persisted or Cache.write("bad","x",PackedByteArray(),root_path).persisted:failures+=1
 for name in DirAccess.get_files_at(root_path):DirAccess.remove_absolute(root_path+"/"+name)
 DirAccess.remove_absolute(root_path)
 print("SURVEY_PATCH_CACHE failures=",failures);quit(1 if failures else 0)

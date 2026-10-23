# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 var stage:="";var output:=""
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--owned-stage="):stage=arg.trim_prefix("--owned-stage=")
  if arg.begins_with("--inspection-output="):output=arg.trim_prefix("--inspection-output=")
 if not preload("res://demo/world_launch.gd").preparation_slot(stage) or not output.is_absolute_path():quit(2);return
 if not ClassDB.class_exists("NativeTerrainRegionStore"):GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var path:=ProjectSettings.globalize_path("user://worlds/"+stage+".trw.terrain")
 var store:RefCounted=ClassDB.instantiate("NativeTerrainRegionStore");var valid:bool=store.open_store(path,false);var rows:Array=[]
 if valid:
  for name:String in DirAccess.get_files_at(path):
   if not name.ends_with(".tindex"):continue
   var digest:=name.trim_suffix(".tindex").hex_decode()
   if digest.size()!=32:valid=false;continue
   var reference:PackedByteArray="TFTR".to_utf8_buffer();reference.resize(40);reference.encode_u32(4,1)
   for i in 32:reference[i+8]=digest[i]
   var row:Dictionary=store.verify_snapshot(reference);rows.append(row);valid=valid and row.get("ok",false)
 valid=valid and rows.size()>=3
 FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"ok":valid,"stage":stage,"checkpoints":rows},"  "))
 store.close();print("INTERRUPTED_GENERATION_INSPECT ok=",valid);quit(0 if valid else 1)

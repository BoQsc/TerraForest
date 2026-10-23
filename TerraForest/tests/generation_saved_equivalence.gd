# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
 var baseline:="";var candidate:=""
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--baseline-world="):baseline=arg.trim_prefix("--baseline-world=")
  if arg.begins_with("--candidate-world="):candidate=arg.trim_prefix("--candidate-world=")
 var launch=preload("res://demo/world_launch.gd")
 if not launch.valid_slot(baseline) or not launch.valid_slot(candidate):quit(2);return
 var archive=ClassDB.instantiate("NativeWorldArchive")
 var a:Dictionary=archive.decode(FileAccess.get_file_as_bytes("user://worlds/"+baseline+".trw"))
 var b:Dictionary=archive.decode(FileAccess.get_file_as_bytes("user://worlds/"+candidate+".trw"))
 var failures:=0
 if not a.get("ok",false) or not b.get("ok",false) or a.sections.terrain!=b.sections.terrain:failures+=1
 print("GENERATION_SAVED_EQUIVALENCE failures=",failures)
 quit(1 if failures else 0)

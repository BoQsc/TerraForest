# SPDX-License-Identifier: 0BSD
extends SceneTree
const Launch=preload("res://demo/world_launch.gd")
func _initialize()->void:run.call_deferred()
func hashes(path:String)->Dictionary:
 var result:Dictionary={}
 if FileAccess.file_exists(path):result[path]=FileAccess.get_sha256(path);return result
 if not DirAccess.dir_exists_absolute(path):return result
 for file:String in DirAccess.get_files_at(path):
  if not file.ends_with(".lock"):result[path.path_join(file)]=FileAccess.get_sha256(path.path_join(file))
 for folder:String in DirAccess.get_directories_at(path):result.merge(hashes(path.path_join(folder)))
 return result
func run()->void:
 var slot:=""
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--review-world="):slot=arg.trim_prefix("--review-world=")
 if not Launch.valid_slot(slot) or not FileAccess.file_exists("user://worlds/"+slot+".trw"):quit(2);return
 var original:=slot
 var clone:="photo_review_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
 var archive=ClassDB.instantiate("NativeWorldArchive")
 if not archive.clone_world(ProjectSettings.globalize_path("user://worlds"),original,clone).get("ok",false):quit(2);return
 slot=clone
 # Exact generated metadata cache files in this newly created disposable clone.
 # Remove them to exercise cold startup; never modify the source world's files.
 var cold_removed:=0
 var folder:="user://worlds/"+slot+".trw.models"
 for asset:String in DirAccess.get_directories_at(folder):
  var checkpoints:=folder.path_join(asset).path_join("checkpoints")
  for file:String in DirAccess.get_files_at(checkpoints):
   if file.ends_with(".tfmd") and DirAccess.remove_absolute(checkpoints.path_join(file))==OK:cold_removed+=1
 var before:Dictionary={}
 for suffix in [".trw",".trw.regions",".trw.models",".trw.water"]:before.merge(hashes("user://worlds/"+slot+suffix))
 var browser=load("res://demo/worlds.tscn").instantiate();root.add_child(browser)
 browser.slots=PackedStringArray([slot]);browser.filter_list();browser.refresh_photographs()
 var launched:bool=browser.photograph_pid>=0
 var deadline:=Time.get_ticks_msec()+150000
 while browser.photograph_pid>=0 and Time.get_ticks_msec()<deadline:await process_frame
 var failures:=0
 if not launched or browser.photograph_pid>=0 or not browser.notice.text.begins_with("Photographs refreshed"):failures+=1
 if browser.photograph_pid>=0:browser.cancel_photographs()
 var after:Dictionary={}
 for suffix in [".trw",".trw.regions",".trw.models",".trw.water"]:after.merge(hashes("user://worlds/"+slot+suffix))
 if before!=after:
  failures+=1
  for path:String in before:
   if before[path]!=after.get(path):print("CHANGED_CANONICAL ",path)
  for path:String in after:
   if not before.has(path):print("NEW_CANONICAL ",path)
 for name in ["north","road","market"]:
  var image:=Image.load_from_file("user://worlds/"+slot+".preview/"+name+".png")
  if image==null or image.get_size()!=Vector2i(1280,720):failures+=1;print("INVALID_PHOTO ",name)
 print("WORLD_PHOTOGRAPHS failures=",failures," cold_removed=",cold_removed," authoritative_files=",before.size()," notice=",browser.notice.text)
 browser.free();quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends SceneTree
var slot:=""
var output:=""
var failures:=0
var checks:=0
func _initialize()->void:
 root.set_flag(Window.FLAG_NO_FOCUS,true)
 ProjectSettings.set_setting("terraforest/offscreen_session",true)
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--preview-slot="):slot=arg.trim_prefix("--preview-slot=")
  if arg.begins_with("--preview-output="):output=arg.trim_prefix("--preview-output=")
 run.call_deferred()
func check(ok:bool,label:String)->bool:
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
 return ok
func wait_for(predicate:Callable,seconds:int)->bool:
 var deadline:=Time.get_ticks_msec()+seconds*1000
 while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
 return predicate.call()
func run()->void:
 if not slot.begins_with("StartupBench_") or not slot.is_valid_identifier() or output.is_empty():quit(2);return
 var path:="user://worlds/"+slot+".trw"
 if not FileAccess.file_exists(path):quit(2);return
 var original:=FileAccess.get_sha256(path)
 change_scene_to_file("res://demo/worlds.tscn");await scene_changed
 var browser=current_scene
 if not check(await wait_for(func():return not browser.library.loading,60),"Saved-world browser loads without photographs"):quit(1);return
 var selected:=-1
 for i in browser.worlds.item_count:
  if str(browser.worlds.get_item_metadata(i))==slot:selected=i;break
 if not check(selected>=0,"Owned newly generated world appears in My worlds"):quit(1);return
 browser.worlds.select(selected);browser.show_saved_details(selected)
 check(preload("res://addons/world_runtime/world_presentation.gd").image_for(slot)==null,"New world is playable without preview images")
 browser.photograph_button.pressed.emit()
 await process_frame
 browser.cancel_photographs()
 if not check(await wait_for(func():return browser.photograph_pid<0 and not browser.library.loading,120),"Optional photography cancels and returns to browser"):quit(1);return
 check(FileAccess.get_sha256(path)==original,"Cancellation preserves canonical saved world")
 browser.worlds.select(selected)
 browser.photograph_button.pressed.emit()
 if not check(await wait_for(func():return browser.photograph_pid<0 and not browser.library.loading,180),"Optional photography completes independently of play"):quit(1);return
 check("Photographs refreshed" in browser.notice.text,"Browser reports successful capture")
 for name:String in ["north","road","market"]:
  var image:=Image.load_from_file("user://worlds/"+slot+".preview/"+name+".png")
  check(image!=null and image.get_size()==Vector2i(1920,1080),"Lossless full-size photograph: "+name)
 check(preload("res://addons/world_runtime/world_presentation.gd").image_for(slot)!=null,"Browser can display deferred photographs")
 check(preload("res://addons/world_runtime/world_presentation.gd").metadata(slot).get("preview_count",0)==3,"Deferred capture updates presentation metadata")
 check(FileAccess.get_sha256(path)==original,"Successful photography preserves canonical saved world")
 check(preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"Preview operation never captures the pointer")
 browser.worlds.select(selected);browser.show_saved_details(selected)
 check(await wait_for(func():return browser.saved_picture.texture!=null,20),"My worlds refreshes its photograph thumbnail")
 await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output.path_join("browser.png"))
 print("DEFERRED_WORLD_PREVIEWS checks=",checks," failures=",failures)
 quit(1 if failures else 0)

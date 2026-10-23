# SPDX-License-Identifier: 0BSD
extends SceneTree
class Browser extends "res://demo/worlds.gd":
 var opened:=false
 func _open_game(_args:PackedStringArray)->void:opened=true
func _initialize()->void:run.call_deferred()
func run()->void:
 var browser:=Browser.new();root.add_child(browser)
 var slot:="cancel_review_%d"%Time.get_ticks_usec()
 browser.name_field.text=slot;browser.preset.select(0);browser.seed_field.value=42
 browser.launch_selected(true)
 var failures:=0;var deadline:=Time.get_ticks_msec()+15000;var creating:=false
 while browser.preparation_pid>=0 and Time.get_ticks_msec()<deadline:
  if FileAccess.file_exists(browser.preparation_status):
   var status:Variant=JSON.parse_string(FileAccess.get_file_as_string(browser.preparation_status))
   if status is Dictionary and status.get("state","")=="creating":creating=true;break
  await process_frame
 if not creating:failures+=1
 await create_timer(3.0).timeout
 browser.generation_screen.cancel_button.pressed.emit()
 var started:=Time.get_ticks_msec();deadline=started+10000
 while browser.preparation_pid>=0 and Time.get_ticks_msec()<deadline:await process_frame
 var status:Variant=JSON.parse_string(FileAccess.get_file_as_string(browser.preparation_status)) if FileAccess.file_exists(browser.preparation_status) else null
 if browser.preparation_pid>=0 or browser.opened or not status is Dictionary or status.get("state","")!="cancelled":failures+=1
 if FileAccess.file_exists("user://worlds/"+slot+".trw") or FileAccess.file_exists("user://worlds/"+slot+".prepare.lock"):failures+=1
 if browser.cancel_button.visible or Engine.max_fps!=60 or not browser.notice.text.contains("cancelled"):failures+=1
 for frame in 3:await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/world_browser_cancel.png")
 FileAccess.open("res://reports/world_browser_cancel.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"slot":slot,"status":status,"stop_ms":Time.get_ticks_msec()-started,"opened":browser.opened,"notice":browser.notice.text},"  "))
 browser.free();print("WORLD_BROWSER_CANCEL failures=",failures);quit(1 if failures else 0)

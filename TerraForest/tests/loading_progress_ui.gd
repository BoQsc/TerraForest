# SPDX-License-Identifier: 0BSD
extends SceneTree
const Meter=preload("res://addons/world_runtime/progress_meter.gd")
var failures:=0
func check(ok:bool,message:String)->void:
 if not ok:failures+=1;push_error(message)
func _initialize()->void:run.call_deferred()
func run()->void:
 var screen=preload("res://addons/world_runtime/generation_screen.gd").new();root.add_child(screen)
 screen.use_photograph("res://docs/evidence/generation_lifecycle/source_generation/generation_loading.png")
 # Use the actual raw world photograph rather than a prior UI capture when available.
 var raw:="user://worlds/lifecycle_bundle_20261023T163819.preview/north.png"
 if FileAccess.file_exists(raw):screen.use_photograph(raw)
 screen.update_stage("Building roads and foundations",180,367)
 await process_frame
 check(screen.panel.bar.value>8 and screen.panel.bar.value<30,"native command fraction contributes to overall percentage")
 screen.update_stage("Photographing the generated world",2,3)
 var prior:float=screen.panel.bar.value
 screen.update_stage("Placing buildings and interiors",1,100)
 check(screen.panel.bar.value==prior,"late observations cannot move the bar backwards")
 screen.update_stage("World generation complete",0,0)
 check(screen.panel.bar.value==88,"generation completion reserves verification and actual load")
 screen.update_status("verifying","Verifying saved terrain, buildings and water",{})
 check(screen.panel.bar.value==88,"verification starts below 100")
 screen.update_status("publishing","Saving the verified world",{})
 check(screen.panel.bar.value==92,"publication remains below playable completion")
 screen.update_status("ready","Opening your world",{})
 check(screen.panel.bar.value==94,"generation handoff is not playable completion")
 screen.panel.reset();screen.update_stage("Photographing the generated world",1,3,{"activity":"View 2/3 · Woodland road · Loading grass and plants","stage_fraction":0.56,"work":"Waiting for nearby vegetation to finish appearing"})
 await RenderingServer.frame_post_draw
 var rect:Rect2=screen.panel.get_global_rect();var bar:Rect2=screen.panel.bar.get_global_rect()
 check(absf(bar.get_center().x-root.size.x*0.5)<2 and bar.position.y>root.size.y*0.65 and bar.size.x>root.size.x*0.85 and bar.size.y>=18 and bar.size.y<=22 and rect.size.y<180 and rect.end.y<=root.size.y-8 and screen.cancel_button.get_global_rect().end.y<root.size.y,"large bar centered near bottom at full resolution")
 root.get_texture().get_image().save_png("res://reports/loading_progress_generation.png")
 screen.cancellation_requested=true;screen.detail.text="Cancelling generation…";screen.update_stage("Saving generated world",0,0)
 check(screen.detail.text=="Cancelling generation…","cancel state cannot be overwritten")
 screen.free()
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
 # Keep the actual loading flow; record only stage changes and one live frame.
 var rows:Array=[];var previous:="";var captured:=false;var deadline:=Time.get_ticks_msec()+60000
 while game.loading_active and Time.get_ticks_msec()<deadline:
  if game.loading_label.text!=previous:
   previous=game.loading_label.text;rows.append({"stage":previous,"percent":game.loading_progress.value})
  check(game.loading_progress.value<100,"input remains gated below completion")
  if not captured and game.loading_progress.value>20:
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://reports/loading_progress_world.png");captured=true
  await process_frame
 check(not game.loading_active and game.loading_progress.value==100,"100 only accompanies playable readiness")
 check(rows.size()>=3,"actual load communicates changing readiness stages")
 FileAccess.open("res://reports/loading_progress_ui.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"stages":rows,"scope":"Real gameplay loading gates and rendered UI, plus controlled generation stage/counter presentation. Full generation workflow checked separately."},"  "))
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
 print("LOADING_PROGRESS_UI failures=",failures);quit(1 if failures else 0)

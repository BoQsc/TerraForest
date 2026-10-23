# SPDX-License-Identifier: 0BSD
extends SceneTree
const Meter=preload("res://addons/world_runtime/progress_meter.gd")
var failures:=0
func check(ok:bool,message:String)->void:
 if not ok:failures+=1;push_error(message)
func screen_shade()->Color:return Color(0.01,0.02,0.03,0.5)
func _initialize()->void:run.call_deferred()
func run()->void:
 var screen=preload("res://addons/world_runtime/generation_screen.gd").new();root.add_child(screen)
 screen.panel.set_compact_width(true,false)
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
 screen.diagnostics.refresh()
 await RenderingServer.frame_post_draw
 var rect:Rect2=screen.panel.get_global_rect();var bar:Rect2=screen.panel.bar.get_global_rect()
 check(absf(bar.get_center().x-root.size.x*0.5)<2 and bar.position.y>root.size.y*0.65 and bar.size.x>root.size.x*0.5 and bar.size.x<root.size.x*0.65 and bar.size.y>=18 and bar.size.y<=22 and rect.size.y<180 and rect.end.y<=root.size.y-8 and screen.cancel_button.get_global_rect().end.y<root.size.y,"compact bar centered near bottom at full resolution")
 var clock:Rect2=screen.panel.clock_label.get_global_rect()
 check(clock.end.x<screen.cancel_button.get_global_rect().position.x and clock.position.x>screen.panel.title.get_global_rect().end.x,"elapsed and estimate fit in header without overlap")
 check(screen.panel.find_children("*","CheckButton",true,false).is_empty(),"loading screen has no Compact toggle")
 check(screen.background.shade.color.a==0.5 and screen.background.shade.get_index()>screen.picture.get_index(),"generation dims the photograph underneath the UI")
 check(screen.panel.clock_label.text.contains("Elapsed") and screen.panel.clock_label.text.contains("Est. remaining"),"both timers are visible beside bar from startup")
 var logo:Rect2=screen.diagnostics.wordmark.get_global_rect()
 check(absf(logo.get_center().x-root.size.x*0.5)<2 and logo.get_center().y>root.size.y*0.3 and logo.get_center().y<root.size.y*0.47,"wordmark is centered slightly above middle")
 check(screen.diagnostics.panel.get_global_rect().end.y<rect.position.y and logo.end.y<screen.diagnostics.panel.get_global_rect().position.y,"wordmark, technical panel and bottom bar do not overlap")
 check(screen.diagnostics.live.text.contains("stage_fraction = 0.56") and screen.diagnostics.history.text.contains("Photographing"),"raw work details and measured stage history are shown")
 root.get_texture().get_image().save_png("res://reports/loading_progress_generation.png")
 var progress_before:float=screen.panel.bar.value
 var elapsed_before:int=screen.panel.timing_snapshot().elapsed_us
 screen.panel.set_compact_width(false,false)
 await RenderingServer.frame_post_draw
 check(screen.panel.bar.get_global_rect().size.x>root.size.x*0.85 and absf(screen.panel.get_global_rect().get_center().x-root.size.x*0.5)<2,"wide option remains centered")
 check(screen.panel.bar.value==progress_before and screen.panel.timing_snapshot().elapsed_us>=elapsed_before,"switching width preserves progress and timer")
 root.get_texture().get_image().save_png("res://reports/loading_progress_wide.png")
 screen.panel.set_compact_width(true,false)
 # The optional width preference remains available without a loading-screen control.
 var preference_path:="user://loading_layout_check_%d.cfg"%Time.get_ticks_usec()
 var preference_panel=preload("res://addons/world_runtime/loading_panel.gd").new();preference_panel.preferences_path=preference_path;root.add_child(preference_panel)
 check(preference_panel.compact_width,"new users default to compact")
 preference_panel.set_compact_width(false)
 check(not preference_panel.compact_width,"optional width preference changes to wide")
 preference_panel.free()
 var restored=preload("res://addons/world_runtime/loading_panel.gd").new();restored.preferences_path=preference_path;root.add_child(restored)
 check(not restored.compact_width,"optional width preference survives a new loading panel")
 restored.free();DirAccess.remove_absolute(ProjectSettings.globalize_path(preference_path))
 # A large payload stays accessible by scrolling and is never interpreted as BBCode.
 var probe:Dictionary={}
 for i in 150:probe["field_%d"%i]="[b]literal[/b]"
 screen.diagnostics.context=probe;screen.diagnostics.refresh()
 await process_frame
 screen.diagnostics.live.get_v_scroll_bar().value=120
 var scrolled:float=screen.diagnostics.live.get_v_scroll_bar().value
 screen.diagnostics.observe("Changed",{"native_completed":7});screen.diagnostics.refresh()
 await process_frame
 check(scrolled>0 and absf(screen.diagnostics.live.get_v_scroll_bar().value-scrolled)<2,"refresh preserves manual diagnostic scroll")
 check(screen.diagnostics.live.get_parsed_text().contains("field_149 = [b]literal[/b]"),"all nested details remain available without markup injection")
 screen.cancellation_requested=true;screen.detail.text="Cancelling generation…";screen.update_stage("Saving generated world",0,0)
 check(screen.detail.text=="Cancelling generation…","cancel state cannot be overwritten")
 screen.free()
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
 game.loading_panel.set_compact_width(true,false)
 # Keep the actual loading flow; record only stage changes and one live frame.
 var elapsed_samples:Array=[]
 var rows:Array=[];var previous:="";var captured:=false;var diagnostic_sample:Dictionary={};var deadline:=Time.get_ticks_msec()+60000
 while game.loading_active and Time.get_ticks_msec()<deadline:
  if game.loading_label.text!=previous:
   previous=game.loading_label.text;rows.append({"stage":previous,"percent":game.loading_progress.value})
  check(game.loading_progress.value<100,"input remains gated below completion")
  elapsed_samples.append(game.loading_panel.timing_snapshot().elapsed_us)
  if not captured and game.loading_progress.value>20:
   game.loading_diagnostics.refresh()
   await RenderingServer.frame_post_draw
   diagnostic_sample=game.loading_diagnostics.context.duplicate(true)
   var backdrop:Control=game.loading_layer.get_node("LoadingBackground")
   check(backdrop.shade.color==screen_shade() and backdrop.shade.get_index()>backdrop.picture.get_index(),"gameplay loading uses the same dimmed background")
   var loading_rect:Rect2=game.loading_panel.get_global_rect()
   check(absf(loading_rect.get_center().x-root.size.x*0.5)<2 and loading_rect.size.x<root.size.x*0.65 and game.loading_diagnostics.panel.get_global_rect().end.y<=loading_rect.position.y,"actual loading uses compact centered panel without diagnostics overlap")
   check(game.loading_diagnostics.live.text.contains("readiness.queued") and game.loading_diagnostics.live.text.contains("addons.ground_cover") and game.loading_diagnostics.live.text.contains("addons.water") and game.loading_diagnostics.live.text.contains("terrain_worker.phase"),"actual world diagnostics are displayed")
   root.get_texture().get_image().save_png("res://reports/loading_progress_world.png");captured=true
  await process_frame
 check(not game.loading_active and game.loading_progress.value==100,"100 only accompanies playable readiness")
 check(not game.loading_diagnostics.is_processing(),"technical display stops polling when gameplay starts")
 var final_timing:Dictionary=game.loading_panel.timing_snapshot()
 check(final_timing.status=="complete" and final_timing.remaining_us==0 and game.loading_panel.clock_label.text.contains("Total") and not game.loading_panel.is_processing(),"ready freezes total, clears ETA and stops timer polling")
 check(elapsed_samples.size()>1 and elapsed_samples.back()>elapsed_samples.front(),"actual elapsed timer advances during loading")
 var state:Dictionary=game.terrain.loading_state(game.player.position,game.fly)
 var expected:=0;var total:=0
 for key:Vector3i in game.terrain.roots:
  var dx:float=maxf(maxf(key.x-game.player.position.x,game.player.position.x-key.x-key.z),0)
  var dz:float=maxf(maxf(key.y-game.player.position.z,game.player.position.z-key.y-key.z),0)
  if not game.terrain.nearby_first or Vector2(dx,dz).length_squared()<384.0*384.0:
   total+=1
   if game.terrain.covered_roots.has(key):expected+=1
 check(state.coverage_ready==expected and state.coverage_total==total,"display counts exactly the coverage required by the play gate")
 check(Meter.loading_caption("Loading landscape coverage",state).contains("%d / %d"%[expected,total]),"landscape caption carries the live fraction")
 check(rows.size()>=3,"actual load communicates changing readiness stages")
 check(game.loading_panel.work.text.contains("worker:") and game.loading_panel.work.text.contains("cache hits") and game.loading_panel.work.text.contains("Coverage"),"bottom bar itself exposes live landscape counters")
 FileAccess.open("res://reports/loading_progress_ui.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"stages":rows,"diagnostics":diagnostic_sample,"timing":final_timing,"scope":"Real gameplay loading gates and rendered UI, plus controlled generation stage/counter presentation. Full generation workflow checked separately."},"  "))
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
 print("LOADING_PROGRESS_UI failures=",failures);quit(1 if failures else 0)

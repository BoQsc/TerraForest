extends SceneTree
var game:Node
var output:="res://reports/runtime_travel_profile"
var rows:Array[Dictionary]=[]
var stages:Dictionary={}
var initializations:Array[Dictionary]=[]
var seen:Dictionary={}
var phase:="idle"
var previous:=0
var process_started:=0
var draw_started:=0
var viewport:RID
var origin:Vector3
var requested_origin:=Vector3.INF
func _initialize()->void:run.call_deferred()
func until(predicate:Callable,seconds:int)->bool:
 var deadline:=Time.get_ticks_msec()+seconds*1000
 while not predicate.call() and Time.get_ticks_msec()<deadline:
  await process_frame;game.app_focused=true
 return predicate.call()
func stage(label:String,milliseconds:float)->void:stages[label]=float(stages.get(label,0.0))+milliseconds
func begin_process()->void:process_started=Time.get_ticks_usec();game.app_focused=true
func begin_draw()->void:draw_started=Time.get_ticks_usec()
func frame()->void:
 var now:=Time.get_ticks_usec()
 for zombie:Node3D in game.zombies.residents:
  if seen.has(zombie.get_instance_id()):continue
  seen[zombie.get_instance_id()]=true
  initializations.append({"phase":phase,"frame":rows.size(),"microseconds":zombie.initialization_us.duplicate(),"geometry":zombie.anatomy.geometry_stats() if zombie.anatomy.has_method("geometry_stats") else {}})
 if rows.size()<6000:
  rows.append({"phase":phase,"frame_ms":(now-previous)/1000.0,"process_ms":(draw_started-process_started)/1000.0,"draw_ms":(now-draw_started)/1000.0,"before_process_ms":(process_started-previous)/1000.0,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport),"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"stages":stages.duplicate(),"ecosystem_us":game.ecosystem.last_process_us,"cover_us":game.ground_cover.last_process_us,"vegetation_us":game.vegetation.renderer.stats.get("update_us",0),"vegetation_phases_us":Array(game.vegetation.renderer.phase_us),"position":game.player.position,"distance":game.player.position.distance_to(origin),"queued":game.terrain.backend.queued(),"residents":game.zombies.residents.size(),"navigation":game.zombies.navigation_status.duplicate(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
 previous=now;stages.clear()
func move(pressed:bool)->void:
 var event:=InputEventKey.new();event.physical_keycode=KEY_W;event.pressed=pressed
 Input.parse_input_event(event);Input.flush_buffered_events()
func sample(label:String,seconds:float)->void:
 phase=label
 var deadline:=Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<deadline:await process_frame
func run()->void:
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--profile-dir="):output=argument.trim_prefix("--profile-dir=")
  if argument.begins_with("--profile-origin="):
   var coordinates:=argument.trim_prefix("--profile-origin=").split(",")
   if coordinates.size()==3:requested_origin=Vector3(float(coordinates[0]),float(coordinates[1]),float(coordinates[2]))
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await until(func():return not game.loading_active and not game.needs_floor_spawn,90):push_error("Travel profile did not finish loading");await finish(false);return
 if requested_origin.is_finite():
  game.teleport(requested_origin)
  if not await until(func():return not game.loading_active and not game.needs_floor_spawn,60):push_error("Travel profile origin did not finish loading");await finish(false);return
 if game.session_menu.developer:game.session_menu.toggle_developer()
 game.session_menu.set_open(false);game._clear_motion();game.fly=false;game.player.rotation.y=0
 Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 await sample("settling",2)
 origin=game.player.position;viewport=root.get_viewport_rid();RenderingServer.viewport_set_measure_render_time(viewport,true)
 game.vegetation.renderer.profiling_enabled=true
 game.terrain.stage_measured.connect(stage);process_frame.connect(begin_process);RenderingServer.frame_pre_draw.connect(begin_draw);RenderingServer.frame_post_draw.connect(frame)
 previous=Time.get_ticks_usec()
 await sample("idle",8)
 move(true);await sample("walking",45);move(false)
 await sample("recovery",8)
 RenderingServer.frame_post_draw.disconnect(frame);RenderingServer.frame_pre_draw.disconnect(begin_draw);process_frame.disconnect(begin_process);game.terrain.stage_measured.disconnect(stage)
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output.path_join("arrival.png"))
 var moved:float=game.player.position.distance_to(origin)
 FileAccess.open(output.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify({"frames":rows,"initializations":initializations,"distance":moved,"adapter":RenderingServer.get_video_adapter_name(),"viewport":root.size,"notes":"1080p capped at 60; wall intervals include waits, GPU timers may lag; nested stage timings must not be summed. Actual held W walking, temporary world."}))
 print("TRAVEL_PROFILE distance=",moved," frames=",rows.size())
 await finish(moved>80 and rows.size()>600)
func finish(success:bool)->void:
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
 print("TRAVEL_PROFILE ","PASS" if success else "FAIL");quit(0 if success else 1)

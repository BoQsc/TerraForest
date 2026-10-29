extends SceneTree
class ProfileWorld extends "res://demo/world.gd":
 func _movement_input_available()->bool:
  return not loading_active and not shutdown_requested and not session_menu.visible_ui() and not player_hud.inventory_open
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
var walking_seconds:=45.0
var slot:=""
var save_hash:=""
var route:=PackedVector3Array()
var route_index:=1
var route_steps:=128
var travelled:=0.0
var previous_position:=Vector3.ZERO
var expected_cache:=""
var profile_notes:="Held W through real walking/physics with deterministic road-following turns, test-only movement admission without mouse capture. Not a mining or endurance benchmark."
func _initialize()->void:
 ProjectSettings.set_setting("terraforest/offscreen_session",true)
 run.call_deferred()
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
 for label in game.zombies.update_phase_us:stages["zombie "+label]=game.zombies.update_phase_us[label]/1000.0
 if phase=="walking":travelled+=game.player.position.distance_to(previous_position)
 previous_position=game.player.position
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
 while Time.get_ticks_msec()<deadline:
  if label=="walking" and route.size()>1:
   var offset:Vector3=route[route_index]-game.player.position;offset.y=0
   if offset.length()<.6:
    route_index+=1
    if route_index>=route.size():route.reverse();route_index=1
    offset=route[route_index]-game.player.position;offset.y=0
   game.player.rotation.y=atan2(-offset.x,-offset.z)
  await process_frame
func run()->void:
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--profile-dir="):output=argument.trim_prefix("--profile-dir=")
  if argument.begins_with("--profile-origin="):
   var coordinates:=argument.trim_prefix("--profile-origin=").split(",")
   if coordinates.size()==3:requested_origin=Vector3(float(coordinates[0]),float(coordinates[1]),float(coordinates[2]))
  if argument.begins_with("--profile-slot="):slot=argument.trim_prefix("--profile-slot=")
  if argument.begins_with("--derived-cache="):expected_cache=argument.trim_prefix("--derived-cache=")
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
 if not slot.is_empty():
  if not slot.begins_with("recipe_generated_") or not slot.is_valid_filename():push_error("Profile requires a disposable generated check slot");quit(1);return
  save_hash=FileAccess.get_sha256("user://worlds/"+slot+".trw")
  var session_arguments:=PackedStringArray(["--world-slot="+slot,"--snapshot-readonly","--gameplay-construction","--ground-cover","--actors","--vehicle-fleet","--temporary"])
  if not expected_cache.is_empty():session_arguments.append("--derived-cache="+expected_cache)
  preload("res://addons/world_runtime/session_options.gd").set_arguments(session_arguments,true)
 game=ProfileWorld.new();game.name="TerraForest";game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await until(func():return not game.loading_active and not game.needs_floor_spawn,90):push_error("Travel profile did not finish loading");await finish(false);return
 var heading:=Vector3.FORWARD
 if not slot.is_empty() and not requested_origin.is_finite():
  var roads:Array=game.generated_region.describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator).get("roads",[])
  roads=roads.filter(func(road:Dictionary):return float(road.width)>=7.0)
  roads.sort_custom(func(first:Dictionary,second:Dictionary):return first.a.distance_squared_to(first.b)>second.a.distance_squared_to(second.b))
  if roads.is_empty():push_error("Profile world has no regional roads");await finish(false);return
  var road:Dictionary=roads[0]
  heading=(road.b-road.a).normalized()
  requested_origin=road.a+heading*5+Vector3.UP*.1
  route.append(requested_origin);route.append(road.b)
  var used:={roads.find(road):true}
  for step in route_steps:
   var best:=-1;var destination:=Vector3.ZERO;var alignment:=-2.0
   for index in roads.size():
    if used.has(index):continue
    var candidate:Dictionary=roads[index]
    var next:Vector3
    if candidate.a.distance_to(route[-1])<.15:next=candidate.b
    elif candidate.b.distance_to(route[-1])<.15:next=candidate.a
    else:continue
    var direction:Vector3=(next-route[-1]).normalized()
    var score:float=direction.dot((route[-1]-route[-2]).normalized())
    if score>alignment:alignment=score;best=index;destination=next
   if best<0:break
   used[best]=true;route.append(destination)
  print("PROFILE_ROUTE ",route)
 if requested_origin.is_finite():
  game.teleport(requested_origin)
  if not await until(func():return not game.loading_active and not game.needs_floor_spawn,60):push_error("Travel profile origin did not finish loading");await finish(false);return
 if game.session_menu.developer:game.session_menu.toggle_developer()
 game.session_menu.set_open(false);game._clear_motion();game.fly=false;game.player.rotation.y=atan2(-heading.x,-heading.z);game.camera.rotation.x=0
 if not await until(func():return game.ecosystem._requests.is_empty() and game.ecosystem.resident.size()==game.ecosystem._wanted.size(),60):push_error("Profile forest did not settle");await finish(false);return
 await sample("settling",2)
 if not is_instance_valid(game):return
 origin=game.player.position;viewport=root.get_viewport_rid();RenderingServer.viewport_set_measure_render_time(viewport,true)
 game.vegetation.renderer.profiling_enabled=true
 game.zombies.profiling_enabled=true
 game.terrain.stage_measured.connect(stage);process_frame.connect(begin_process);RenderingServer.frame_pre_draw.connect(begin_draw);RenderingServer.frame_post_draw.connect(frame)
 previous=Time.get_ticks_usec();process_started=previous;draw_started=previous;previous_position=game.player.position
 await sample("idle",8)
 move(true);await sample("walking",walking_seconds);move(false)
 await sample("recovery",8)
 RenderingServer.frame_post_draw.disconnect(frame);RenderingServer.frame_pre_draw.disconnect(begin_draw);process_frame.disconnect(begin_process);game.terrain.stage_measured.disconnect(stage)
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output.path_join("arrival.png"))
 var moved:float=game.player.position.distance_to(origin)
 var unchanged:=slot.is_empty() or save_hash==FileAccess.get_sha256("user://worlds/"+slot+".trw")
 var mouse_untouched:bool=preload("res://addons/world_runtime/mouse_ownership.gd").captures==0 and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE
 var cache_isolated:bool=expected_cache.is_empty() or game.terrain.backend.cache_path==expected_cache
 FileAccess.open(output.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify({"frames":rows,"initializations":initializations,"distance":moved,"travelled":travelled,"route":route,"adapter":RenderingServer.get_video_adapter_name(),"viewport":root.size,"slot":slot,"save_unchanged":unchanged,"mouse_untouched":mouse_untouched,"notes":"1080p capped at 60, nonactivating offscreen; wall intervals include waits, GPU timers may lag; nested stages must not be summed. "+profile_notes}))
 print("TRAVEL_PROFILE distance=",moved," frames=",rows.size())
 print("PROFILE_CACHE actual=",game.terrain.backend.cache_path," isolated=",cache_isolated)
 await finish(travelled>80 and rows.size()>600 and unchanged and mouse_untouched and cache_isolated)
func finish(success:bool)->void:
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
 print("TRAVEL_PROFILE ","PASS" if success else "FAIL");quit(0 if success else 1)

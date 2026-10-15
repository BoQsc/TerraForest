# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func percentile(rows:Array,field:String,p:float)->float:
 var values:Array=[]
 for row in rows:values.append(float(row[field]))
 values.sort();return values[int((values.size()-1)*p)]
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
 var output:="";var slot:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--crossing-output="):output=arg.trim_prefix("--crossing-output=")
  if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
 if output.is_empty() or not slot.begins_with("actor_crossing_"):quit(2);return
 var game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:int=Time.get_ticks_msec()+45000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 check(not game.loading_active,"furnished settlement loads")
 if game.loading_active:game.terrain.shutdown();game.free();quit(1);return
 game.set_physics_process(false);game._clear_motion()
 var street:Dictionary=game.road_palette.prepared_streets[0]
 var direction:Vector3=(street.ends[1]-street.ends[0]).normalized()
 var side:=Vector3(-direction.z,0,direction.x)
 var a:Vector3=street.ends[0]+direction*5+Vector3.UP*0.93
 var b:Vector3=street.ends[0]+direction*17+Vector3.UP*0.93
 game.player.position=a+side*5;game.terrain.focus=a
 game.camera.global_position=(a+b)*0.5+side*10+Vector3.UP*7;game.camera.look_at((a+b)*0.5)
 for frame in 90:await physics_frame
 var crowd:bool="--crowd" in OS.get_cmdline_user_args()
 var lanes:int=8 if crowd else 1
 var handles:=PackedInt64Array();var goals:=PackedVector3Array()
 for lane in lanes:
  var offset:Vector3=side*(float(lane)-(lanes-1)*0.5)*0.8
  for reverse in 2:
   var point:Vector3=(a if reverse==0 else b)+offset
   var goal:Vector3=(b if reverse==0 else a)+offset
   var identity:int=game.actors.spawn(point)
   handles.append(game.actors.store.resolve_identity(identity));goals.append(goal)
   game.actors.orders.set_target(identity,goal)
 var minimum:=INF;var trace:Array=[];var peak_work:=0;var costs:Array=[];var render_costs:Array=[]
 var viewport:=root.get_viewport_rid();RenderingServer.viewport_set_measure_render_time(viewport,true)
 game.actors.pool.set_profiling(true)
 var timing:Dictionary={"previous":Time.get_ticks_usec(),"drawn":Engine.get_frames_drawn(),"actor_ms":0.0,"probe_ms":0.0,"updates":0}
 var frame_sampler:Callable=func():
  var now:int=Time.get_ticks_usec()
  render_costs.append({"frame_ms":(now-timing.previous)/1000.0,"drawn_delta":Engine.get_frames_drawn()-timing.drawn,"actor_ms":timing.actor_ms,"probe_ms":timing.probe_ms,"updates":timing.updates,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),"engine_window_process_max_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"engine_window_physics_max_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"engine_window_navigation_max_ms":Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS)*1000})
  timing.previous=now;timing.drawn=Engine.get_frames_drawn();timing.actor_ms=0.0;timing.probe_ms=0.0;timing.updates=0
 RenderingServer.frame_post_draw.connect(frame_sampler)
 for frame in 720:
  await physics_frame
  var begin:int=Time.get_ticks_usec()
  game.actors.update_simulation(1.0/60,(a+b)*0.5,true,game._actor_collision_ready)
  var actor_ms:float=(Time.get_ticks_usec()-begin)/1000.0
  timing.actor_ms+=actor_ms;timing.updates+=1
  var probe_begin:int=Time.get_ticks_usec()
  peak_work=maxi(peak_work,game.actors.simulation_status.route_work)
  var positions:=PackedVector3Array();var states:Array=[]
  for handle in handles:
   positions.append(game.actors.store.get_position(handle))
   if frame%12==0:states.append(game.actors.pool.navigation_status(handle))
  for i in positions.size():
   for j in range(i+1,positions.size()):minimum=minf(minimum,positions[i].distance_to(positions[j]))
  if frame%12==0:trace.append({"positions":positions,"states":states})
  timing.probe_ms+=(Time.get_ticks_usec()-probe_begin)/1000.0
  var status:Dictionary=game.actors.simulation_status
  costs.append({"actor_ms":actor_ms,"readiness_ms":status.readiness_us/1000.0,"motion_ms":status.motion_us/1000.0,"transform_ms":status.transform_us/1000.0,"store_ms":status.store_us/1000.0,"planning_ms":status.route_planning_us/1000.0,"held":status.held,"active":game.actors.pool.active_handles().size()})
 RenderingServer.frame_post_draw.disconnect(frame_sampler)
 var arrived:=0
 for i in handles.size():
  if game.actors.store.get_position(handles[i]).distance_to(goals[i])<0.3:arrived+=1
 check(minimum>=0.69,"street crossing preserves separation: %.3f m"%minimum)
 check(arrived==handles.size(),"actors arrive through ordinary main-world navigation: %d / %d"%[arrived,handles.size()])
 check(peak_work<=12,"shared route planning budget remains bounded")
 var measured:Array=costs.slice(60);var summary:Dictionary={}
 for field in ["actor_ms","readiness_ms","motion_ms","transform_ms","store_ms","planning_ms","held","active"]:summary[field]={"p95":percentile(measured,field,0.95),"max":percentile(measured,field,1.0)}
 for field in ["frame_ms","gpu_ms","probe_ms","drawn_delta","updates"]:summary[field]={"p95":percentile(render_costs.slice(60),field,0.95),"max":percentile(render_costs.slice(60),field,1.0)}
 for field in ["engine_window_process_max_ms","engine_window_physics_max_ms","engine_window_navigation_max_ms"]:summary[field]={"observed_max":percentile(render_costs.slice(60),field,1.0)}
 check(summary.drawn_delta.max==1,"render sampler observes consecutive drawn frames")
 check(summary.active.max<=16,"active collision population remains bounded")
 if crowd:
  check(summary.frame_ms.p95<=18.5,"frame p95 <= 18.5 ms")
  check(summary.actor_ms.p95<=1.0 and summary.actor_ms.max<=2.0,"actor adapter p95 <= 1 ms and max <= 2 ms")
 print("CROSSING_COST ",JSON.stringify(summary))
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output+"/street.png")
 var file:=FileAccess.open(output+"/motion.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"timing_schema":2,"native_profiling":true,"failures":failures,"population":handles.size(),"arrived":arrived,"minimum_separation":minimum,"peak_route_work":peak_work,"summary":summary,"physics_cost_rows":costs,"render_cost_rows":render_costs,"trace":trace},"  "));file.close()
 game.terrain.shutdown();game.free();await process_frame
 print("ACTOR_STREET_CROSSING failures=",failures);quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node3D
var failures:=0
var phases:Array=[]
func _initialize():call_deferred("run")
func settled()->bool:
 var s:Dictionary=game.lakes.statistics()
 return not game.loading_active and game.terrain.backend.queued()==0 and game.terrain.backend.status()=="idle" and int(s.dirty_meshes)==0 and not s.mesh_batch_active and not s.mesh_publish_pending and not s.fill_active
func distribution(rows:Array,field:String)->Dictionary:
 var values:Array=[]
 for row:Dictionary in rows:values.append(row[field])
 values.sort()
 return {"median":values[values.size()/2],"p95":values[floori((values.size()-1)*0.95)],"max":values.back()}
func sample(label:String,position:Vector3,target:Vector3):
 game.camera.global_position=position;game.camera.look_at(target,Vector3.UP)
 var deadline:=Time.get_ticks_msec()+15000;var idle:=0
 while idle<60 and Time.get_ticks_msec()<deadline:
  await RenderingServer.frame_post_draw
  idle=idle+1 if settled() else 0
 if idle<60:failures+=1;print("FAIL settled warmup ",label);return
 var viewport:=root.get_viewport_rid();var rows:Array=[];var previous:=Time.get_ticks_usec()
 for frame in 120:
  await RenderingServer.frame_post_draw
  var now:=Time.get_ticks_usec()
  rows.append({"frame_ms":(now-previous)/1000.0,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"unsettled":0 if settled() else 1})
  previous=now
 var stats:Dictionary={}
 for field in ["frame_ms","gpu_ms","render_cpu_ms","primitives","draw_calls","unsettled"]:stats[field]=distribution(rows,field)
 if stats.gpu_ms.median<=0 or stats.unsettled.max!=0:failures+=1
 phases.append({"view":label,"camera":position,"target":target,"summary":stats,"rows":rows,"water":game.lakes.statistics(),"trees":game.vegetation.renderer.roots.size()})
 print("BOUNDARY_COST ",label," ",JSON.stringify(stats))
func run():
 game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 if not game.has_meta("water_bucket_review_ready"):quit(1);return
 game.set_process(false);game.set_physics_process(false);game._clear_motion();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 var entry:Dictionary=game.lakes._lakes.values()[0];var center:Vector3=entry.seed
 await sample("above",Vector3(center.x,entry.level+2,center.z+6),Vector3(center.x,entry.level,center.z))
 await sample("underwater",Vector3(center.x,entry.level-1.2,center.z+4),Vector3(center.x,entry.level-1.3,center.z-4))
 var presentation:Dictionary=load("res://addons/presentation/fullscreen_policy.gd").measurement(root)
 if not presentation.fair_graphical_sample or Engine.max_fps!=60:failures+=1
 var file:=FileAccess.open("res://reports/water_boundary_cost.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"failures":failures,"phases":phases,"presentation":presentation,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"scope":"Two fixed views, 120 measured frames each after 60 settled frames. Viewport timers, not whole-device utilization, power or endurance."},"  "));file.close()
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),false)
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_BOUNDARY_COST failures=",failures);quit(failures)

# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 var started:=Time.get_ticks_msec()
 var refill_seen:=false
 var deadline:=Time.get_ticks_msec()+90000
 while game.loading_active and Time.get_ticks_msec()<deadline:
  await process_frame
  if game.lakes.water!=null:refill_seen=refill_seen or game.lakes.statistics().fill_active
 if game.loading_active or game.terrain.backend.world_generator not in [12,13]:quit(1);return
 var load_ms:=Time.get_ticks_msec()-started
 game.set_physics_process(false);game._clear_motion()
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[game.terrain.backend.world_seed,game.terrain.backend.world_generator]))
 var d:PackedByteArray=core.execute(Codec.command(27))
 var center:=Vector3(d.decode_float(48),d.decode_float(44),d.decode_float(56))
 game.teleport(center+Vector3(72,0,20))
 deadline=Time.get_ticks_msec()+60000
 while (game.loading_active or not game.lakes.statistics().render_ready) and Time.get_ticks_msec()<deadline:await process_frame
 var stats:Dictionary=game.lakes.statistics()
 stats["cached_load_ms"]=load_ms;stats["arrival_ms"]=Time.get_ticks_msec()-started-load_ms;stats["refill_seen"]=refill_seen
 var ok:bool=not game.loading_active and stats.render_ready and stats.ready==4 and not stats.capacity_reached and not stats.fill_active and not refill_seen
 for x in [-50,0,50]:ok=ok and game.lakes.depth_at(center+Vector3(x,-.5,0))>0
 ok=ok and game.lakes.depth_at(center+Vector3(85,-.5,0))==0
 game.set_physics_process(false);game.camera.global_position=center+Vector3(72,15,20);game.camera.look_at(center)
 for frame in 120:await process_frame
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 var rows:Array=[]
 var stages:Dictionary={}
 game.terrain.stage_measured.connect(func(label:String,ms:float):stages[label]=maxf(float(stages.get(label,0)),ms))
 var frames:Array[float]=[]
 var previous:=Time.get_ticks_usec()
 for frame in 180:
  await process_frame
  var now:=Time.get_ticks_usec();frames.append(float(now-previous)/1000.0);previous=now
  rows.append({"frame_ms":frames[-1],"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"engine_process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"engine_physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"cap":Engine.max_fps,"focused":game.app_focused,"queued":game.terrain.backend.queued(),"worker":game.terrain.backend.status(),"ground_dirty":game.ground_cover._dirty.size(),"ground_requests":game.ground_cover._requests.size(),"ground_job":not game.ground_cover._scatter_job.is_empty(),"ecosystem_us":game.ecosystem.last_process_us,"water_process_us":game.lakes.last_process_us,"ground_process_us":game.ground_cover.last_process_us,"paging_process_us":game.model_paging.last_process_us if game.model_paging!=null else 0,"forest_process_us":game.vegetation.last_process_us,"vegetation_us":game.vegetation.renderer.stats.get("update_us",0),"stages":stages.duplicate()})
  stages.clear()
 frames.sort();stats["stationary_frame_p95_ms"]=frames[171];stats["stationary_frame_max_ms"]=frames[179]
 stats["frame_samples"]=rows
 if "--lake-profile-isolation" in OS.get_cmdline_user_args():
  game.process_mode=Node.PROCESS_MODE_DISABLED
  for frame in 30:await process_frame
  var paused:Array=[]
  previous=Time.get_ticks_usec()
  for frame in 120:
   await process_frame
   var now:=Time.get_ticks_usec()
   paused.append({"frame_ms":(now-previous)/1000.0,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())});previous=now
  stats["paused_world_samples"]=paused
  game.process_mode=Node.PROCESS_MODE_INHERIT

 if "--lake-native-isolation" in OS.get_cmdline_user_args():
  var native_nodes:Array=[]
  for node:Node in game.find_children("*","",true,false):
   if node.get_class() in ["NativeBlockWorld","NativeStaticBatch"]:
    native_nodes.append({"node":node,"process":node.is_processing(),"physics":node.is_physics_processing()})
  stats["isolated_native_nodes"]=native_nodes.size()
  for entry:Dictionary in native_nodes:entry.node.set_process(false);entry.node.set_physics_process(false)
  stats["native_disabled_samples"]=await sample_frames(120)
  for entry:Dictionary in native_nodes:entry.node.set_process(entry.process);entry.node.set_physics_process(entry.physics)
  game.set_process(false)
  stats["controller_disabled_samples"]=await sample_frames(120)
  game.set_process(true)
  stats["restored_samples"]=await sample_frames(120)
 var submerged_roots:=0
 var visible_roots:=0
 for packed:Array in game.ground_cover.resident.values():
  for species:Dictionary in packed:
   var poses:PackedFloat32Array=species.transforms
   for i in range(0,poses.size(),12):
    var root_position:=Vector3(poses[i+3],poses[i+7],poses[i+11])
    visible_roots+=1
    if game.lakes.depth_at(root_position+Vector3.UP*.08)>0:submerged_roots+=1
 stats["visible_ground_roots"]=visible_roots;stats["submerged_ground_roots"]=submerged_roots
 ok=ok and visible_roots>0 and submerged_roots==0
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/regional_lake_world.png")
 var file:=FileAccess.open("res://reports/regional_lake_world.json",FileAccess.WRITE);file.store_string(JSON.stringify(stats,"  "));file.close()
 print("REGIONAL_LAKE_WORLD failures=",0 if ok else 1," stats=",JSON.stringify(stats))
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(0 if ok else 1)

func sample_frames(count:int)->Array:
 for frame in 20:await process_frame
 var samples:Array=[]
 var previous:=Time.get_ticks_usec()
 for frame in count:
  await process_frame
  var now:=Time.get_ticks_usec()
  samples.append({"frame_ms":(now-previous)/1000.0,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())});previous=now
 return samples

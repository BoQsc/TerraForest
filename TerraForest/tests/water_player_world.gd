# SPDX-License-Identifier: 0BSD
extends SceneTree
class BrushProfileBackend extends "res://addons/volumetric_terrain/terrain_backend.gd":
 var stages:Array[float]=[0.0,0.0,0.0,0.0]
 var tiles_profiled:=0
 var measuring:=false
 var light_start:=PackedByteArray()
 var handoff:Dictionary={}
 var staging_frames:Array[Dictionary]=[]
 var worker_done_us:=0
 func poll()->Array[Dictionary]:
  var results_batch:=super.poll()
  var received:=Time.get_ticks_usec()
  for result in results_batch:
   match result.kind:
    "edit_begin":
     handoff.clear()
     staging_frames.clear()
     worker_done_us=0
    "edit_chunk":
     handoff[result.key]={"worker_us":result.profile_ready_us,"received_us":received}
    "edit_done":worker_done_us=result.worker_finished_us
  return results_batch
 func _push(result:Dictionary)->void:
  if result.kind=="edit_begin":
   stages.fill(0.0)
   tiles_profiled=0
   measuring=true
   light_start=_call(Codec.command(15))
  elif result.kind=="edit_chunk":
   result.profile_ready_us=Time.get_ticks_usec()
  elif result.kind=="edit_done":
   var light:=_call(Codec.command(15))
   var counts:={}
   var labels:=["rays","ray_steps","unresolved","probe_hits"]
   for i in labels.size():counts[labels[i]]=(light.decode_u32(12+4*i)-light_start.decode_u32(12+4*i)) & 0xffffffff
   print("AUTHORING_NATIVE_MS ",JSON.stringify({"tiles":tiles_profiled,"extraction":stages[0],"simplification":stages[1],"blocks":stages[2],"shading":stages[3],"build":result.build_total_ms,"lighting":counts}))
   measuring=false
  super._push(result)
 func _build(key:Vector3i,base:bool,build_epoch:int,relight:bool=false,bottoms:Array=[],foreground:bool=false)->Dictionary:
  var result:=super._build(key,base,build_epoch,relight,bottoms,foreground)
  if measuring and foreground and not result.has("error"):
   var region:Dictionary=result.get("region_stages",{})
   if region.has("native_ms"):
    for i in 4:stages[i]+=region.native_ms[i]
   elif not result.get("cached",false) and not result.has("bricks"):
    var profile:=_call(Codec.command(19))
    for i in 4:stages[i]+=profile.decode_float(12+i*4)
   tiles_profiled+=1
  return result
# Compact phase attribution without full trace output or desktop interaction.
class FramePhases extends Node:
 var sample:Dictionary={}
 var started:=0;var ended:=0;var drawing:=0;var previous:=0
 var usage:RefCounted;var prior_work:=PackedInt64Array()
 func _ready()->void:
  process_priority=1000000
  usage=ClassDB.instantiate("NativeResourceUsage")
  get_tree().process_frame.connect(begin)
  RenderingServer.frame_pre_draw.connect(pre_draw)
  RenderingServer.frame_post_draw.connect(post_draw)
 func begin()->void:started=Time.get_ticks_usec()
 func _process(_delta:float)->void:ended=Time.get_ticks_usec()
 func pre_draw()->void:drawing=Time.get_ticks_usec()
 func post_draw()->void:
  var now:=Time.get_ticks_usec()
  if previous>0:sample={"before_process_ms":(started-previous)/1000.0,"process_ms":(ended-started)/1000.0,"after_process_ms":(drawing-ended)/1000.0,"draw_ms":(now-drawing)/1000.0}
  if usage!=null and OS.get_thread_caller_id()==OS.get_main_thread_id():
   var work:PackedInt64Array=usage.thread_work()
   if prior_work.size()==2 and work.size()==2 and prior_work[1]>=0 and work[1]>=prior_work[1]:sample.thread_cpu_ms=(work[1]-prior_work[1])/1000.0
   prior_work=work
  previous=now
 func _exit_tree()->void:
  if RenderingServer.frame_pre_draw.is_connected(pre_draw):RenderingServer.frame_pre_draw.disconnect(pre_draw)
  if RenderingServer.frame_post_draw.is_connected(post_draw):RenderingServer.frame_post_draw.disconnect(post_draw)
# Sample between sibling subtrees in scene processing order to locate work
# outside the game controller's explicit timers. Enabled only by the route driver.
class RouteProcessMarker extends Node:
 var observe:Callable
 func _process(_delta:float)->void:observe.call()
var route_markers:Array[Node]=[]
var route_section_us:Dictionary={}
var route_trader_section:=""
var route_marker_time:=0
func mark_route_section(label:String)->void:
 var now:=Time.get_ticks_usec()
 route_section_us[label]=now-route_marker_time
 route_marker_time=now
func install_route_markers()->void:
 for child:Node in game.get_children():
  var marker:=RouteProcessMarker.new()
  var script:Script=child.get_script()
  var label:=str(child.name)+" "+(script.resource_path if script else child.get_class())
  if child==game.trader:route_trader_section=label
  marker.observe=mark_route_section.bind(label)
  route_markers.append(marker)
  game.add_child(marker)
  game.move_child(marker,child.get_index()+1)
var exploration_terrain_stages:Dictionary={}
func record_exploration_stage(label:String,ms:float)->void:
 exploration_terrain_stages[label]=float(exploration_terrain_stages.get(label,0.0))+ms
var frame_phases:FramePhases
var game:Node3D
var failures:=0
var evidence:=""
var slot:="Amber_Pines"
func check_lake_region_seams(center:Vector3,level:float,label:String)->void:
 timing_diagnostic("mesh seam probes")
 var sampled:=0
 var largest_step:=0.0
 for axis:int in [0,2]:
  for region_offset in range(-4,5):
   for lane:int in [-3,0,3]:
    var at:=Vector3(center.x,level+2,center.z)
    at[axis]=(floorf(center[axis]/4)+region_offset)*4
    at[2-axis]+=lane
    var offset:=Vector3.ZERO
    offset[axis]=.00025
    var left:Dictionary=game.lakes.water.raycast_surface(at-offset,at-offset-Vector3.UP*4)
    var right:Dictionary=game.lakes.water.raycast_surface(at+offset,at+offset-Vector3.UP*4)
    if not left.get("hit",false) or not right.get("hit",false):continue
    if left.normal.y<.8 or right.normal.y<.8:continue
    sampled+=1
    largest_step=maxf(largest_step,absf(left.point.y-right.point.y))
 print("LAKE_REGION_SEAMS ",label," wet_pairs=",sampled," max_step_m=",largest_step)
 check(sampled>=10 and largest_step<=.0015,label+" adjacent lake regions meet across the open water surface")
func check_crater_coverage(center:Vector3,level:float,label:String)->void:
 timing_diagnostic("shore contact probes")
 var sampled:=0;var missing:Array=[]
 for x in range(-5,6):
  for z in range(-5,6):
   if x*x+z*z>25:continue
   var p:=Vector3(center.x+x*.5,level-.5,center.z+z*.5)
   var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*8,p-Vector3.UP*8,1))
   if hit.is_empty() or hit.position.y>p.y-.1:continue
   sampled+=1
   if game.lakes.depth_at(p)<.2:
    var live:Dictionary=game.lakes.water.cell_geometry(p)
    missing.append({"point":str(p),"floor":hit.position.y,"region":str(Vector3i((p/4).floor())),"resident":not live.is_empty(),"capacity_ml":live.get("capacity_ml",0),"head":live.get("head",0)})
 print("CRATER_COVERAGE ",label," sampled=",sampled," missing=",JSON.stringify(missing))
 check(sampled>10 and missing.is_empty(),label+" water covers every sampled excavated air point below its level")
 var surface:Dictionary=game.lakes.water.raycast_surface(Vector3(center.x,level+1,center.z),Vector3(center.x,level-1,center.z))
 if label.begins_with("sea"):
  var column:=Vector2i(floori(center.x/4),floori(center.z/4))
  var mask:PackedByteArray=game.lakes._surrounding_ocean.last_coverage
  var detailed:=mask.size()==250000 and mask[column.x+500*column.y]!=0
  var rendered_hits:Array[float]=[]
  for layer in range(floori((level-1)/4),floori((level+1)/4)+1):
   var instance:MeshInstance3D=game.lakes._meshes.get(Vector3i(column.x,layer,column.y))
   if instance==null or not instance.is_visible_in_tree():continue
   var faces:=instance.mesh.get_faces()
   var origin:=instance.to_local(Vector3(center.x,level+1,center.z))
   var end:=instance.to_local(Vector3(center.x,level-1,center.z))
   for i in range(0,faces.size(),3):
    var hit=Geometry3D.segment_intersects_triangle(origin,end,faces[i],faces[i+1],faces[i+2])
    if hit!=null:rendered_hits.append(instance.to_global(hit).y)
  print("SEA_PUBLICATION ",label," center=",center," detail=",detailed," mesh_hits=",rendered_hits," query=",surface)
 if not surface.get("hit",false):check(false,label+" shoreline reference surface exists");return
 var water_level:float=surface.point.y
 var contacts:=0;var gaps:Array=[]
 for angle in 48:
  var direction:=Vector3(cos(TAU*angle/48.0),0,sin(TAU*angle/48.0))
  var start:=Vector3(center.x,water_level-.01,center.z)
  var bank:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,start+direction*5,1))
  if bank.is_empty():continue
  contacts+=1
  var probe:Vector3=bank.position-direction*.02
  var top:Dictionary=game.lakes.water.raycast_surface(Vector3(probe.x,water_level+.3,probe.z),Vector3(probe.x,water_level-.3,probe.z))
  if not top.get("hit",false) or absf(top.point.y-water_level)>.025:
   var floor_hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(probe+Vector3.UP*2,probe-Vector3.UP*2,1))
   gaps.append({"point":str(probe),"water_hit":top.get("hit",false),"height":top.get("point",Vector3.INF).y,"reference_y":water_level,"floor_y":floor_hit.get("position",Vector3.INF).y,"depth_at_probe":game.lakes.depth_at(probe),"angle_index":angle})
 print("SHORE_CONTACT ",label," sampled=",contacts," gaps=",JSON.stringify(gaps))
 check(contacts>=10 and gaps.is_empty(),label+" water reaches within 2 cm of the actual terrain waterline")
var blast_metrics:Dictionary={}
var terrain_published_us:=0
var terrain_published_frame:=0
var water_draw_frames:=0
var terrain_admitted_us:=0
var blast_timeline:Array[Dictionary]=[]
var blast_started:=0
var blast_last_state:=""
func terrain_published(_bounds:AABB,_revision:int)->void:
 if action_started_us and not timing_phase.is_empty() and not terrain_published_us and game.terrain.edit_accepted_us>=action_started_us:
  terrain_admitted_us=game.terrain.edit_accepted_us
  terrain_published_us=Time.get_ticks_usec()
  terrain_published_frame=Engine.get_frames_drawn()
var timing_phase:=""
var timing_local_ms:=-1.0
var action_started_us:=0
var local_draw_us:=0
var audit_meshes_before:Dictionary={}
var audit_meshes_after:Dictionary={}
var audit_edit_areas:Array[AABB]=[]
func resident_render_meshes()->Dictionary:
 var meshes:Dictionary={}
 for coord:Vector3i in game.lakes._meshes:
  meshes[coord]=game.lakes._meshes[coord].mesh
 return meshes

func compare_render_owners()->Dictionary:
 # Compare the geometry actually submitted to the renderer. Read GPU-backed
 # arrays only after the timed action. Held resources also cover removals.
 var coordinates:=audit_meshes_before.keys()
 for coord:Vector3i in audit_meshes_after:
  if not audit_meshes_before.has(coord):coordinates.append(coord)
 var owners:Array=[]
 for coord:Vector3i in coordinates:
  var previous:ArrayMesh=audit_meshes_before.get(coord)
  var current:ArrayMesh=audit_meshes_after.get(coord)
  if previous==current:continue
  var bounds:=AABB(Vector3(coord)*4,Vector3.ONE*4)
  var inside:=false
  for area in audit_edit_areas:
   if bounds.intersects(area):inside=true;break
  var change:="added" if previous==null else "removed" if current==null else "changed"
  var entry:Dictionary={"coordinate":str(coord),"intersects_edit":inside}
  if previous!=null and current!=null:
   var old_arrays:=previous.surface_get_arrays(0)
   var new_arrays:=current.surface_get_arrays(0)
   if old_arrays==new_arrays:change="identical"
   elif old_arrays[Mesh.ARRAY_INDEX]==new_arrays[Mesh.ARRAY_INDEX]:
    var from_vertices:PackedVector3Array=old_arrays[Mesh.ARRAY_VERTEX]
    var to_vertices:PackedVector3Array=new_arrays[Mesh.ARRAY_VERTEX]
    if from_vertices.size()==to_vertices.size():
     var displacement:=Vector3.ZERO
     var min_dy:=INF
     var max_dy:=-INF
     for i in from_vertices.size():
      var offset:=to_vertices[i]-from_vertices[i]
      displacement=displacement.max(offset.abs())
      min_dy=minf(min_dy,offset.y);max_dy=maxf(max_dy,offset.y)
     entry.max_vertex_displacement_m=[displacement.x,displacement.y,displacement.z]
     entry.uniform_vertical_translation=(from_vertices.size()>0 and displacement.x==0 and displacement.z==0 and min_dy==max_dy
      and old_arrays[Mesh.ARRAY_NORMAL]==new_arrays[Mesh.ARRAY_NORMAL]
      and old_arrays[Mesh.ARRAY_COLOR]==new_arrays[Mesh.ARRAY_COLOR]
      and old_arrays[Mesh.ARRAY_TEX_UV]==new_arrays[Mesh.ARRAY_TEX_UV])
  entry.geometry=change
  owners.append(entry)
 return {"edit_areas":str(audit_edit_areas),"replaced":owners}
func measure_local_draw()->void:
 if timing_phase.is_empty() or not action_started_us or local_draw_us or not terrain_published_us:return
 if game.lakes._local_response_started_us>=action_started_us and not game.lakes._local_response_pending and not game.lakes._local_publication_pending:
  local_draw_us=Time.get_ticks_usec()
  water_draw_frames=1+Engine.get_frames_drawn()-terrain_published_frame
var timing_previous:=0
var timing_frames:Array[float]=[]
var timing_play_frames:Array[float]=[]
var timing_diagnostics:PackedStringArray=[]
var timing_capture_end:=0
var timing_worst_play:Dictionary={}
func timing_diagnostic(label:String)->void:
 if not timing_phase.is_empty() and not timing_diagnostics.has(label):timing_diagnostics.append(label)
var timing_water:Array[float]=[]
var timing_stages:Dictionary={}
var timing_worst:Array[Dictionary]=[]
var timing_totals:Dictionary={}
var timing_water_worst:Dictionary={}
var timing_pipeline_draw:=0.0
var timing_pipeline_specialization:=0.0
func timing_stage(label:String,ms:float)->void:
 if not timing_phase.is_empty():
  timing_stages[label]=float(timing_stages.get(label,0))+ms
  timing_totals[label]=float(timing_totals.get(label,0))+ms
func start_timing(label:String)->void:
 if "--water-owner-audit" in OS.get_cmdline_user_args():
  audit_meshes_before=resident_render_meshes()
  audit_meshes_after.clear();audit_edit_areas.clear()
 if frame_phases==null:frame_phases=FramePhases.new();root.add_child(frame_phases)
 if "--qualification-route" not in OS.get_cmdline_user_args() and "--water-immediate-contact" not in OS.get_cmdline_user_args():
  game.max_fps=0;game.background_fps=0;Engine.max_fps=0
  if DisplayServer.get_name()!="headless":DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 game.structures.blocks.set_process_profiling_enabled(true)
 terrain_published_us=0;terrain_admitted_us=0;action_started_us=0;local_draw_us=0;blast_started=Time.get_ticks_usec();blast_timeline.clear();blast_last_state=""
 if DisplayServer.get_name()!="headless" and not RenderingServer.frame_post_draw.is_connected(measure_local_draw):
  RenderingServer.frame_post_draw.connect(measure_local_draw)
 if not game.terrain.region_changed.is_connected(terrain_published):game.terrain.region_changed.connect(terrain_published)
 timing_phase=label;timing_local_ms=-1;timing_frames.clear();timing_water.clear();timing_previous=Time.get_ticks_usec()
 timing_play_frames.clear();timing_diagnostics.clear();timing_worst_play={}
 timing_stages.clear();timing_worst.clear();timing_totals.clear();timing_water_worst.clear()
 timing_pipeline_draw=Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)
 timing_pipeline_specialization=Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)
 if DisplayServer.get_name()!="headless":RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 if not game.terrain.stage_measured.is_connected(timing_stage):game.terrain.stage_measured.connect(timing_stage)
 if not process_frame.is_connected(sample_timing):process_frame.connect(sample_timing)
func sample_timing()->void:
 if timing_phase.is_empty():return
 var now:=Time.get_ticks_usec()
 var pipelines:=Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)
 var specializations:=Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)
 timing_worst.append({"frame_ms":(now-timing_previous)/1000.0,"stages":timing_stages.duplicate(),"water_main_us":game.lakes.last_process_us,"pipeline_draw_delta":pipelines-timing_pipeline_draw,"pipeline_specialization_delta":specializations-timing_pipeline_specialization,"render_setup_ms":RenderingServer.get_frame_setup_time_cpu(),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000})
 timing_pipeline_draw=pipelines;timing_pipeline_specialization=specializations
 timing_worst.back().sample_end_unix_ms=Time.get_unix_time_from_system()*1000
 timing_worst.back().frame_phases=frame_phases.sample.duplicate()
 timing_worst.back().other_main_us={"handgun":game.tool_view.human.last_handgun_process_us,"forest":game.vegetation.last_process_us,"ecosystem":game.ecosystem.last_process_us,"ground_cover":game.ground_cover.last_process_us,"model_paging":game.model_paging.last_process_us if game.model_paging!=null else 0}
 timing_worst.back().native_blocks=game.structures.blocks.process_frame_profile()
 if game.structures._model_horizon!=null:timing_worst.back().model_horizon=game.structures._model_horizon.process_frame_profile()
 timing_worst.back().water_work_us=game.lakes.last_process_work.duplicate()
 timing_worst.back().handgun_work=game.tool_view.human.last_handgun_work.duplicate()
 var state:Dictionary=game.lakes.water.runtime_state()
 state.capture=game.lakes.last_process_work.get("equilibrium_capture",0)>0
 state.equilibrium_worker=game.lakes._equilibrium_task>=0
 state.mesh_worker=game.lakes._mesh_task>=0
 state.commit_frame_mesh_dispatch=game.lakes.last_process_work.get("local_mesh_dispatched",false)
 state.published=game.lakes._published_mesh_batch_id
 state.local_response=game.lakes._local_response_pending
 state.local_publication=game.lakes._local_publication_pending
 state.terrain_pending=game.terrain.pending_edit
 var signature:=JSON.stringify(state)
 if signature!=blast_last_state and blast_timeline.size()<2000:
  blast_last_state=signature;state.ms=(Time.get_ticks_usec()-blast_started)/1000.0
  blast_timeline.append(state)
 timing_worst.back().publication=game.lakes.last_publication_work.duplicate()
 if not capture_phase.is_empty() or timing_capture_end>timing_previous:timing_diagnostic("image capture")
 var frame:Dictionary=timing_worst.back()
 frame.diagnostics=timing_diagnostics.duplicate()
 if timing_diagnostics.is_empty():
  timing_play_frames.append(frame.frame_ms)
  if frame.frame_ms>timing_worst_play.get("frame_ms",0):timing_worst_play=frame
 timing_diagnostics.clear()
 if game.lakes.last_process_us>timing_water_worst.get("water_main_us",0):timing_water_worst=timing_worst.back().duplicate(true)
 timing_worst.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.frame_ms>b.frame_ms)
 if timing_worst.size()>5:timing_worst.resize(5)
 timing_stages.clear()
 timing_frames.append((now-timing_previous)/1000.0);timing_water.append(float(game.lakes.last_process_us));timing_previous=now
func finish_timing()->void:
 blast_metrics[timing_phase]={"frames":timing_frames.size(),"frame_p95_ms":percentile(timing_frames,.95),"frame_p99_ms":percentile(timing_frames,.99),"frame_max_ms":timing_frames.back() if not timing_frames.is_empty() else 0,"water_main_p95_us":percentile(timing_water,.95),"water_main_max_us":timing_water.back() if not timing_water.is_empty() else 0}
 blast_metrics[timing_phase].water_after_terrain_ms=(Time.get_ticks_usec()-terrain_published_us)/1000.0 if terrain_published_us else -1
 blast_metrics[timing_phase].timeline=blast_timeline.duplicate(true)
 blast_metrics[timing_phase].outside_diagnostics={"frames":timing_play_frames.size(),"p99_ms":percentile(timing_play_frames,.99),"worst":timing_worst_play}
 blast_metrics[timing_phase].local_response_ms=timing_local_ms
 blast_metrics[timing_phase].action_to_local_draw_ms=(local_draw_us-action_started_us)/1000.0 if local_draw_us else -1
 if terrain_admitted_us and terrain_published_us and local_draw_us:
  blast_metrics[timing_phase].action_to_terrain_admission_ms=(terrain_admitted_us-action_started_us)/1000.0
  blast_metrics[timing_phase].terrain_admission_to_publication_ms=(terrain_published_us-terrain_admitted_us)/1000.0
  blast_metrics[timing_phase].terrain_publication_to_local_draw_ms=(local_draw_us-terrain_published_us)/1000.0
  blast_metrics[timing_phase].terrain_to_water_frames=water_draw_frames
 if "--two-frame-edits" in OS.get_cmdline_user_args():
  check(local_draw_us>0 and water_draw_frames<=2 and local_draw_us-terrain_admitted_us<=33334,timing_phase+" draws the changed water within two frames of the terrain edit")
 blast_metrics[timing_phase].worst_frames=timing_worst.duplicate(true)
 blast_metrics[timing_phase].stage_totals=timing_totals.duplicate()
 blast_metrics[timing_phase].water_worst=timing_water_worst.duplicate(true)
 if not audit_edit_areas.is_empty():
  blast_metrics[timing_phase].render_owner_audit=compare_render_owners()
  audit_meshes_before.clear();audit_meshes_after.clear()
 timing_phase=""
 FileAccess.open(evidence.path_join("normal_gameplay_blast_performance.json"),FileAccess.WRITE).store_string(JSON.stringify(blast_metrics,"  "))
func local_response(point:Vector3,label:String)->void:
 var deadline:=Time.get_ticks_msec()+10000
 while Time.get_ticks_msec()<deadline:
  if terrain_published_us>0 and game.lakes._local_response_started_us>=blast_started and not game.lakes._local_response_pending and not game.lakes._local_publication_pending:
   var latency:float=game.lakes._local_response_us/1000.0
   timing_diagnostic("first publication probes")
   if "--water-owner-audit" in OS.get_cmdline_user_args():
    audit_meshes_after=resident_render_meshes()
    audit_edit_areas=game.terrain.water_edit_areas(AABB())
   timing_local_ms=latency
   print("LOCAL_WATER_RESPONSE ",label," ms=",latency," wider_pending=",game.lakes.water.runtime_state().settling_regions)
   print("LOCAL_WATER_SOLVE ",label," ",JSON.stringify(game.lakes.statistics().get("equilibrium_result",{})))
   if label=="lake":
    var packet:=PackedByteArray()
    var first_surface:Array=[]
    if "--water-local-snapshot" in OS.get_cmdline_user_args():
     packet=game.lakes.water.capture_local_snapshot(AABB(point-Vector3(12,8,12),Vector3(24,12,24)))
     check(not packet.is_empty() and packet.size()<8*1024*1024,"Local replay fits its declared eight MiB evidence allowance")
    for axis:Vector3 in [Vector3.RIGHT,Vector3.BACK]:
     var heads:Array=[]
     for offset in range(-16,17):
      var sample:=point+axis*offset*.5+Vector3.UP*2
      var hit:Dictionary=game.lakes.water.raycast_surface(sample,sample-Vector3.UP*5)
      if not packet.is_empty():first_surface.append({"from":sample,"height":hit.point.y if hit.get("hit",false) else null})
      heads.append([offset*.5,str(hit)])
     print("LOCAL_WATER_HEADS origin=",point," axis=",axis," ",JSON.stringify(heads))
    if not packet.is_empty() and packet.size()<8*1024*1024:
     FileAccess.open(evidence.path_join("local_response.water_regions"),FileAccess.WRITE).store_var({"point":point,"snapshot":packet,"first_surface":first_surface})
   var probe:=point-Vector3.UP
   if label=="mining":
    var floor_hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*3,point-Vector3.UP*5,1))
    check(not floor_hit.is_empty() and floor_hit.position.y<point.y-.35,"Mining lowers the actual terrain collision surface")
    if not floor_hit.is_empty():probe.y=(floor_hit.position.y+point.y-.25)*.5
   print("LOCAL_WATER_PROBE ",label," point=",probe," depth=",game.lakes.depth_at(probe)," edit=",game.terrain.water_occupancy_edit_bounds(AABB()))
   check(game.lakes.depth_at(probe)>.2,label+" crater has published water before wider settling finishes")
   check(latency<=250,label+" local response publishes within 250 ms of terrain publication")
   return
  await process_frame
 check(false,label+" local response completed")
func bucket_response_cases(lake:Dictionary)->void:
 var inventory=game.player_hud.inventory
 if not game.player_hud.equip_item(401):
  check(inventory.grant_items(PackedInt64Array([401,1]),inventory.snapshot().revision).ok,"An empty bucket enters the ordinary inventory")
 check(game.player_hud.equip_item(401),"Ordinary empty bucket equipped")
 var bucket_slot:int=game.player_hud.active_slot
 var point:=Vector3(lake.seed.x,lake.level,lake.seed.z)
 var before:int=owned_amount();var results:Array=[]
 for action in 4:
  var pour:bool=action%2==1
  if action==2:
   var background_deadline:=Time.get_ticks_msec()+10000
   while Time.get_ticks_msec()<background_deadline:
    if game.lakes._mesh_task>=0 and not game.lakes.water.runtime_state().urgent_batch and game.lakes.water.statistics().relaxation_rollback_bytes>0:break
    await process_frame
   check(game.lakes._mesh_task>=0 and game.lakes.water.statistics().relaxation_rollback_bytes>0,"A wider relaxation is actually meshing when the next bucket edit interrupts it")
  var began:=Time.get_ticks_usec()
  var result:Dictionary=game.lakes.bucket(point+Vector3.UP*2,point-Vector3.UP,pour,inventory,bucket_slot,inventory.snapshot().revision)
  check(result.get("ok",false) or result.get("pending",false),"Actual-game bucket action accepted: "+str(result.get("reason","")))
  var deadline:=Time.get_ticks_msec()+5000
  while Time.get_ticks_msec()<deadline and (not game.lakes._pending_bucket.is_empty() or game.lakes._local_response_pending or game.lakes._local_publication_pending):await process_frame
  var elapsed:float=(Time.get_ticks_usec()-began)/1000.0
  var expected:=0 if pour else 1000000
  check(inventory.snapshot().slots[bucket_slot].water_ml==expected,"Bucket inventory agrees with the completed transfer")
  check(owned_amount()==before-expected,"Bucket transfer preserves world plus carried quantity exactly")
  check(elapsed<=100,"Bucket "+("pour" if pour else "scoop")+" publishes within 100 ms, including during wider relaxation")
  results.append({"pour":pour,"interrupting_mesh":action>=2,"visible_ms":elapsed,"pending":game.lakes.water.runtime_state().settling_regions})
  print("LOCAL_BUCKET_RESPONSE ",JSON.stringify(results.back()))
 FileAccess.open(evidence.path_join("bucket_response.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
func mining_response_case(lake:Dictionary)->void:
 check(await ready("before_mining"),"Previous edits settle before the mining measurement")
 var above:=Vector3(lake.seed.x+2,lake.level+2,lake.seed.z)
 var ground:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(above,above-Vector3.UP*20,1))
 check(not ground.is_empty(),"Actual lake floor is available for mining")
 if ground.is_empty():return
 var before:int=owned_amount()
 check(game.player_hud.equip_item(1),"Ordinary pickaxe equipped for the mining impact")
 var cell:=Vector3i((ground.position-ground.normal*.05).floor())
 var target:Dictionary={"kind":"terrain","key":"terrain:%d:%d:%d"%[cell.x,cell.y,cell.z],"health":game.world_attack.Durability.WORLD.terrain,"material":"stone","name":"Terrain","position":ground.position,"normal":ground.normal}
 game.terrain.set_interaction_target(ground.position)
 start_timing("lake_mining")
 action_started_us=Time.get_ticks_usec()
 check(game.world_attack.apply_target(target) and game.terrain.pending_edit,"Ordinary pickaxe damage and contact-mining stroke are admitted in the saved game")
 await local_response(ground.position+Vector3.UP*.25,"mining")
 check(await ready("mining"),"Mining completes wider relaxation")
 finish_timing()
 check(owned_amount()==before,"Mining conserves every owned millilitre")
func capture(label:String,center:Vector3,level:float,underwater:bool=false)->void:
 if DisplayServer.get_name()=="headless" or "--water-no-captures" in OS.get_cmdline_user_args():return
 capture_phase="capture "+label
 var processing:=game.is_processing();var physics:=game.is_physics_processing()
 var water_processing:bool=game.lakes.is_processing()
 game.lakes.set_process(false)
 var captures:Array=[]
 var camera_transform:Transform3D=game.camera.global_transform
 var tool_visible:bool=game.tool_view.visible
 game.set_process(false);game.set_physics_process(false);game.tool_view.visible=false
 game.camera.global_position=center+Vector3(-4,level-center.y+(-1 if underwater else 3),6)
 game.camera.look_at(Vector3(center.x,level-1,center.z),Vector3.UP)
 if underwater:
  game.camera.global_position=Vector3(center.x,level-1,center.z)
  game.camera.look_at(game.camera.global_position+Vector3(2,.3,0),Vector3.UP)
  check(game.lakes.depth_at(game.camera.global_position)>.2,"Underwater capture camera is inside the excavated water volume")
 game.combat.effects.step(.7,true);game.water_camera.update()
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 captures.append([root.get_texture().get_image(),evidence.path_join(label+".png")])
 if not underwater:
  # Keep the second lake view on the water side of Cedar Vale's bank trees.
  var reverse_offset:=Vector3(5,5,4) if "lake" in label else Vector3(5,1.5,-4)
  game.camera.global_position=Vector3(center.x,level,center.z)+reverse_offset
  game.camera.look_at(Vector3(center.x,level-.6,center.z),Vector3.UP)
  game.water_camera.update()
  for frame in 4:await process_frame
  await RenderingServer.frame_post_draw
  captures.append([root.get_texture().get_image(),evidence.path_join(label+"_reverse.png")])
 game.camera.global_transform=camera_transform;game.water_camera.update()
 game.tool_view.visible=tool_visible
 game.set_process(processing);game.set_physics_process(physics)
 game.lakes.set_process(water_processing)
 # Encode only after both angles have been captured. PNG compression must not
 # become a fake low-FPS sample between the two views of the frozen state.
 for entry:Array in captures:entry[0].save_png(entry[1])
 timing_capture_end=Time.get_ticks_usec()
 if route_started:
  # The interval containing PNG encoding ends on the next frame.
  await process_frame
 capture_phase=""
func _initialize()->void:run.call_deferred()
func owned_amount()->int:
 timing_diagnostic("quantity snapshot")
 # Pristine ocean residency can retire after travel; it is not owned lake mass.
 # Use the production save snapshot's non-regenerable quantity, outside timing.
 var measure:bool=not timing_phase.is_empty() and frame_phases.usage!=null
 var before_cpu:PackedInt64Array=frame_phases.usage.thread_work() if measure else PackedInt64Array()
 var started:=Time.get_ticks_usec()
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var frozen:Variant=game.lakes.water.capture_storage_snapshot(catalog)
 var bytes:PackedByteArray=frozen if frozen is PackedByteArray else frozen.serialize_snapshot()
 if measure:
  timing_stage("test-only quantity snapshot",(Time.get_ticks_usec()-started)/1000.0)
  var after_cpu:PackedInt64Array=frame_phases.usage.thread_work()
  if before_cpu.size()==2 and after_cpu.size()==2 and before_cpu[1]>=0:
   timing_stage("snapshot main-thread CPU",(after_cpu[1]-before_cpu[1])/1000.0)
 check(bytes.size()>=32 and bytes.decode_u32(0)==0x31575256,"Owned-quantity snapshot is complete")
 return bytes.decode_u64(16) if bytes.size()>=32 else -1
func gameplay_barrel(point:Vector3)->int:
 # Exercise paid placement and ordinary projectile damage. Only input ownership
 # is supplied by the offscreen controller; water/combat scheduling stays normal.
 game.app_focused=true;game.player_view.entry.finish()
 game.combat.action_input_owned=func()->bool:return true
 game.object_placement.action_input_owned=func()->bool:return true
 var inventory=game.player_hud.inventory
 check(inventory.grant_items(PackedInt64Array([222,1,9,1,228,12]),inventory.snapshot().revision).ok,"Gameplay supplies enter the ordinary inventory")
 check(game.player_hud.equip_item(222),"Carried barrel equipped")
 game.player.global_position=point+Vector3(-2,1,2)
 game.camera.global_position=point+Vector3(-2,2,2);game.camera.look_at(point)
 game.object_placement.free_placement=true
 await physics_frame;await physics_frame
 var before:PackedInt64Array=game.combat.barrels.get_ids()
 var target:Dictionary=game.object_placement.target()
 check(target.get("ok",false),"Shoreline barrel placement is supported: "+str(target.get("reason","")))
 if not target.get("ok",false):return 0
 check(game.combat.place_barrel(),"Normal placement consumes carried barrel")
 var id:=0
 for candidate:int in game.combat.barrels.get_ids():
  if not before.has(candidate):id=candidate;break
 check(id>0,"Placed barrel exists in gameplay")
 return id
func shoot_barrel(id:int)->void:
 if id<=0:return
 var presentations:=[0]
 var on_equipment:=func(_slots:Array):presentations[0]+=1
 game.player_hud.character_panel.equipment_presented.connect(on_equipment)
 var equip_started:=Time.get_ticks_usec()
 check(game.player_hud.equip_item(9),"Handgun equipped for barrel ignition")
 timing_stage("handgun equip",(Time.get_ticks_usec()-equip_started)/1000.0)
 game.player_hud.character_panel.equipment_presented.disconnect(on_equipment)
 check(presentations[0]<=1 and game.player_hud.active_item==9 and game.equipped_tool==9,"Equipping updates the active handgun with at most one equipment presentation")
 print("EQUIP_STAGES ",game.tool_view.human.get("last_equip_stages"))
 game.camera.look_at(game.combat.barrel_position(id)+Vector3.UP*.5)
 var deadline:=Time.get_ticks_msec()+10000
 var shots_before:int=game.combat.shots
 while Time.get_ticks_msec()<deadline and game.combat.barrels.get_ids().has(id):
  game.app_focused=true
  game.camera.look_at(game.combat.barrel_position(id)+Vector3.UP*.5)
  var fire_started:=Time.get_ticks_usec()
  if not action_started_us:action_started_us=fire_started
  game.combat.fire()
  timing_stage("ordinary handgun fire",(Time.get_ticks_usec()-fire_started)/1000.0)
  await physics_frame
 check(game.combat.shots>=shots_before+2,"Ordinary handgun fire damages the barrel")
func percentile(values:Array[float],fraction:float)->float:
 values.sort();return values[int((values.size()-1)*fraction)] if not values.is_empty() else 0
func native_render_profiles()->Dictionary:
 var entries:Array[Dictionary]=[];var total:=0
 for node:Node in root.find_children("*","Node",true,false):
  if not node.has_method("render_frame_profile"):continue
  var value:Dictionary=node.render_frame_profile();var elapsed:int=value.get("process_us",0)
  total+=elapsed
  if elapsed>0:entries.append({"path":str(node.get_path()),"class":node.get_class(),"work":value})
 entries.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.work.process_us>b.work.process_us)
 var count:=entries.size();if entries.size()>12:entries.resize(12)
 return {"total_us":total,"active":count,"largest":entries}
func measure_game(lake:Dictionary)->void:
 if DisplayServer.get_name()=="headless":return
 game.max_fps=0;game.background_fps=0;Engine.max_fps=0;game.fly=true
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 var center:Vector3=lake.seed;center.y=lake.level
 var report:Dictionary={"scope":"Actual read-only player world; 1920x1080 isolated desktop; identical moving camera paths; uncapped render timing"}
 for phase in ["water_on_a","water_off","water_on_b"]:
  game.lakes.visible=phase!="water_off"
  var frames:Array[float]=[];var gpu:Array[float]=[];var water:Array[float]=[]
  var phase_times:Dictionary={}
  var handgun:Array[float]=[]
  var previous:=Time.get_ticks_usec()
  for frame in 240:
   var angle:=TAU*frame/240.0
   game.app_focused=true;game.needs_floor_spawn=false
   game.player.global_position=center+Vector3(cos(angle)*10,3,sin(angle)*10);game.camera.look_at(center-Vector3.UP,Vector3.UP)
   await process_frame
   var now:=Time.get_ticks_usec()
   if frame>=30:
    frames.append((now-previous)/1000.0);water.append(float(game.lakes.last_process_us))
    gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
    handgun.append(float(game.tool_view.human.last_handgun_process_us))
    for key:String in frame_phases.sample:
     if not phase_times.has(key):
      var samples:Array[float]=[];phase_times[key]=samples
     phase_times[key].append(frame_phases.sample[key])
   previous=now
  report[phase]={"frames":frames.size(),"frame_p95_ms":percentile(frames,.95),"frame_p99_ms":percentile(frames,.99),"frame_max_ms":frames.back(),"gpu_p95_ms":percentile(gpu,.95),"water_main_p95_us":percentile(water,.95),"water_main_max_us":water.back()}
  report[phase].handgun_main_p95_us=percentile(handgun,.95)
  report[phase].frame_phase_p95_ms={}
  for key:String in phase_times:report[phase].frame_phase_p95_ms[key]=percentile(phase_times[key],.95)
 report.handgun_work=game.tool_view.human.last_handgun_work.duplicate()
 report.handgun_base_active=game.tool_view.human.animation_player.active
 report.native_render_profiles=native_render_profiles()
 game.lakes.visible=true
 check(await ready("moving_combat"),"Player-world moving combat completes water publication")
 FileAccess.open(evidence.path_join("player_water_performance.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
# Binary rows avoid allocating a dictionary or encoding JSON on every frame.
# The phase index and column order are written alongside the samples.
const ROUTE_COLUMNS:=["elapsed_us","interval_us","phase","viewport_cpu_ms","viewport_gpu_ms","queued","x","y","z","yaw"]
const ROUTE_MAX_FRAMES:=36000
var route_samples:=PackedFloat64Array()
var route_phase_names:Array[String]=[]
var route_phase:="load"
var capture_phase:=""
var route_scene_start:=0
var route_started:=0
var route_prior:=0
var route_count:=0
var route_overflow:=false
func record_route_frame()->void:
 var now:=Time.get_ticks_usec()
 if route_count>=ROUTE_MAX_FRAMES:route_overflow=true;return
 var label:=timing_phase if not timing_phase.is_empty() else route_phase
 if not capture_phase.is_empty():label=capture_phase
 var phase:=route_phase_names.find(label)
 if phase<0:phase=route_phase_names.size();route_phase_names.append(label)
 var index:=route_count*ROUTE_COLUMNS.size()
 var viewport:=root.get_viewport_rid()
 var p:Vector3=game.player.position
 route_samples[index]=now-route_started
 route_samples[index+1]=now-route_prior
 route_samples[index+2]=phase
 route_samples[index+3]=RenderingServer.viewport_get_measured_render_time_cpu(viewport)
 route_samples[index+4]=RenderingServer.viewport_get_measured_render_time_gpu(viewport)
 route_samples[index+5]=game.terrain.backend.queued()
 route_samples[index+6]=p.x;route_samples[index+7]=p.y;route_samples[index+8]=p.z;route_samples[index+9]=game.yaw
 route_prior=now;route_count+=1
func begin_route_capture()->void:
 route_samples.resize(ROUTE_MAX_FRAMES*ROUTE_COLUMNS.size())
 route_started=Time.get_ticks_usec();route_prior=route_started
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 process_frame.connect(record_route_frame)
func finish_route_capture(source_sha:String)->void:
 process_frame.disconnect(record_route_frame)
 route_samples.resize(route_count*ROUTE_COLUMNS.size())
 var f:=FileAccess.open(evidence.path_join("qualification_frames.bin"),FileAccess.WRITE)
 f.store_buffer(route_samples.to_byte_array());f.close()
 var description:={"scene_setup_us":route_started-route_scene_start,"columns":ROUTE_COLUMNS,"encoding":"little-endian float64","phases":route_phase_names,"frames":route_count,"overflow":route_overflow,"source_sha256":source_sha,"gpu":RenderingServer.get_video_adapter_name(),"viewport":str(root.size),"cap":Engine.max_fps,"monitor_hz":DisplayServer.screen_get_refresh_rate(),"scope":"Game intervals and asynchronous viewport measurements. Actual display presentation requires an external trace."}
 description.settings={"renderer":RenderingServer.get_current_rendering_method(),"vsync":DisplayServer.window_get_vsync_mode(),"msaa_3d":root.msaa_3d,"scale_3d":root.scaling_3d_scale,"shadows":game.sun.shadow_enabled}
 description.processor=OS.get_processor_name()
 description.video_driver=Array(OS.get_video_adapter_driver_info())
 description.physical_memory_bytes=OS.get_memory_info().get("physical",-1)
 description.os_version=OS.get_version()
 FileAccess.open(evidence.path_join("qualification_frames.json"),FileAccess.WRITE).store_string(JSON.stringify(description,"  "))
 check(not route_overflow and route_count>0,"Complete bounded qualification frame record")
func qualification_travel()->void:
 route_phase="forest walk";await measure_grounded_route("forest_walk.json")
 if not game.trader.anchor.is_finite():check(false,"World contains trader");return
 game.teleport(game.trader.anchor+Vector3(0,0,16))
 if not await ready("trader travel"):check(false,"Trader destination loads");return
 route_phase="trader walk";await measure_grounded_route("trader_walk.json")
 var mines:Array=game.quests.store.get_locations().filter(func(row):return row.layout=="coal_mine")
 if mines.size()!=1:check(false,"World contains a coal mine");return
 var site:Dictionary=mines[0]
 var layouts=preload("res://addons/exploration/cave_layouts.gd")
 var station:Vector3=Vector3(site.origin)+layouts.turn(Vector3(.5,.2,43),site.rotation)
 game.teleport(station,station.y)
 if not await ready("underground travel"):check(false,"Underground station loads");return
 check(game.player.global_position.distance_to(station)<5,"Player arrived at underground station")
 route_phase="underground turn"
 var original:float=game.yaw
 for frame in 240:
  game.app_focused=true;game.yaw=original+TAU*frame/240.0;game.player.rotation.y=game.yaw
  await process_frame
func ready(label:String)->bool:
 route_phase=label
 var deadline:=Time.get_ticks_msec()+120000
 var next_progress:=Time.get_ticks_msec()+10000
 while Time.get_ticks_msec()<deadline:
  game.app_focused=true
  if Time.get_ticks_msec()>=next_progress and game.lakes.water!=null:
   var progress:Dictionary=game.lakes.statistics()
   print("PLAYER_LOAD_PROGRESS ",label," loading=",game.loading_active," pending=",progress.pending_regions," settling=",progress.settling_regions," regions=",progress.regions," meshes=",progress.dirty_meshes," equilibrium=",progress.equilibrium_pending," request=",progress.next_occupancy_request," busy=",progress.occupancy_busy," builder=",progress.occupancy_builder_present," slices=",progress.slice_callbacks," status=",progress.slice_last_status," patch=",progress.slice_failure," result=",JSON.stringify(progress.equilibrium_result))
   next_progress=Time.get_ticks_msec()+10000
  if not game.terrain.latest_error.is_empty():break
  if not game.loading_active and not game.terrain.pending_edit and game.lakes.water!=null:
   var s:Dictionary=game.lakes.water.runtime_state()
   if not game.lakes._equilibrium_failure.is_empty() or not game.lakes._surface_failure.is_empty():break
   if s.dirty_meshes==0 and s.pending_regions==0 and s.settling_regions==0 and not s.fill_active and not s.mesh_batch_active and not s.mesh_publish_pending and game.lakes._staged_meshes.is_empty() and game.lakes._mesh_task<0:
    print("PLAYER_WATER_STATE ",label," ",JSON.stringify(game.lakes.statistics()));return true
  await process_frame
 print("PLAYER_WATER_FAILURE ",label," ",game.terrain.latest_error," ",JSON.stringify(game.lakes.statistics() if game.lakes.water!=null else {}));return false
# Walk the same ground out and back using the production player motor.
func measure_grounded_route(filename:String="grounded_pacing.json")->void:
 game.player_view.entry.finish()
 game.fly=false
 var prior_access:bool=game.session_menu.developer_hud.mouse_access
 game.session_menu.developer_hud.mouse_access=true
 game.yaw=0
 game.player.rotation.y=0
 var rows:Array=[]
 var exploration:= "--exploration-profile" in OS.get_cmdline_user_args() or "--qualification-route" in OS.get_cmdline_user_args()
 var prior_zombie_profiling:bool=game.zombies.profiling_enabled
 var trader_route:bool="--exploration-trader" in OS.get_cmdline_user_args() or filename=="trader_walk.json"
 var last_trader_id:=0
 var trader_arrivals:=0
 var trader_retirements:=0
 var trader_outfit_ok:=true
 var leg_ms:=15000 if exploration else 5000
 var compare_sync:=exploration and "--compare-walk-vsync" in OS.get_cmdline_user_args()
 var prior_sync:=DisplayServer.window_get_vsync_mode()
 var reversed_order:="--walk-vsync-off-first" in OS.get_cmdline_user_args()
 if exploration and frame_phases==null:
  frame_phases=FramePhases.new()
  root.add_child(frame_phases)
 if exploration:
  RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
  install_route_markers()
  game.zombies.profiling_enabled=true
  game.terrain.stage_measured.connect(record_exploration_stage)
 for lap in 2:
  if compare_sync:
   var sync:=DisplayServer.VSYNC_DISABLED if (lap==0)==reversed_order else DisplayServer.VSYNC_ENABLED
   DisplayServer.window_set_vsync_mode(sync)
   # Exclude the presentation-mode transition from the steady walk.
   for warmup in 30:await process_frame
   check(DisplayServer.window_get_vsync_mode()==sync,"Requested window presentation mode is active")
  var previous:=Time.get_ticks_usec()
  var frames:Array[float]=[]
  var draw_samples:Array[float]=[]
  var gpu_samples:Array[float]=[]
  var longest:=0
  var streak:=0
  var counts:=[0,0,0]
  var over_budget:=0
  var slowest:Array=[]
  var worst_frame:=0.0
  var worst_trader_us:=0
  var start:Vector3=game.player.position
  var outward:=Vector3.ZERO
  for leg in 2:
   var keycode:=KEY_D if leg==0 else KEY_A
   game.controls.set_key(keycode,true,Time.get_ticks_usec())
   var until:=Time.get_ticks_msec()+leg_ms
   while Time.get_ticks_msec()<until:
    game.app_focused=true
    var phase:=1.0-(until-Time.get_ticks_msec())/float(leg_ms)
    game.yaw=.35*sin(phase*TAU)
    game.player.rotation.y=game.yaw
    route_marker_time=Time.get_ticks_usec()
    await process_frame
    var now:=Time.get_ticks_usec()
    var ms:float=(now-previous)/1000.0
    previous=now
    frames.append(ms)
    if compare_sync and frame_phases.sample.has("draw_ms"):
     draw_samples.append(frame_phases.sample.draw_ms)
     gpu_samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
    if ms>1000.0/60.0:over_budget+=1
    worst_frame=maxf(worst_frame,ms)
    if exploration and (slowest.size()<8 or ms>float(slowest.back().ms)):
     slowest.append({
      "ms":ms, "position":str(game.player.position), "phase":frame_phases.sample.duplicate(),
      "viewport_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
      "viewport_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
      "scene_sections_us":route_section_us.duplicate(), "terrain_ms":exploration_terrain_stages.duplicate(),
      "zombie_us":game.zombies.update_phase_us.duplicate(), "residents":game.zombies.residents.size(),
      "water_us":game.lakes.last_process_us, "trees_us":game.vegetation.last_process_us,
      "ecosystem_us":game.ecosystem.last_process_us, "cover_us":game.ground_cover.last_process_us})
     slowest.sort_custom(func(a,b):return a.ms>b.ms)
     if slowest.size()>8:slowest.pop_back()
    if trader_route:
     worst_trader_us=maxi(worst_trader_us,int(route_section_us.get(route_trader_section,0)))
     var id:int=game.trader.actor.get_instance_id() if is_instance_valid(game.trader.actor) else 0
     if last_trader_id!=id:
      if id:
       trader_arrivals+=1
       trader_outfit_ok=trader_outfit_ok and game.trader.human.is_visible_in_tree() and game.trader.human.clothing.worn==PackedInt32Array([301,302,303]) and game.trader.human.animation_player.is_playing()
      else:trader_retirements+=1
      last_trader_id=id
    if exploration:exploration_terrain_stages.clear()
    for n in 3:
     if ms>[20,33,50][n]:counts[n]+=1
    streak=streak+1 if ms>20 else 0
    longest=maxi(longest,streak)
   game.controls.set_key(keycode,false,Time.get_ticks_usec())
   if leg==0:
    outward=game.player.position
    var delta:Vector3=outward-start
    check(Vector2(delta.x,delta.z).length()>4,"Grounded route actually traverses terrain")
  rows.append({"lap":lap,"frames":frames.size(),"over_20_33_50":counts,"longest_over_20":longest,"p99_ms":percentile(frames,.99),"cap":Engine.max_fps,"start":str(start),"turnaround":str(outward),"end":str(game.player.position)})
  rows.back().over_60fps_budget=over_budget
  rows.back().max_ms=worst_frame
  if compare_sync:
   rows.back().vsync=DisplayServer.window_get_vsync_mode()
   rows.back().refresh_hz=DisplayServer.screen_get_refresh_rate()
   rows.back().draw_p99_ms=percentile(draw_samples,.99)
   rows.back().viewport_gpu_p99_ms=percentile(gpu_samples,.99)
  rows.back().slowest=slowest
  if trader_route:rows.back().max_trader_subtree_us=worst_trader_us
 if compare_sync:DisplayServer.window_set_vsync_mode(prior_sync)
 if trader_route:
  check(trader_arrivals>=2 and trader_retirements>0,"Player leaves and re-enters the shop residency radius")
  check(trader_outfit_ok,"Returning shopkeeper has a visible woven outfit and active animation")
 if exploration:
  if route_samples.is_empty():RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),false)
  game.terrain.stage_measured.disconnect(record_exploration_stage)
  game.zombies.profiling_enabled=prior_zombie_profiling
  for marker in route_markers:marker.queue_free()
  route_markers.clear()
 game.session_menu.developer_hud.mouse_access=prior_access
 FileAccess.open(evidence.path_join(filename),FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))

func check_authoring_brush()->void:
 game.player_view.entry.finish()
 var coastal:bool="--authoring-preparation" in OS.get_cmdline_user_args()
 if coastal:
  game.fly=true
  game.teleport(Vector3(20,50,1008),50)
  if not await ready("coastal brush preparation"):check(false,"Coastal authoring destination is resident");return
 elif "--authoring-at-spawn" not in OS.get_cmdline_user_args():
  game.teleport(Vector3(1000,80,1000))
  if not await ready("inland authoring"):check(false,"Authoring destination is resident");return
 if not game.session_menu.developer:game.session_menu.toggle_developer()
 game.session_menu.set_open(false)
 game.app_focused=true
 Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 if "--authoring-drag" in OS.get_cmdline_user_args():
  await check_authoring_drag()
  return
 for i in (1 if coastal else 3):
  game.radius=2 if i==0 else 32
  if i==1 and "--authoring-at-spawn" not in OS.get_cmdline_user_args():
   game.fly=true
   game.player.global_position+=Vector3.UP*65
  game.session_menu.activate_developer_slot(i)
  game.player_view.set_enabled(i==1,false)
  var view:Camera3D=root.get_camera_3d()
  view.look_at(Vector3(66,39.9,1008) if coastal else view.global_position+Vector3(.15,-1,-.1),Vector3.UP)
  game._update_edit(0)
  var shape_ok:bool=game.pointer.mesh==[game.sphere_preview,game.box_preview,game.block_preview][i]
  check(game.pointer.visible and shape_ok,"Active camera shows the selected development brush "+str(i))
  if game.latest_hit.is_empty():check(false,"Brush ray hits terrain");continue
  var hit:Vector3=game.latest_hit.position
  check((-view.global_basis.z).dot(view.global_position.direction_to(hit))>.999,"Aim follows the active camera")
  var center:Vector3=hit-game.latest_hit.normal*game.radius*.55
  if i==1:center=center.snapped(Vector3.ONE)
  if i==2:center=(hit-game.latest_hit.normal*.015).floor()+Vector3.ONE*.5
  check(game.pointer.position.is_equal_approx(center),"Preview matches brush centre")
  check(game.pointer.scale.is_equal_approx(Vector3.ONE*(1 if i==2 else game.radius*2)),"Preview matches brush dimensions")
  if i<2 and "--authoring-captures" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
   await RenderingServer.frame_post_draw
   var capture_path:=evidence.path_join("authoring_brush_%d.png"%i)
   check(root.get_texture().get_image().save_png(capture_path)==OK,"Rendered brush view retained")
  if i==2 or failures>0:continue
  var revision:int=game.terrain.published_revision
  var ticket:int=game.terrain.edit_ticket
  var audit:="--authoring-dependencies" in OS.get_cmdline_user_args() and (i==1 or "--authoring-collision-reuse" in OS.get_cmdline_user_args())
  var owners_before:=brush_mesh_owners(view,center,game.radius) if audit else {}
  var stamps_before:Dictionary=game.terrain.stamps.duplicate() if audit else {}
  if audit:
   exploration_terrain_stages.clear()
   game.terrain.stage_measured.connect(record_exploration_stage)
  var profiling:=game.terrain.backend is BrushProfileBackend and not coastal
  var verify_draw:=profiling or ("--two-frame-edits" in OS.get_cmdline_user_args() and not coastal)
  var draw_record:Dictionary={}
  var geometry_draw:Dictionary={}
  var observe_geometry:=func(installed:int)->void:
   if installed!=ticket+1:return
   geometry_draw.installed_us=Time.get_ticks_usec()
   await RenderingServer.frame_post_draw
   geometry_draw.draw_us=Time.get_ticks_usec()
   geometry_draw.frame=Engine.get_frames_drawn()
  var observe_draw:=func(row:Dictionary)->void:
   if row.ticket==ticket+1 and row.has("draw_us"):draw_record.merge(row)
  if profiling:
   game.terrain.stage_measured.connect(record_brush_staging)
  if verify_draw:
   game.terrain.edit_measured.connect(observe_draw)
   game.terrain.edit_geometry_installed.connect(observe_geometry)
  var click:=InputEventMouseButton.new()
  click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
  var started:=Time.get_ticks_usec()
  var input_frame:=Engine.get_frames_drawn()
  Input.parse_input_event(click);Input.flush_buffered_events()
  game._update_edit(1)
  var preparing:bool=not game.preparing_stroke.is_empty()
  var admitted:bool=game.terrain.pending_edit or preparing
  if coastal:check(preparing,"One press is retained while the remote coastal brush prepares occupancy")
  var feedback_us:=Time.get_ticks_usec()-started
  if not admitted:
   print("AUTHORING_REJECTION ",JSON.stringify({"target":str(hit),"captured":str(game.last_capture_signature),"queued":game.stroke_buffer.samples.size(),"message":game.status.text,"terrain_error":game.terrain.latest_error}))
  click=click.duplicate();click.pressed=false
  Input.parse_input_event(click);Input.flush_buffered_events()
  check(admitted,"Development tool accepts the brush press")
  if coastal and "--authoring-cancel" in OS.get_cmdline_user_args():
   game.session_menu.activate_developer_slot(1)
   check(game.preparing_stroke.is_empty(),"Changing tools cancels a preparing stroke")
   check(await ready("cancelled authoring"),"Water preparation drains after brush cancellation")
   check(game.terrain.edit_ticket==ticket and game.terrain.published_revision==revision,"A cancelled brush never mutates terrain")
   return
  if coastal and "--authoring-interrupt" in OS.get_cmdline_user_args():
   check(game.terrain.sculpt_sphere(Vector3(60,72,1008),2,true,1),"Independent terrain command admitted during preparation")
   check(await ready("intervening edit"),"Intervening terrain command publishes")
   for frame in 5:await physics_frame
   check(game.preparing_stroke.is_empty() and game.terrain.edit_ticket==ticket+1 and game.terrain.published_revision==revision+1,"A prepared brush cannot overwrite a newer terrain revision")
   return
  var frames:=0;var worst_us:=0;var previous:=started
  while admitted and game.terrain.published_revision==revision and Time.get_ticks_usec()-started<60000000:
   await process_frame
   var now:=Time.get_ticks_usec()
   worst_us=maxi(worst_us,now-previous);previous=now;frames+=1
  check(game.terrain.published_revision>revision,"Authoring brush publishes a changed terrain revision")
  if profiling:
   game.terrain.stage_measured.disconnect(record_brush_staging)
  if verify_draw:
   var draw_deadline:=Time.get_ticks_usec()+500000
   while draw_record.is_empty() and Time.get_ticks_usec()<draw_deadline:await process_frame
   game.terrain.edit_measured.disconnect(observe_draw)
   game.terrain.edit_geometry_installed.disconnect(observe_geometry)
   check(geometry_draw.has("draw_us"),"Contact geometry has a matched post-draw receipt")
   if geometry_draw.has("draw_us"):
    var frames_to_draw:int=1+geometry_draw.frame-input_frame
    print("AUTHORING_GEOMETRY_DRAW ",JSON.stringify({"radius":game.radius,"input_to_install_ms":(geometry_draw.installed_us-started)/1000.0,"input_to_draw_ms":(geometry_draw.draw_us-started)/1000.0,"frames_drawn":frames_to_draw}))
    if "--two-frame-edits" in OS.get_cmdline_user_args():
     check(frames_to_draw<=2 and geometry_draw.draw_us-started<=33334,"Authoring brush reaches first draw in two frames")
   check(not draw_record.is_empty(),"First terrain post-draw receipt belongs to this brush ticket")
   if not draw_record.is_empty():
    print("AUTHORING_FIRST_DRAW ",JSON.stringify({"ticket":draw_record.ticket,"input_to_commit_ms":(draw_record.publish_us-started)/1000.0,"input_to_draw_ms":(draw_record.draw_us-started)/1000.0,"commit_to_draw_ms":(draw_record.draw_us-draw_record.publish_us)/1000.0}))
  if profiling:
   var events:Dictionary=game.terrain.backend.handoff
   var waits:Array[float]=[]
   var staging:Array[float]=[]
   var still_pending:=0
   for event:Dictionary in events.values():
    if not event.has("staged_us"):continue
    waits.append((event.received_us-event.worker_us)/1000.0)
    staging.append((event.staged_us-event.received_us)/1000.0)
    if event.staged_us>game.terrain.backend.worker_done_us:still_pending+=1
   check(not waits.is_empty() and waits.size()==events.size(),"Every worker tile was observed in main-thread staging")
   if not waits.is_empty():
    var timeline:Array=game.terrain.backend.staging_frames
    print("AUTHORING_HANDOFF ",JSON.stringify({"tiles":events.size(),"poll_wait_p50_ms":percentile(waits,.5),"poll_wait_max_ms":waits.max(),"received_to_staged_p50_ms":percentile(staging,.5),"received_to_staged_max_ms":staging.max(),"staged_after_worker_done":still_pending,"frames":timeline}))
  if coastal:
   for frame in 5:await physics_frame
   check(game.terrain.edit_ticket==ticket+1 and game.terrain.published_revision==revision+1 and game.preparing_stroke.is_empty(),"Released coastal brush applies exactly once")
  # Link player latency to the native edit and the terrain publication work.
  var terrain_stages:={"worker_queue_ms":game.terrain.last_queue_ms,"field_ms":game.terrain.last_edit_ms,
   "mesh_build_ms":game.terrain.last_total_build_ms,"geometry_tiles":game.terrain.last_density_tiles,
   "commit_ms":game.terrain.last_commit_ms,"after_worker_ms":game.terrain.last_prepare_latency_ms,
   "support_worker_ms":game.terrain.last_support_worker_ms,"support_publish_ms":game.terrain.last_support_publish_ms}
  print("AUTHORING_EDIT ",JSON.stringify({"center":str(center),"radius":game.radius,"tool":game.tool,"preparing":preparing,"feedback_us":feedback_us,"admission_us":game.terrain.edit_accepted_us-started if game.terrain.edit_ticket>ticket else null,"publication_us":previous-started if game.terrain.published_revision>revision else null,"frames":frames,"worst_interval_us":worst_us,"terrain_stages":terrain_stages}))
  if audit:
   game.terrain.stage_measured.disconnect(record_exploration_stage)
   print("AUTHORING_MAIN_STAGES_MS ",JSON.stringify(exploration_terrain_stages))
   report_brush_dependencies(view,center,game.radius,owners_before,stamps_before)
   if i==1 and "--authoring-collision-reuse" in OS.get_cmdline_user_args():
    await physics_frame
    record_brush_contacts(center)

func record_brush_staging(stage:String,ms:float)->void:
 # Observe completed tiles at the end of each slice and immediately before
 # the atomic swap clears staged_batch. Times are upper bounds within a slice.
 if stage not in ["staging frame","geometry ready"]:return
 var events:Dictionary=game.terrain.backend.handoff
 var now:=Time.get_ticks_usec()
 for key in game.terrain.staged_batch:
  if events.has(key) and not events[key].has("staged_us"):events[key].staged_us=now
 if stage=="staging frame" and not events.is_empty() and game.terrain.pending_edit:
  game.terrain.backend.staging_frames.append({"received":events.size(),"staged":game.terrain.staged_batch.size(),"worker_done":game.terrain.edit_worker_done,"staging_ms":ms})

func record_brush_contacts(center:Vector3)->void:
 var hits:Array=[]
 var space:PhysicsDirectSpaceState3D=game.get_world_3d().direct_space_state
 for axis in 3:
  for sign_value in [-1,1]:
   var normal:=Vector3.ZERO
   normal[axis]=sign_value
   for u in range(-36,37,3):
    for v in range(-36,37,3):
     var origin:=center
     origin[(axis+1)%3]+=u+.173
     origin[(axis+2)%3]+=v+.319
     var ray:=PhysicsRayQueryParameters3D.create(origin+normal*48,origin-normal*48,1)
     ray.exclude=[game.player.get_rid()]
     ray.hit_back_faces=true
     var hit:=space.intersect_ray(ray)
     if hit.is_empty():hits.append(null)
     else:
      var position:Vector3=hit.position
      var surface_normal:Vector3=hit.normal
      hits.append([position[axis],surface_normal.x,surface_normal.y,surface_normal.z])
 var file:=FileAccess.open(evidence.path_join("brush_contacts.json"),FileAccess.WRITE)
 check(file!=null,"Retain post-publication collision ray samples")
 if file!=null:file.store_string(JSON.stringify(hits))
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--authoring-contact-reference="):
   compare_brush_contacts(hits,arg.trim_prefix("--authoring-contact-reference="))

func compare_brush_contacts(hits:Array,path:String)->void:
 var reference=JSON.parse_string(FileAccess.get_file_as_string(path))
 if not reference is Array or reference.size()!=hits.size():
  check(false,"Reference uses the same six-direction contact grid")
  return
 var changed_hits:=0
 var matches:=0
 var max_distance:=0.0
 var max_normal_difference:=0.0
 for i in hits.size():
  var a=reference[i]
  var b=hits[i]
  if a==null or b==null:
   if a!=b:changed_hits+=1
   continue
  matches+=1
  max_distance=maxf(max_distance,absf(a[0]-b[0]))
  max_normal_difference=maxf(max_normal_difference,Vector3(a[1],a[2],a[3]).distance_to(Vector3(b[1],b[2],b[3])))
 check(matches>0 and changed_hits==0 and max_distance<=.001 and max_normal_difference<=.001,"Edited surface matches reference hits, positions and normals")
 print("AUTHORING_CONTACT_COMPARISON ",JSON.stringify({"rays":hits.size(),"hits":matches,"changed_hits":changed_hits,"max_distance_m":max_distance,"max_normal_difference":max_normal_difference}))

# Keep CPU-side mesh arrays from the installed surface. Compare only after publication.
func brush_mesh_owners(view:Camera3D,center:Vector3,radius:float)->Dictionary:
 var owners:={}
 var planes:=view.get_frustum()
 for key:Vector3i in game.terrain.tiles:
  var footprint:=Rect2(Vector2(key.x,key.y),Vector2(key.z,key.z))
  if not footprint.grow(radius+32).has_point(Vector2(center.x,center.z)):continue
  var tile:Dictionary=game.terrain.tiles[key]
  var bricks:Dictionary=tile.get("bricks",{-1:tile})
  var records:={}
  for brick:int in bricks:
   var entry:Dictionary=bricks[brick]
   var node:Node3D=entry.node
   var in_view:=false
   if node is MeshInstance3D and node.is_visible_in_tree():
    var box:AABB=node.global_transform*node.get_aabb()
    in_view=true
    for plane in planes:
     # Godot frustum normals point outward. Exclude only a wholly outside box.
     if plane.distance_to(box.get_center())>plane.normal.abs().dot(box.size*.5):
      in_view=false
      break
   records[brick]={"node":node.get_instance_id(),"arrays":entry.get("arrays",[]),"in_view":in_view}
   if "--authoring-collision-reuse" in OS.get_cmdline_user_args():
    var shapes:Array[ConcavePolygonShape3D]=[]
    var body:StaticBody3D=entry.get("body")
    if is_instance_valid(body):
     for child in body.get_children():
      if child is CollisionShape3D and child.shape is ConcavePolygonShape3D:shapes.append(child.shape)
    records[brick].shapes=shapes
  owners[key]=records
 return owners

func report_brush_dependencies(view:Camera3D,center:Vector3,radius:float,before:Dictionary,old_stamps:Dictionary)->void:
 var after:=brush_mesh_owners(view,center,radius)
 var counts:={"replaced":0,"identical":0,"attributes_only":0,"changed_in_frustum":0,"changed_outside":0,"retained":0,"tiles_with_replacements":0}
 var collision:={"old_triangles":0,"new_triangles":0,"unchanged_triangles":0,"changed_axis_aligned":0,"old_shapes":0,"new_shapes":0,"shared_shapes":0,"stable_cell_triangles":{}}
 var keys:=before.keys()
 for key in after:
  if not before.has(key):keys.append(key)
 keys.sort()
 var render_hash:=HashingContext.new()
 render_hash.start(HashingContext.HASH_SHA256)
 for key:Vector3i in keys:
  if game.terrain.stamps.get(key,0)==old_stamps.get(key,0):continue
  var old:Dictionary=before.get(key,{})
  var current:Dictionary=after.get(key,{})
  var ids:=old.keys()
  for id in current:
   if not old.has(id):ids.append(id)
  ids.sort()
  var replacements:=0
  for id in ids:
   var a:Dictionary=old.get(id,{})
   var b:Dictionary=current.get(id,{})
   if a.get("node",0)==b.get("node",0):
    counts.retained+=1
    continue
   replacements+=1
   if a.has("shapes") or b.has("shapes"):
    compare_brush_collision(a.get("shapes",[]),b.get("shapes",[]),collision)
   var old_arrays:Array=a.get("arrays",[])
   var new_arrays:Array=b.get("arrays",[])
   render_hash.update(var_to_bytes([key,id,new_arrays]))
   if old_arrays==new_arrays:
    counts.identical+=1
    continue
   if old_arrays.size()==Mesh.ARRAY_MAX and new_arrays.size()==Mesh.ARRAY_MAX:
    if old_arrays[Mesh.ARRAY_VERTEX]==new_arrays[Mesh.ARRAY_VERTEX] and old_arrays[Mesh.ARRAY_INDEX]==new_arrays[Mesh.ARRAY_INDEX]:
     counts.attributes_only+=1
   if a.get("in_view",false) or b.get("in_view",false):counts.changed_in_frustum+=1
   else:counts.changed_outside+=1
  counts.replaced+=replacements
  if replacements>0:counts.tiles_with_replacements+=1
 check(counts.changed_in_frustum>0,"Brush changes installed mesh arrays inside the camera frustum")
 counts.render_sha256=render_hash.finish().hex_encode()
 print("AUTHORING_DEPENDENCIES ",JSON.stringify(counts))
 if "--authoring-collision-reuse" in OS.get_cmdline_user_args():
  check(collision.old_triangles>0 and collision.new_triangles>0,"Compared installed physics triangles across publication")
  collision.radius=radius
  print("AUTHORING_COLLISION_REUSE ",JSON.stringify(collision))

# Compare actual physics faces after timing the edit. A cyclic vertex rotation
# preserves winding. Count duplicate triangles independently within each owner.
func brush_collision_faces(shapes:Array)->Dictionary:
 var triangles:={}
 for shape:ConcavePolygonShape3D in shapes:
  var faces:=shape.get_faces()
  for i in range(0,faces.size(),3):
   var first:=0
   for j in range(1,3):
    if faces[i+j]<faces[i+first]:first=j
   var ordered:=PackedVector3Array([faces[i+first],faces[i+(first+1)%3],faces[i+(first+2)%3]])
   var key:=ordered.to_byte_array().hex_encode()
   if triangles.has(key):triangles[key].count+=1
   else:
    var planar:=false
    for axis in 3:
     if ordered[0][axis]==ordered[1][axis] and ordered[0][axis]==ordered[2][axis]:planar=true
    triangles[key]={"count":1,"center":(ordered[0]+ordered[1]+ordered[2])/3.0,"axis_aligned":planar}
 return triangles

func compare_brush_collision(old_shapes:Array,new_shapes:Array,total:Dictionary)->void:
 total.old_shapes+=old_shapes.size()
 total.new_shapes+=new_shapes.size()
 for shape in new_shapes:
  if old_shapes.has(shape):total.shared_shapes+=1
 var old:=brush_collision_faces(old_shapes)
 var current:=brush_collision_faces(new_shapes)
 var keys:=old.keys()
 for key in current:
  if not old.has(key):keys.append(key)
 var bins:={4:{},8:{},16:{}}
 for key in keys:
  var a:int=old[key].count if old.has(key) else 0
  var b:int=current[key].count if current.has(key) else 0
  total.old_triangles+=a
  total.new_triangles+=b
  total.unchanged_triangles+=mini(a,b)
  var record:Dictionary=current.get(key,old.get(key))
  if record.axis_aligned:total.changed_axis_aligned+=maxi(0,b-a)
  for width:int in bins:
   var cell:=Vector3i((Vector3(record.center)/width).floor())
   if not bins[width].has(cell):bins[width][cell]={"changed":false,"count":0}
   var bin:Dictionary=bins[width][cell]
   bin.changed=bin.changed or a!=b
   bin.count+=b
 for width:int in bins:
  var stable:=0
  for bin:Dictionary in bins[width].values():
   if not bin.changed:stable+=int(bin.count)
  total.stable_cell_triangles[width]=total.stable_cell_triangles.get(width,0)+stable

func brush_button(pressed:bool)->void:
 var event:=InputEventMouseButton.new()
 event.button_index=MOUSE_BUTTON_LEFT
 event.pressed=pressed
 Input.parse_input_event(event)
 Input.flush_buffered_events()
 game._update_edit(.06)

func check_authoring_drag()->void:
 game.radius=2
 game.session_menu.activate_developer_slot(0)
 var view:Camera3D=root.get_camera_3d()
 view.look_at(view.global_position+Vector3(.15,-1,-.1),Vector3.UP)
 game._update_edit(.06)
 if game.latest_hit.is_empty():check(false,"Drag starts on resident terrain");return
 var hit:Vector3=game.latest_hit.position
 var origin:=view.global_position
 var direction:=origin.direction_to(hit)
 var probe:=PhysicsRayQueryParameters3D.create(origin,hit+direction*12,1)
 probe.exclude=[game.player.get_rid()]
 var revision:int=game.terrain.published_revision
 brush_button(true)
 brush_button(false)
 check(game.terrain.pending_edit,"First excavation is in flight during the following drag")
 view.look_at(hit+Vector3.RIGHT*3,Vector3.UP)
 brush_button(true)
 var clicked:Vector3=game.last_brush
 view.look_at(hit+Vector3.RIGHT*3.75,Vector3.UP)
 game._update_edit(.06)
 check(game.last_brush.distance_to(clicked)>.1,"Held brush samples a different point")
 view.look_at(view.global_position+Vector3(.1,1,.1),Vector3.UP)
 game._update_edit(.06)
 check(game.latest_hit.is_empty() and not game.stroke_valid,"Crossing empty sky ends the swept segment")
 brush_button(false)
 var queued:Array=game.stroke_buffer.samples
 check(queued.size()==1 and queued[0].a.is_equal_approx(clicked) and queued[0].b.is_equal_approx(clicked),"Release retains the queued click at its original extent")
 view.look_at(hit+Vector3.RIGHT*5,Vector3.UP)
 var started:=Time.get_ticks_usec()
 brush_button(true)
 var frames:=0
 while game.terrain.published_revision<revision+2 and Time.get_ticks_usec()-started<3000000:
  await process_frame
  frames+=1
 var elapsed:=Time.get_ticks_usec()-started
 check(game.terrain.published_revision>=revision+2 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"Successive terrain revisions publish while the button remains held")
 await physics_frame
 var after:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(probe)
 var cut_depth:=direction.dot(Vector3(after.position)-hit) if not after.is_empty() else 0.0
 check(cut_depth>.1,"The original aim ray reaches the excavated surface before release")
 print("AUTHORING_DRAG ",JSON.stringify({"elapsed_us":elapsed,"frames":frames,"cut_depth_m":cut_depth,"published":game.terrain.published_revision-revision}))
 brush_button(false)
 check(await ready("drag release"),"Remaining admitted work drains after release")

func run()->void:
 var sea_completed:=false
 var expected_source:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--check-evidence-dir="):evidence=arg.trim_prefix("--check-evidence-dir=")
  if arg.begins_with("--water-source-slot="):slot=arg.trim_prefix("--water-source-slot=")
  if arg.begins_with("--water-source-sha256="):expected_source=arg.trim_prefix("--water-source-sha256=").to_lower()
 if not slot.is_valid_identifier() or evidence.is_empty():quit(2);return
 var path:="user://worlds/"+slot+".trw"
 if not FileAccess.file_exists(path):check(false,"Player source exists");quit(1);return
 var original:=FileAccess.get_sha256(path)
 print("WATER_GAMEPLAY_INPUT ",JSON.stringify({"slot":slot,"source_sha256":original,"viewport":str(root.size),"gpu":RenderingServer.get_video_adapter_name()}))
 if original.is_empty() or (not expected_source.is_empty() and original!=expected_source):
  check(false,"Player source matches the pinned water workload");quit(1);return
 ProjectSettings.set_setting("terraforest/offscreen_session",true)
 preload("res://addons/world_runtime/session_options.gd").set_arguments(PackedStringArray(["--world-slot="+slot,"--snapshot-readonly","--temporary","--no-derived-cache","--gameplay-construction","--ground-cover","--actors"]),true)
 route_scene_start=Time.get_ticks_usec()
 game=load("res://demo/world.tscn").instantiate()
 if "--authoring-native-profile" in OS.get_cmdline_user_args():
  game.terrain.backend=BrushProfileBackend.new()
  game.terrain.backend.profile_regions=true
 game.temporary_world=true;root.add_child(game)
 var qualification:bool="--qualification-route" in OS.get_cmdline_user_args()
 if qualification:begin_route_capture()
 check(await ready("initial"),"Actual player world loads read-only")
 if "--authoring-brush" in OS.get_cmdline_user_args() and failures==0:await check_authoring_brush()
 if qualification and failures==0:await qualification_travel()
 if "--exploration-trader" in OS.get_cmdline_user_args():
  check(game.trader.anchor.is_finite(),"Saved world has a trader destination")
  if game.trader.anchor.is_finite():
   game.teleport(game.trader.anchor+Vector3(0,0,16))
   check(await ready("trader_exploration"),"Trader district becomes playable")
 if "--grounded-pacing" in OS.get_cmdline_user_args():await measure_grounded_route()
 if "--water-load-only" in OS.get_cmdline_user_args():
  check(FileAccess.get_sha256(path)==original,"Original player save is unchanged")
  game.terrain.shutdown();game.free();await process_frame;await process_frame
  print("WATER_PLAYER_WORLD failures=",failures);quit(failures);return
 if failures==0 and "--water-profile-only" in OS.get_cmdline_user_args():
  game.player_view.entry.finish();game.fly=true;game.app_focused=true
  var lake:Dictionary=game.lakes._lakes.values()[0]
  game.teleport(lake.seed);check(await ready("profile_lake"),"Actual lake is ready for frame attribution")
  frame_phases=FramePhases.new();root.add_child(frame_phases)
  var inventory=game.player_hud.inventory
  check(inventory.grant_items(PackedInt64Array([9,1]),inventory.snapshot().revision).ok,"Profile handgun inventory admission")
  check(game.player_hud.equip_item(9),"Profile equips ordinary handgun")
  if "--water-profile-reequip" in OS.get_cmdline_user_args():
   check(inventory.grant_items(PackedInt64Array([222,1]),inventory.snapshot().revision).ok,"Profile barrel inventory admission")
   for frame in 90:await process_frame
   game.player_hud.equip_item(222)
   for frame in 90:await process_frame
   game.player_hud.equip_item(9)
   for frame in 90:await process_frame
  await measure_game(lake)
  check(FileAccess.get_sha256(path)==original,"Original player save is unchanged")
  game.terrain.shutdown();game.free();await process_frame;await process_frame
  print("WATER_PLAYER_WORLD profile-only failures=",failures);quit(failures);return
 if failures==0:
  game.player_view.entry.finish();game.fly=true;game.app_focused=true
  game.teleport(Vector3(20,40,1008),43)
  check(await ready("coastal_teleport"),"Surrounding ocean teleport reaches playable state")
 if failures==0:
  var point:=Vector3.INF;var closest:=INF
  for x in range(10,100,2):
   var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,70,1008),Vector3(x,10,1008),1))
   if not hit.is_empty() and absf(hit.position.y-40)<closest:closest=absf(hit.position.y-40);point=hit.position
  check(closest<2,"Actual surrounding shoreline ground found near sea level")
  if point==Vector3.INF:point=Vector3(50,39,1008)
  print("PLAYER_SHORE_TARGET ",point," distance_from_sea_level=",closest)
  var id:int=await gameplay_barrel(point)
  if id>0:point=game.combat.barrel_position(id)
  await capture("player_shore_before",point,40)
  var revision:int=game.terrain.published_revision
  print("PLAYER_BLAST_ADMISSION position=",game.combat.barrel_position(id)," revision=",revision," protected=",game.combat.barrels.is_removal_protected(id))
  start_timing("sea_shore_blast")
  await shoot_barrel(id)
  var deadline:=Time.get_ticks_msec()+60000
  while Time.get_ticks_msec()<deadline and game.combat.barrels.get_ids().has(id):
   game.app_focused=true
   await process_frame
  check(not game.combat.barrels.get_ids().has(id),"Normal gameplay queue detonates coastal barrel")
  print("PLAYER_BLAST_PENDING ",game.terrain.pending_edit," ticket=",game.terrain.edit_ticket)
  await process_frame;await process_frame
  await local_response(point,"sea")
  if qualification or "--water-immediate-contact" in OS.get_cmdline_user_args():check_crater_coverage(point,40,"sea immediate")
  if "--water-edit-response" in OS.get_cmdline_user_args():await capture("player_shore_after",point,40)
  sea_completed=await ready("coastal_blast")
  check(sea_completed,"Surrounding-ocean blast settles and republishes")
  finish_timing()
  check_crater_coverage(point,40,"sea")
  check(game.terrain.published_revision>revision,"Barrel changes the actual terrain revision")
  check(game.lakes.depth_at(point-Vector3.UP)>.2,"Connected ocean water occupies the newly excavated shoreline crater")
  if "--water-edit-response" not in OS.get_cmdline_user_args():await capture("player_shore_after",point,40)
  await capture("player_shore_underwater",point,40,true)
 if sea_completed:
  var lake:Dictionary=game.lakes._lakes.values()[0]
  game.teleport(lake.seed)
  var lake_ready:bool=await ready("lake_teleport")
  check(lake_ready,"Lake teleport after ocean explosion reaches playable state")
  if lake_ready:
   var ground:Dictionary={};var nearest:=INF
   for direction in 16:
    var angle:=TAU*direction/16.0
    for distance in range(4,65,2):
     var above:Vector3=lake.seed+Vector3(cos(angle)*distance,0,sin(angle)*distance);above.y=lake.level+8
     var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(above,above-Vector3.UP*30,1))
     if not hit.is_empty() and absf(hit.position.y-lake.level)<nearest:
      nearest=absf(hit.position.y-lake.level);ground=hit
   check(nearest<0.5,"Actual inland shoreline found within half a metre of water level")
   check(not ground.is_empty(),"Real lake floor is available after teleport")
   if not ground.is_empty():
    var p:Vector3=ground.position;var owned:int=owned_amount()
    var id:int=await gameplay_barrel(p)
    if id>0:p=game.combat.barrel_position(id)
    if "--water-immediate-contact" in OS.get_cmdline_user_args():check_lake_region_seams(p,lake.level,"before blast")
    await capture("player_lake_before",p,lake.level)
    start_timing("lake_shore_blast")
    await shoot_barrel(id)
    var deadline:=Time.get_ticks_msec()+60000
    while Time.get_ticks_msec()<deadline and game.combat.barrels.get_ids().has(id):
     game.app_focused=true
     await process_frame
    check(not game.combat.barrels.get_ids().has(id),"Normal gameplay queue detonates lake shoreline barrel")
    await local_response(p,"lake")
    if "--water-immediate-contact" in OS.get_cmdline_user_args():check_lake_region_seams(p,lake.level,"first publication")
    if qualification or "--water-immediate-contact" in OS.get_cmdline_user_args():check_crater_coverage(p,lake.level,"lake immediate")
    if "--water-edit-response" in OS.get_cmdline_user_args():await capture("player_lake_after",p,lake.level)
    if "--water-edit-response" in OS.get_cmdline_user_args() and "--blast-only-timing" not in OS.get_cmdline_user_args():await bucket_response_cases(lake)
    check(await ready("lake_blast"),"Actual lake crater finishes finite equilibrium")
    finish_timing()
    check_crater_coverage(p,lake.level,"lake")
    if "--water-immediate-contact" in OS.get_cmdline_user_args():check_lake_region_seams(p,lake.level,"settled")
    check(owned_amount()==owned,"Lake blast preserves every owned millilitre")
    check(game.lakes.depth_at(p-Vector3.UP)>.2,"Lake water occupies the excavated space below its former floor")
    if "--water-edit-response" not in OS.get_cmdline_user_args():await capture("player_lake_after",p,lake.level)
    await capture("player_lake_underwater",p,lake.level,true)
    if "--water-edit-response" in OS.get_cmdline_user_args():await mining_response_case(lake)
   if "--water-player-performance" in OS.get_cmdline_user_args():await measure_game(lake)
 if qualification:finish_route_capture(original)
 check(FileAccess.get_sha256(path)==original,"Original player save is unchanged")
 game.terrain.shutdown();game.free();await process_frame;await process_frame
 print("WATER_PLAYER_WORLD failures=",failures);quit(failures)

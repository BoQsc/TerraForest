# SPDX-License-Identifier: 0BSD
extends SceneTree
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
var frame_phases:FramePhases
var game:Node3D
var failures:=0
var evidence:=""
var slot:="Amber_Pines"
func check_crater_coverage(center:Vector3,level:float,label:String)->void:
 var sampled:=0;var missing:Array=[]
 for x in range(-5,6):
  for z in range(-5,6):
   if x*x+z*z>25:continue
   var p:=Vector3(center.x+x*.5,level-.5,center.z+z*.5)
   var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*8,p-Vector3.UP*8,1))
   if hit.is_empty() or hit.position.y>p.y-.1:continue
   sampled+=1
   if game.lakes.depth_at(p)<.2:missing.append({"point":str(p),"floor":hit.position.y})
 print("CRATER_COVERAGE ",label," sampled=",sampled," missing=",JSON.stringify(missing))
 check(sampled>10 and missing.is_empty(),label+" water covers every sampled excavated air point below its level")
 var surface:Dictionary=game.lakes.water.raycast_surface(Vector3(center.x,level+1,center.z),Vector3(center.x,level-1,center.z))
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
  if not top.get("hit",false) or absf(top.point.y-water_level)>.025:gaps.append({"point":str(probe),"water_hit":top.get("hit",false),"height":top.get("point",Vector3.INF).y})
 print("SHORE_CONTACT ",label," sampled=",contacts," gaps=",JSON.stringify(gaps))
 check(contacts>=10 and gaps.is_empty(),label+" water reaches within 2 cm of the actual terrain waterline")
var blast_metrics:Dictionary={}
var terrain_published_us:=0
var blast_timeline:Array[Dictionary]=[]
var blast_started:=0
var blast_last_state:=""
func terrain_published(_bounds:AABB,_revision:int)->void:
 if not timing_phase.is_empty():terrain_published_us=Time.get_ticks_usec()
var timing_phase:=""
var timing_local_ms:=-1.0
var timing_previous:=0
var timing_frames:Array[float]=[]
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
 if frame_phases==null:frame_phases=FramePhases.new();root.add_child(frame_phases)
 game.max_fps=0;game.background_fps=0;Engine.max_fps=0
 if DisplayServer.get_name()!="headless":DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 game.structures.blocks.set_process_profiling_enabled(true)
 terrain_published_us=0;blast_started=Time.get_ticks_usec();blast_timeline.clear();blast_last_state=""
 if not game.terrain.region_changed.is_connected(terrain_published):game.terrain.region_changed.connect(terrain_published)
 timing_phase=label;timing_local_ms=-1;timing_frames.clear();timing_water.clear();timing_previous=Time.get_ticks_usec()
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
 state.published=game.lakes._published_mesh_batch_id
 state.local_response=game.lakes._local_response_pending
 state.local_publication=game.lakes._local_publication_pending
 state.terrain_pending=game.terrain.pending_edit
 var signature:=JSON.stringify(state)
 if signature!=blast_last_state and blast_timeline.size()<2000:
  blast_last_state=signature;state.ms=(Time.get_ticks_usec()-blast_started)/1000.0
  blast_timeline.append(state)
 timing_worst.back().publication=game.lakes.last_publication_work.duplicate()
 if game.lakes.last_process_us>timing_water_worst.get("water_main_us",0):timing_water_worst=timing_worst.back().duplicate(true)
 timing_worst.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.frame_ms>b.frame_ms)
 if timing_worst.size()>5:timing_worst.resize(5)
 timing_stages.clear()
 timing_frames.append((now-timing_previous)/1000.0);timing_water.append(float(game.lakes.last_process_us));timing_previous=now
func finish_timing()->void:
 blast_metrics[timing_phase]={"frames":timing_frames.size(),"frame_p95_ms":percentile(timing_frames,.95),"frame_p99_ms":percentile(timing_frames,.99),"frame_max_ms":timing_frames.back() if not timing_frames.is_empty() else 0,"water_main_p95_us":percentile(timing_water,.95),"water_main_max_us":timing_water.back() if not timing_water.is_empty() else 0}
 blast_metrics[timing_phase].water_after_terrain_ms=(Time.get_ticks_usec()-terrain_published_us)/1000.0 if terrain_published_us else -1
 blast_metrics[timing_phase].timeline=blast_timeline.duplicate(true)
 blast_metrics[timing_phase].local_response_ms=timing_local_ms
 blast_metrics[timing_phase].worst_frames=timing_worst.duplicate(true)
 blast_metrics[timing_phase].stage_totals=timing_totals.duplicate()
 blast_metrics[timing_phase].water_worst=timing_water_worst.duplicate(true)
 timing_phase=""
 FileAccess.open(evidence.path_join("normal_gameplay_blast_performance.json"),FileAccess.WRITE).store_string(JSON.stringify(blast_metrics,"  "))
func local_response(point:Vector3,label:String)->void:
 var deadline:=Time.get_ticks_msec()+10000
 while Time.get_ticks_msec()<deadline:
  if terrain_published_us>0 and game.lakes._local_response_started_us>=blast_started and not game.lakes._local_response_pending and not game.lakes._local_publication_pending:
   var latency:float=game.lakes._local_response_us/1000.0
   timing_local_ms=latency
   print("LOCAL_WATER_RESPONSE ",label," ms=",latency," wider_pending=",game.lakes.water.runtime_state().settling_regions)
   print("LOCAL_WATER_SOLVE ",label," ",JSON.stringify(game.lakes.statistics().get("equilibrium_result",{})))
   if label=="lake":
    if "--water-local-snapshot" in OS.get_cmdline_user_args():
     var packet:PackedByteArray=game.lakes.water.capture_local_snapshot(AABB(point-Vector3(12,8,12),Vector3(24,12,24)))
     check(not packet.is_empty() and packet.size()<8*1024*1024,"Local replay fits its declared eight MiB evidence allowance")
     if not packet.is_empty() and packet.size()<8*1024*1024:FileAccess.open(evidence.path_join("local_response.water_regions"),FileAccess.WRITE).store_var({"point":point,"snapshot":packet})
    for axis:Vector3 in [Vector3.RIGHT,Vector3.BACK]:
     var heads:Array=[]
     for offset in range(-16,17):
      var sample:=point+axis*offset*.5+Vector3.UP*2
      var hit:Dictionary=game.lakes.water.raycast_surface(sample,sample-Vector3.UP*5)
      heads.append([offset*.5,str(hit)])
     print("LOCAL_WATER_HEADS origin=",point," axis=",axis," ",JSON.stringify(heads))
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
 check(game.world_attack.apply_target(target) and game.terrain.pending_edit,"Ordinary pickaxe damage and contact-mining stroke are admitted in the saved game")
 await local_response(ground.position+Vector3.UP*.25,"mining")
 check(await ready("mining"),"Mining completes wider relaxation")
 finish_timing()
 check(owned_amount()==before,"Mining conserves every owned millilitre")
func capture(label:String,center:Vector3,level:float,underwater:bool=false)->void:
 if DisplayServer.get_name()=="headless" or "--water-no-captures" in OS.get_cmdline_user_args():return
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
  game.camera.global_position=Vector3(center.x+5,level+(3.5 if "lake" in label else 1.5),center.z-4)
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
func _initialize()->void:run.call_deferred()
func owned_amount()->int:
 # Pristine ocean residency can retire after travel; it is not owned lake mass.
 # Use the production save snapshot's non-regenerable quantity, outside timing.
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var frozen:Variant=game.lakes.water.capture_storage_snapshot(catalog)
 var bytes:PackedByteArray=frozen if frozen is PackedByteArray else frozen.serialize_snapshot()
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
 var equip_started:=Time.get_ticks_usec()
 check(game.player_hud.equip_item(9),"Handgun equipped for barrel ignition")
 timing_stage("handgun equip",(Time.get_ticks_usec()-equip_started)/1000.0)
 game.camera.look_at(game.combat.barrel_position(id)+Vector3.UP*.5)
 var deadline:=Time.get_ticks_msec()+10000
 var shots_before:int=game.combat.shots
 while Time.get_ticks_msec()<deadline and game.combat.barrels.get_ids().has(id):
  game.app_focused=true
  game.camera.look_at(game.combat.barrel_position(id)+Vector3.UP*.5)
  var fire_started:=Time.get_ticks_usec()
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
func ready(label:String)->bool:
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
func run()->void:
 var sea_completed:=false
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--check-evidence-dir="):evidence=arg.trim_prefix("--check-evidence-dir=")
  if arg.begins_with("--water-source-slot="):slot=arg.trim_prefix("--water-source-slot=")
 if not slot.is_valid_identifier() or evidence.is_empty():quit(2);return
 var path:="user://worlds/"+slot+".trw"
 if not FileAccess.file_exists(path):check(false,"Player source exists");quit(1);return
 var original:=FileAccess.get_sha256(path)
 ProjectSettings.set_setting("terraforest/offscreen_session",true)
 preload("res://addons/world_runtime/session_options.gd").set_arguments(PackedStringArray(["--world-slot="+slot,"--snapshot-readonly","--temporary","--no-derived-cache","--gameplay-construction","--ground-cover","--actors"]),true)
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
 check(await ready("initial"),"Actual player world loads read-only")
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
  await capture("player_shore_before",point,40)
  var id:int=await gameplay_barrel(point)
  if id>0:point=game.combat.barrel_position(id)
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
    await capture("player_lake_before",p,lake.level)
    start_timing("lake_shore_blast")
    await shoot_barrel(id)
    var deadline:=Time.get_ticks_msec()+60000
    while Time.get_ticks_msec()<deadline and game.combat.barrels.get_ids().has(id):
     game.app_focused=true
     await process_frame
    check(not game.combat.barrels.get_ids().has(id),"Normal gameplay queue detonates lake shoreline barrel")
    await local_response(p,"lake")
    if "--water-edit-response" in OS.get_cmdline_user_args():await capture("player_lake_after",p,lake.level)
    if "--water-edit-response" in OS.get_cmdline_user_args():await bucket_response_cases(lake)
    check(await ready("lake_blast"),"Actual lake crater finishes finite equilibrium")
    finish_timing()
    check_crater_coverage(p,lake.level,"lake")
    check(owned_amount()==owned,"Lake blast preserves every owned millilitre")
    check(game.lakes.depth_at(p-Vector3.UP)>.2,"Lake water occupies the excavated space below its former floor")
    if "--water-edit-response" not in OS.get_cmdline_user_args():await capture("player_lake_after",p,lake.level)
    await capture("player_lake_underwater",p,lake.level,true)
    if "--water-edit-response" in OS.get_cmdline_user_args():await mining_response_case(lake)
   if "--water-player-performance" in OS.get_cmdline_user_args():await measure_game(lake)
 check(FileAccess.get_sha256(path)==original,"Original player save is unchanged")
 game.terrain.shutdown();game.free();await process_frame;await process_frame
 print("WATER_PLAYER_WORLD failures=",failures);quit(failures)

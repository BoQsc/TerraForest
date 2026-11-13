# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node3D
var failures:=0
var evidence:=""
var slot:="Amber_Pines"
func capture(label:String,center:Vector3,level:float,underwater:bool=false)->void:
 if DisplayServer.get_name()=="headless":return
 var processing:=game.is_processing();var physics:=game.is_physics_processing()
 game.set_process(false);game.set_physics_process(false);game.tool_view.visible=false
 game.camera.global_position=center+Vector3(-4,level-center.y+(-1 if underwater else 3),6)
 game.camera.look_at(Vector3(center.x,level-1,center.z),Vector3.UP)
 game.combat.effects.step(.7,true);game.water_camera.update()
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(evidence.path_join(label+".png"))
 game.set_process(processing);game.set_physics_process(physics)
func _initialize()->void:run.call_deferred()
func owned_amount()->int:
 # Pristine ocean residency can retire after travel; it is not owned lake mass.
 # Use the production save snapshot's non-regenerable quantity, outside timing.
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var frozen:Variant=game.lakes.water.capture_storage_snapshot(catalog)
 var bytes:PackedByteArray=frozen if frozen is PackedByteArray else frozen.serialize_snapshot()
 check(bytes.size()>=32 and bytes.decode_u32(0)==0x31575256,"Owned-quantity snapshot is complete")
 return bytes.decode_u64(16) if bytes.size()>=32 else -1
func percentile(values:Array[float],fraction:float)->float:
 values.sort();return values[int((values.size()-1)*fraction)] if not values.is_empty() else 0
func measure_game(lake:Dictionary)->void:
 if DisplayServer.get_name()=="headless":return
 game.max_fps=0;game.background_fps=0;Engine.max_fps=0;game.fly=true
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 var center:Vector3=lake.seed;center.y=lake.level
 var report:Dictionary={"scope":"Actual read-only player world; 1920x1080 isolated desktop; identical moving camera paths; uncapped render timing"}
 var explosions:int=game.combat.explosions
 for phase in ["water_on_a","water_off","water_on_b","combat"]:
  game.lakes.visible=phase!="water_off"
  var frames:Array[float]=[];var gpu:Array[float]=[];var water:Array[float]=[]
  var previous:=Time.get_ticks_usec()
  for frame in 240:
   var angle:=TAU*frame/240.0
   game.app_focused=true;game.needs_floor_spawn=false
   game.player.global_position=center+Vector3(cos(angle)*10,3,sin(angle)*10);game.camera.look_at(center-Vector3.UP,Vector3.UP)
   if phase=="combat" and frame in [30,100,170]:
    var p:Vector3=center+Vector3(cos(angle)*4,-1,sin(angle)*4)
    var id:int=game.combat.barrels.insert_instance(PackedFloat32Array([1,0,0,p.x,0,1,0,p.y,0,0,1,p.z]),AABB())
    check(id>0 and game.combat.damage_barrel(id,50),"Moving player-world combat ignites a barrel")
   game.combat.step_blasts()
   if not game.terrain.pending_edit and not game.combat.detonations.is_empty():
    if game.combat.detonate(game.combat.detonations[0]):game.combat.detonations.pop_front()
   await process_frame
   var now:=Time.get_ticks_usec()
   if frame>=30:
    frames.append((now-previous)/1000.0);water.append(float(game.lakes.last_process_us))
    gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
   previous=now
  report[phase]={"frames":frames.size(),"frame_p95_ms":percentile(frames,.95),"frame_p99_ms":percentile(frames,.99),"frame_max_ms":frames.back(),"gpu_p95_ms":percentile(gpu,.95),"water_main_p95_us":percentile(water,.95),"water_main_max_us":water.back()}
 game.lakes.visible=true
 check(await ready("moving_combat"),"Player-world moving combat completes water publication")
 check(game.combat.explosions==explosions+3,"All three player-world moving-combat barrels detonate")
 FileAccess.open(evidence.path_join("player_water_performance.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func ready(label:String)->bool:
 var deadline:=Time.get_ticks_msec()+120000
 while Time.get_ticks_msec()<deadline:
  if not game.terrain.latest_error.is_empty():break
  if not game.loading_active and not game.terrain.pending_edit and game.lakes.water!=null:
   var s:Dictionary=game.lakes.statistics()
   if not str(s.equilibrium_failure).is_empty() or not str(s.surface_failure).is_empty():break
   if s.render_ready and s.settling_regions==0:
    print("PLAYER_WATER_STATE ",label," ",JSON.stringify(s));return true
  await process_frame
 print("PLAYER_WATER_FAILURE ",label," ",game.terrain.latest_error," ",JSON.stringify(game.lakes.statistics() if game.lakes.water!=null else {}));return false
func run()->void:
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
 if failures==0:
  game.player_view.entry.finish();game.fly=true;game.app_focused=true
  game.lakes.settling_active=func()->bool:return true
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
  var id:int=game.combat.barrels.insert_instance(PackedFloat32Array([1,0,0,point.x,0,1,0,point.y,0,0,1,point.z]),AABB())
  var revision:int=game.terrain.published_revision
  game.combat.set_physics_process(false)
  print("PLAYER_BLAST_ADMISSION position=",game.combat.barrel_position(id)," revision=",revision," protected=",game.combat.barrels.is_removal_protected(id))
  check(id>0 and game.combat.damage_barrel(id,50),"Actual surrounding-ocean barrel ignited")
  var deadline:=Time.get_ticks_msec()+60000
  var detonated:=false
  while Time.get_ticks_msec()<deadline:
   if game.combat.detonate(id):detonated=true;break
   await process_frame
  check(detonated,"Coastal preparation admits the queued barrel detonation")
  game.combat.detonations.erase(id)
  print("PLAYER_BLAST_PENDING ",game.terrain.pending_edit," ticket=",game.terrain.edit_ticket)
  await process_frame;await process_frame
  check(await ready("coastal_blast"),"Surrounding-ocean blast settles and republishes")
  check(game.terrain.published_revision>revision,"Barrel changes the actual terrain revision")
  check(game.lakes.depth_at(point-Vector3.UP)>.2,"Connected ocean water occupies the newly excavated shoreline crater")
  await capture("player_shore_after",point,40)
  await capture("player_shore_underwater",point,40,true)
 if failures==0:
  var lake:Dictionary=game.lakes._lakes.values()[0]
  game.teleport(lake.seed)
  check(await ready("lake_teleport"),"Lake teleport after ocean explosion reaches playable state")
  if failures==0:
   var above:Vector3=Vector3(lake.seed.x+3,lake.level+4,lake.seed.z)
   var ground:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(above,above-Vector3.UP*20,1))
   check(not ground.is_empty(),"Real lake floor is available after teleport")
   if not ground.is_empty():
    var p:Vector3=ground.position;var owned:int=owned_amount()
    var id:int=game.combat.barrels.insert_instance(PackedFloat32Array([1,0,0,p.x,0,1,0,p.y,0,0,1,p.z]),AABB())
    await capture("player_lake_before",p,lake.level)
    check(id>0 and game.combat.damage_barrel(id,50) and game.combat.detonate(id),"Actual lake barrel detonates after ocean travel")
    game.combat.detonations.erase(id)
    check(await ready("lake_blast"),"Actual lake crater finishes finite equilibrium")
    check(owned_amount()==owned,"Lake blast preserves every owned millilitre")
    check(game.lakes.depth_at(p-Vector3.UP)>.2,"Lake water occupies the excavated space below its former floor")
    await capture("player_lake_after",p,lake.level)
    await capture("player_lake_underwater",p,lake.level,true)
   if failures==0 and "--water-player-performance" in OS.get_cmdline_user_args():await measure_game(lake)
 check(FileAccess.get_sha256(path)==original,"Original player save is unchanged")
 game.terrain.shutdown();game.free();await process_frame;await process_frame
 print("WATER_PLAYER_WORLD failures=",failures);quit(failures)

# SPDX-License-Identifier: 0BSD
extends "water_static_mining.gd"
var evidence:=""
var frames:Array[int]=[]
var measured:=false
var previous_frame:=0
var terrain_published_us:=0
var water_main_us:Array[int]=[]
var gpu_ms:Array[float]=[]
var timeline:Array[Dictionary]=[]
var measurement_started:=0
var terrain_preparations:Array[Dictionary]=[]
var frame_stages:Dictionary={}
func terrain_published(_bounds:AABB,_revision:int)->void:
 if measured:terrain_published_us=Time.get_ticks_usec()
func frame_cost()->void:
 if not measured:return
 var now:=Time.get_ticks_usec()
 if previous_frame:frames.append(now-previous_frame)
 var state:Dictionary=game.lakes.statistics()
 timeline.append({"ms":(now-measurement_started)/1000.0,"pending":state.pending_regions,"dirty":state.dirty_meshes,"settling":state.settling_regions,"worker":state.get("equilibrium_pending",false),"main_us":game.lakes.last_process_us})
 water_main_us.append(game.lakes.last_process_us)
 gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
 previous_frame=now
func idle_water()->bool:
 var deadline:=Time.get_ticks_msec()+60000
 var next_report:=Time.get_ticks_msec()+10000
 while Time.get_ticks_msec()<deadline:
  var stats:Dictionary=game.lakes.statistics()
  if not stats.get("equilibrium_failure","").is_empty():
   print("WATER_EQUILIBRIUM_FAILURE ",stats.equilibrium_failure);return false
  if not game.terrain.pending_edit and stats.render_ready and stats.settling_regions==0:return true
  if Time.get_ticks_msec()>=next_report:
   print("WATER_BARREL_PROGRESS ",JSON.stringify({"terrain_pending":game.terrain.pending_edit,"settling_regions":stats.settling_regions,"settling_steps":stats.settling_steps,"pending_regions":stats.pending_regions,"dirty_meshes":stats.dirty_meshes,"surface_failure":stats.surface_failure,"occupancy_failure":stats.occupancy_failure}))
   next_report+=10000
  await process_frame
 return false
func moment(values:Dictionary)->float:
 var result:=0.0
 for key:String in values:
  var parts:=key.split(":");var region:=int(parts[0]);var index:=int(parts[1])
  result+=float(((region>>12)&4095)*8+(index/8)%8)*float(values[key])
 return result
func capture(label:String,center:Vector3,level:float,underwater:bool=false)->void:
 game.camera.global_position=center+Vector3(-3,level-center.y-1 if underwater else level-center.y+2,4 if underwater else 6)
 game.camera.look_at(center+Vector3(0,level-center.y-1 if underwater else level-center.y-1.5,0),Vector3.UP)
 # Advance transient explosion effects while the fixed-camera game is paused.
 game.combat.effects.step(.6,true)
 game.water_camera.update()
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(evidence.path_join(label+".png"))
func run():
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--check-evidence-dir="):evidence=argument.trim_prefix("--check-evidence-dir=")
 if evidence.is_empty():push_error("Run through the admitted check launcher");quit(2);return
 process_frame.connect(frame_cost)
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+120000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Actual lake review world prepares")
 if failures:await finish();return
 game.terrain.stage_measured.connect(func(label:String,ms:float):frame_stages[label]=float(frame_stages.get(label,0))+ms)
 game.terrain.region_changed.connect(terrain_published)
 game.terrain.lake_slice_profiled.connect(func(worker:float,queue:float,status:int):
  if measured:terrain_preparations.append({"worker_ms":worker,"queue_ms":queue,"status":status}))
 game.set_process(false);game.set_physics_process(false);game._clear_motion();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 game.tool_view.visible=false
 check(game.combat.blast_water_settling,"Terrain-reactive water is enabled in ordinary gameplay")
 # Fixed-player rendering check: exercise the real committed-edit callback and
 # water scheduler without depending on which desktop window currently has focus.
 game.lakes.settling_active=func()->bool:return true
 check(await idle_water(),"Initial water publication reaches idle")
 var entry:Dictionary=game.lakes._lakes.values()[0]
 if "--water-contact-only" in OS.get_cmdline_user_args():
  await object_contact_case(entry);await finish();return
 var above:Vector3=entry.seed+Vector3(3,0,0);above.y=entry.level+4
 await physics_frame
 var ground:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(above,above-Vector3.UP*20,1))
 check(not ground.is_empty(),"Actual terrain beneath lake is available")
 if ground.is_empty():await finish();return
 var base:Vector3=ground.position
 var id:int=game.combat.barrels.insert_instance(PackedFloat32Array([1,0,0,base.x,0,1,0,base.y,0,0,1,base.z]),AABB())
 check(id>0,"Explosive barrel enters the actual model store")
 var before:=amounts(game.lakes.capture_snapshot());var total:int=game.lakes.statistics().water_ml
 await capture("barrel_before",base,entry.level)
 measured=true;previous_frame=0;var started:=Time.get_ticks_usec();measurement_started=started
 check(game.combat.damage_barrel(id,50) and game.combat.detonate(id),"Actual damaged barrel admits terrain excavation")
 game.combat.detonations.erase(id)
 check(await idle_water(),"Barrel crater water settles and publishes within the bound")
 var finished:=Time.get_ticks_usec();var elapsed:=finished-started;measured=false
 var water_latency:float=(finished-terrain_published_us)/1000.0 if terrain_published_us else -1
 var after:=amounts(game.lakes.capture_snapshot());var stats:Dictionary=game.lakes.statistics()
 var checkpoint:=FileAccess.open(evidence.path_join("post_blast_statistics.json"),FileAccess.WRITE);checkpoint.store_string(JSON.stringify(stats,"  "));checkpoint.close()
 check(stats.water_ml==total,"Barrel excavation conserves every owned millilitre")
 check(after!=before and moment(after)<moment(before),"Water redistributes downward into the actual barrel crater")
 check(game.combat.barrels.get_instance(id).is_empty(),"Detonated barrel is removed exactly once")
 check(not stats.surface_budget_failed and stats.surface_failure.is_empty(),"Water publication reports no geometry budget failure")
 await capture("barrel_after",base,entry.level)
 await capture("barrel_after_underwater",base,entry.level,true)
 var snapshot:PackedByteArray=game.lakes.capture_snapshot()
 if "--water-replay-capture" in OS.get_cmdline_user_args():
  var replay:=FileAccess.open(evidence.path_join("post_blast.water"),FileAccess.WRITE);replay.store_buffer(snapshot);replay.close()
 check(game.lakes.restore_snapshot(snapshot),"Post-blast water snapshot restores")
 check(await idle_water() and amounts(game.lakes.capture_snapshot())==after,"Reload preserves settled quantities")
 game.lakes.water.settle_after_edit(AABB(base-Vector3.ONE*4,Vector3.ONE*8))
 var unfinished:PackedByteArray=game.lakes.capture_snapshot()
 game.lakes.loading_active=func()->bool:return true
 game.lakes.settling_active=func()->bool:return false
 check(game.lakes.restore_snapshot(unfinished) and game.lakes.statistics().settling_regions>0,"Saved unfinished water transaction restores pending work")
 check(await idle_water(),"Saved unfinished water transaction completes while gameplay is blocked by loading")
 check(game.lakes.statistics().water_ml==total,"Loading-time settlement preserves the saved quantity")
 game.lakes.loading_active=func()->bool:return game.loading_active or game.lakes.offline_preparation
 game.lakes.settling_active=func()->bool:return true
 var legacy_snapshot:=snapshot.duplicate();legacy_snapshot.encode_u32(4,11)
 check(game.lakes.restore_snapshot(legacy_snapshot) and game.lakes.statistics().pending_regions>0,"Actual game migrates an old geometry-cache revision through terrain sampling")
 check(await idle_water() and amounts(game.lakes.capture_snapshot())==after,"Actual-game migration republishes water without changing stored quantities")
 frames.sort();water_main_us.sort();gpu_ms.sort()
 var report:Dictionary={"terrain_preparations":terrain_preparations,"timeline":timeline,"failures":failures,"water_ml":total,"barrel_base":base,"settle_publish_ms":elapsed/1000.0,"water_after_terrain_ms":water_latency,"statistics":stats,"frame_samples":frames.size(),"scope":"Actual barrel, terrain and water path with stationary player; focus-independent water advancement. Not a moving-combat FPS acceptance."}
 if not water_main_us.is_empty():report.water_main_p95_us=water_main_us[int((water_main_us.size()-1)*.95)];report.water_main_max_us=water_main_us.back()
 if not gpu_ms.is_empty():report.scene_gpu_p95_ms=gpu_ms[int((gpu_ms.size()-1)*.95)]
 if not frames.is_empty():report.frame_p95_ms=frames[int((frames.size()-1)*.95)]/1000.0;report.frame_max_ms=frames.back()/1000.0
 var file:=FileAccess.open(evidence.path_join("water_barrel_world.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 if "--water-full-regression" in OS.get_cmdline_user_args():await terrain_cases(entry,total)
 if "--water-object-contact" in OS.get_cmdline_user_args():await object_contact_case(entry)
 if "--water-performance" in OS.get_cmdline_user_args():await performance_cases(entry)
 await finish()
func object_contact_case(entry:Dictionary)->void:
 # Keep this independent of the paid terrain deposit at the lake seed.
 var location:Vector3=entry.seed+Vector3(-3,0,-3)
 var current_surface:Dictionary=game.lakes.water.raycast_surface(Vector3(location.x,entry.level+1,location.z),Vector3(location.x,entry.level-4,location.z))
 check(current_surface.get("hit",false),"Current post-blast surface determines the contact fixture height")
 if not current_surface.get("hit",false):return
 var cell:=Vector3i(floori(location.x),floori(current_surface.point.y),floori(location.z))
 game.construction_inventory.gameplay=false
 check(game.construction_inventory.place_block(game.structures.blocks,game.player_hud.inventory,cell,1),"Actual cube construction intersects the lake surface")
 check(await idle_water(),"Object contact publishes with conserved water")
 var center:=Vector3(cell)+Vector3(.5,0,.5)
 var reference:Dictionary=game.lakes.water.raycast_surface(center+Vector3(2,3,0),center+Vector3(2,-2,0))
 check(reference.get("hit",false),"Reference free surface exists beside object")
 if reference.get("hit",false):
  var level:float=reference.point.y
  check(level>cell.y and level<cell.y+1,"Cube crosses the current free surface, not an obsolete authored height")
  check(game.lakes.depth_at(Vector3(cell)+Vector3(.5,.1,.5))==0,"Solid cube excludes water inside its occupied volume")
  for offset in [Vector3(-.51,0,0),Vector3(.51,0,0),Vector3(0,0,-.51),Vector3(0,0,.51)]:
   var probe:Vector3=center+offset
   var hit:Dictionary=game.lakes.water.raycast_surface(Vector3(probe.x,level+1,probe.z),Vector3(probe.x,level-.5,probe.z))
   check(hit.get("hit",false) and absf(hit.point.y-level)<.02,"Visible water reaches within 1 cm of the cube wall: "+str(hit))
  await capture("object_contact_above",center,level)
  await capture("object_contact_underwater",center,level,true)
 check(game.structures.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,0])),"Contact fixture removes through actual block transaction")
 check(await idle_water(),"Object removal restores the water boundary")
func finish():
 if is_instance_valid(game):game.terrain.shutdown();game.queue_free()
 await process_frame;await process_frame
 print("WATER_BARREL_WORLD failures=",failures);quit(failures)

func terrain_cases(entry:Dictionary,total:int)->void:
 var center:Vector3=entry.seed;center.y=entry.level
 var bank:=Vector3.INF
 for step in range(12,81):
  var p:Vector3=center+Vector3(step*.25,0,0)
  var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*10,p-Vector3.UP*20,1))
  if not hit.is_empty() and hit.position.y>=entry.level-.1:bank=hit.position;break
 check(bank.is_finite(),"Actual shoreline is available for the breach test")
 if not bank.is_finite():return
 var before:=amounts(game.lakes.capture_snapshot())
 var id:int=game.combat.barrels.insert_instance(PackedFloat32Array([1,0,0,bank.x,0,1,0,bank.y,0,0,1,bank.z]),AABB())
 await capture("shore_before",bank,entry.level)
 var began:=Time.get_ticks_usec()
 check(id>0 and game.combat.damage_barrel(id,50) and game.combat.detonate(id),"Shoreline barrel detonates through actual combat")
 game.combat.detonations.erase(id)
 check(await idle_water(),"Shoreline breach reaches a published equilibrium")
 var shore_elapsed:float=(Time.get_ticks_usec()-began)/1000.0
 check(game.lakes.statistics().water_ml==total and amounts(game.lakes.capture_snapshot())!=before,"Breach redistributes finite water without loss")
 await capture("shore_after",bank,entry.level)
 await capture("shore_underwater",bank,entry.level,true)
 var results:Dictionary={"shore_ms":shore_elapsed}
 var mine:Vector3=center+Vector3(-3,-3,0)
 before=amounts(game.lakes.capture_snapshot())
 check(game.terrain.sculpt_sphere(mine,2.0),"Ordinary mining under the lake is admitted")
 check(await idle_water(),"Mining updates the published water volume")
 check(game.lakes.statistics().water_ml==total and amounts(game.lakes.capture_snapshot())!=before,"Mining changes water distribution and conserves quantity")
 await capture("mining_underwater",mine,entry.level,true)
 var deposit:Vector3=center+Vector3(0,-1,0)
 before=amounts(game.lakes.capture_snapshot())
 var slot:=-1
 var inventory:Dictionary=game.player_hud.inventory.snapshot()
 for i in inventory.slots.size():
  if inventory.slots[i].item==201 and inventory.slots[i].count>0:slot=i;break
 check(slot>=0 and game.mining_rewards.place(Vector3i(deposit.floor()),201,slot),"Carried terrain material is deposited through the actual inventory transaction")
 check(await idle_water(),"Deposited terrain displaces water and publishes")
 check(game.lakes.statistics().water_ml==total and amounts(game.lakes.capture_snapshot())!=before,"Deposition changes water distribution and conserves quantity")
 var reference:Dictionary=game.lakes.water.raycast_surface(center+Vector3(-3,1,-3),center+Vector3(-3,-4,-3))
 if reference.get("hit",false):
  var level:float=reference.point.y
  var tested:=0
  for z in range(-4,5):
   for x in range(-4,5):
    var p:=Vector3(deposit.floor())+Vector3(.5+x*.15,0,.5+z*.15)
    var ground:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x,level+2,p.z),Vector3(p.x,level-3,p.z),1))
    if ground.is_empty() or ground.position.y>=level-.04:continue
    tested+=1
    var surface:Dictionary=game.lakes.water.raycast_surface(Vector3(p.x,level+.5,p.z),Vector3(p.x,level-.5,p.z))
    var covered:bool=surface.get("hit",false) and absf(surface.point.y-level)<.03
    if not covered:print("TERRAIN_CONTACT_PROBE ",JSON.stringify({"point":p,"ground":ground.position,"level":level,"surface":surface,"geometry":game.lakes.water.cell_geometry(Vector3(p.x,level,p.z))}))
    check(covered,"Submerged deposited terrain stays covered at "+str(p))
  check(tested>0,"Terrain-contact coverage samples actual submerged ground")
 else:check(false,"Terrain-contact reference surface exists")
 await capture("deposition_above",deposit,entry.level)
 await capture("deposition_underwater",deposit,entry.level,true)
 # Compare the optimized invalidation against a full authoritative resample.
 var geometry_before:=contact_signature(center)
 var conserved:=amounts(game.lakes.capture_snapshot())
 game.lakes.water.invalidate(AABB(center-Vector3.ONE*12,Vector3.ONE*24))
 check(await idle_water(),"Full terrain occupancy reference resamples and publishes")
 var geometry_after:=contact_signature(center)
 check(geometry_after==geometry_before and amounts(game.lakes.capture_snapshot())==conserved,"Narrow edit invalidation matches full terrain resampling without quantity changes")
 results["boundary"]=boundary_topology(center)
 check(results.boundary.open_edges==0 and results.boundary.degenerate==0 and results.boundary.triangles>0,"Actual game water has a closed nondegenerate boundary across region seams")
 results["failures"]=failures;results["statistics"]=game.lakes.statistics()
 var file:=FileAccess.open(evidence.path_join("terrain_cases.json"),FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()

func percentile(values:Array[float],fraction:float)->float:
 values.sort();return values[int((values.size()-1)*fraction)] if not values.is_empty() else 0.0
func performance_cases(entry:Dictionary)->void:
 var initial_explosions:int=game.combat.explosions
 # Keep the full game update/physics running. Scripted travel gives identical
 # camera paths in each comparison without relying on desktop input focus.
 game.max_fps=0;game.background_fps=0;Engine.max_fps=0
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 game.fly=true;game.app_focused=true;game.needs_floor_spawn=false
 game.set_process(true);game.set_physics_process(true)
 var center:Vector3=entry.seed;center.y=entry.level
 var report:Dictionary={"scope":"1920x1080 full game updates, scripted moving viewpoint, uncapped; alternating identical water on/off paths and actual barrel combat"}
 for phase in ["water_on_a","water_off","water_on_b","combat"]:
  game.lakes.visible=phase!="water_off"
  var samples:Array[float]=[];var gpu:Array[float]=[];var cpu:Array[float]=[];var main:Array[float]=[]
  var worst:Array[Dictionary]=[]
  var previous:=Time.get_ticks_usec()
  for frame in 240:
   var angle:float=float(frame)*TAU/240.0
   game.player.global_position=center+Vector3(cos(angle)*9,2.0,sin(angle)*9)
   game.camera.look_at(center-Vector3.UP,Vector3.UP)
   game.app_focused=true
   if phase=="combat" and frame in [30,100,170] and not game.terrain.pending_edit:
    var base:Vector3=center+Vector3(cos(angle)*5,-1,sin(angle)*5)
    var id:int=game.combat.barrels.insert_instance(PackedFloat32Array([1,0,0,base.x,0,1,0,base.y,0,0,1,base.z]),AABB())
    check(id>0 and game.combat.damage_barrel(id,50),"Moving gameplay admits a damaged explosive barrel")
   frame_stages.clear()
   await process_frame
   var now:=Time.get_ticks_usec()
   if frame>=30:
    samples.append((now-previous)/1000.0)
    worst.append({"frame_ms":samples.back(),"stages":frame_stages.duplicate(),"water_us":game.lakes.last_process_us,"frame":frame})
    gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
    cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
    main.append(float(game.lakes.last_process_us))
   previous=now
  worst.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.frame_ms>b.frame_ms)
  worst.resize(mini(10,worst.size()))
  report[phase]={"worst_frames":worst,"frames":samples.size(),"frame_p95_ms":percentile(samples,.95),"frame_p99_ms":percentile(samples,.99),"frame_max_ms":samples.back(),"gpu_p95_ms":percentile(gpu,.95),"render_cpu_p95_ms":percentile(cpu,.95),"water_main_p95_us":percentile(main,.95),"water_main_max_us":main.back()}
 game.set_process(false);game.set_physics_process(false);game.lakes.visible=true
 check(await idle_water(),"Moving combat leaves water settled and fully published")
 check(game.combat.explosions==initial_explosions+3,"All three moving-combat barrels actually detonated")
 report["explosions"]=game.combat.explosions
 report["failures"]=failures
 var file:=FileAccess.open(evidence.path_join("water_performance.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()

func contact_signature(center:Vector3)->PackedInt64Array:
 var result:=PackedInt64Array()
 var origin:Vector3=(center-Vector3(8,6,8)).floor()+Vector3.ONE*.25
 for z in 32:
  for y in 16:
   for x in 32:
    var shape:Dictionary=game.lakes.water.cell_geometry(origin+Vector3(x,y,z)*.5)
    result.append(shape.get("capacity_ml",-1))
 return result

func boundary_topology(origin:Vector3)->Dictionary:
 var edges:Dictionary={};var triangles:=0;var degenerate:=0;var volume:=0.0
 for node:MeshInstance3D in game.lakes._meshes.values():
  if node.mesh==null:continue
  var arrays:Array=node.mesh.surface_get_arrays(0)
  var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
  if not indices.is_empty():
   var expanded:=PackedVector3Array();expanded.resize(indices.size())
   for i in indices.size():expanded[i]=vertices[indices[i]]
   vertices=expanded
  for i in range(0,vertices.size(),3):
   triangles+=1
   var points:Array[Vector3]=[vertices[i]+node.position,vertices[i+1]+node.position,vertices[i+2]+node.position]
   if (points[1]-points[0]).cross(points[2]-points[0]).length_squared()<1e-12:degenerate+=1
   volume+=(points[0]-origin).dot((points[2]-origin).cross(points[1]-origin))/6.0
   for edge in 3:
    var a:=str(Vector3i((points[edge]*4096).round()));var b:=str(Vector3i((points[(edge+1)%3]*4096).round()))
    var key:=a+"|"+b if a<b else b+"|"+a
    var pair:Vector2i=edges.get(key,Vector2i.ZERO);pair.x+=1;pair.y+=1 if a<b else -1;edges[key]=pair
 var open_edges:=0
 for key:String in edges:
  var pair:Vector2i=edges[key]
  if pair.x<2 or pair.x%2!=0 or pair.y!=0:
   open_edges+=1
   if open_edges<=16:print("WATER_OPEN_EDGE ",key," ",pair)
 return {"triangles":triangles,"degenerate":degenerate,"open_edges":open_edges,"rendered_m3":absf(volume),"owned_m3":game.lakes.statistics().water_ml/1000000.0}

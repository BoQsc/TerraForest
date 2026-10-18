# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var phases:Array=[]
func settled()->bool:
 var c=game.ground_cover
 return c.resident.size()==c._wanted.size() and c._dirty.is_empty() and c._requests.is_empty() and c._scatter_job.is_empty() and c._support_job.is_empty() and game.terrain.backend.queued()==0 and game.terrain.backend.status()=="idle"
func sample(label:String)->void:
 for frame in 45:await RenderingServer.frame_post_draw
 var frames:Array[float]=[];var gpu:Array[float]=[];var cpu:Array[float]=[];var previous:=Time.get_ticks_usec()
 for frame in 120:
  await RenderingServer.frame_post_draw
  var now:=Time.get_ticks_usec();frames.append((now-previous)/1000.0);previous=now
  gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
  cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
 frames.sort();gpu.sort();cpu.sort()
 phases.append({"name":label,"frame_p95":frames[113],"worst":frames.back(),"gpu_median":gpu[60],"gpu_p95":gpu[113],"cpu_median":cpu[60]})
 root.get_texture().get_image().save_png("res://reports/vegetation_lighting/"+label+".png")
func run()->void:
 DirAccess.make_dir_recursive_absolute("res://reports/vegetation_lighting")
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;game.max_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved world ready"):await done();return
 var centers:=preload("res://addons/world_ecosystem/woodland_authoring.gd").centers(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 var center:Vector3=centers[0]
 game.teleport(center);await wait_for(func():return not game.loading_active,45)
 game.set_physics_process(false);game._clear_motion()
 check(await wait_for(settled,45),"ground cover and terrain queues settle")
 var c=game.ground_cover
 var target:Vector3=game.player.position
 # Actual saved meadow; planted and natural cover use the production materials/batches.
 game.camera.global_position=target+Vector3(0,2.0,4);game.camera.look_at(target+Vector3(0,0.3,-4))
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 if "--cover-travel" in OS.get_cmdline_user_args():
  await travel()
  await done();return
 for batch in c.batches:batch.set_casts_shadows(false)
 await sample("shadows_off")
 for kind in [0,1,6,7]:c.batches[kind].set_casts_shadows(true)
 await sample("understory_shadows")
 for batch in c.batches:batch.set_casts_shadows(true)
 await sample("all_cover_shadows")
 for batch in c.batches:batch.set_casts_shadows(false)
 await sample("shadows_off_repeat")
 check(c.rejected_batches==0,"no rejected publication")
 check(root.size==Vector2i(1920,1080) and Engine.max_fps==60,"1080p cap60")
 var render:Array=[]
 for batch in c.batches:
  var stat:Dictionary=batch.render_stats();render.append(stat)
  check(stat.resident_transform_bytes<=stat.byte_limit,"native render byte bound")
  check(stat.budget_deferred==0,"all visible candidate pages fit resident budgets")
 FileAccess.open("res://reports/vegetation_lighting/result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"phases":phases,"render":render,"scope":"Saved meadow stationary shadow comparison; no thermal or old-laptop claim."},"  "))
 for kind in [0,1,6,7]:c.batches[kind].set_casts_shadows(true)
 await travel()
 await done()
func done()->void:
 print("VEGETATION_LIGHTING failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)

func travel()->void:
 var c=game.ground_cover
 var before:PackedByteArray=c.removed.capture_storage_snapshot()
 var initial:Vector3=game.camera.global_position
 var rows:Array=[];var previous:=Time.get_ticks_usec();var elapsed:=0.0
 while elapsed<10.0:
  await RenderingServer.frame_post_draw
  var now:=Time.get_ticks_usec();var dt:float=(now-previous)/1000000.0;previous=now;elapsed+=dt
  game.camera.global_position=initial+Vector3(minf(elapsed,10.0)*6.4,0,0)
  game.camera.look_at(game.camera.global_position+Vector3(2,-1.5,-8))
  rows.append(dt*1000.0)
 check(await wait_for(settled,25),"64m travel settles new cover owners")
 check(c.removed.capture_storage_snapshot()==before,"render travel preserves gathered and planted state")
 check(c.rejected_batches==0 and c.resident.size()<=49,"travel retains bounded owners without rejected publication")
 var render:Array=[]
 for batch in c.batches:
  var stat:Dictionary=batch.render_stats();render.append(stat)
  check(stat.budget_deferred==0 and stat.resident_transform_bytes<=stat.byte_limit,"travel preserves visible pages within budgets")
 rows.sort()
 root.get_texture().get_image().save_png("res://reports/vegetation_lighting/travel_end.png")
 FileAccess.open("res://reports/vegetation_lighting/travel.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"frame_p95":rows[int(rows.size()*0.95)],"worst":rows.back(),"render":render,"scope":"Scripted 64m camera traversal across streaming boundaries at 6.4m/s; no player movement/long-run qualification."},"  "))

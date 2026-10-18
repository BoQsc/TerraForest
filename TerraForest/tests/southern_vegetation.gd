# SPDX-License-Identifier: 0BSD
extends "res://tests/vegetation_lighting_world.gd"
func settled()->bool:
 var c=game.ground_cover
 return c.resident.size()==c._wanted.size() and c._dirty.is_empty() and c._requests.is_empty() and c._scatter_job.is_empty() and c._support_job.is_empty()
func run()->void:
 DirAccess.make_dir_recursive_absolute("res://reports/southern_vegetation")
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.max_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved world ready"):await done();return
 var center:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator).sites[4].position
 if "--invalidate-before-travel" in OS.get_cmdline_user_args():
  game.ground_cover.reset();game.ground_cover._process(0.0)
  game.ground_cover._exclusion_changed(AABB())
 game.teleport(center+Vector3(28,0,32))
 if not check(await wait_for(func():return not game.loading_active,45),"southern arrival ready"):await done();return
 game.set_physics_process(false);game._clear_motion()
 var begin:=Time.get_ticks_msec()
 var progress:Array=[]
 while not settled() and Time.get_ticks_msec()-begin<25000:
  var c=game.ground_cover
  progress.append({"ms":Time.get_ticks_msec()-begin,"resident":c.resident.size(),"wanted":c._wanted.size(),"dirty":str(c._dirty.keys()),"pending":str(c._pending),"requests":str(c._requests.keys()),"scatter_key":str(c._scatter_job.get("key")),"layer":c._scatter_job.get("layer",-1),"support":str(c._support_job.keys()),"queue":game.terrain.backend.queued(),"worker":game.terrain.backend.status(),"pending_edit":game.terrain.pending_edit,"revision":game.terrain.published_revision,"rejected":c.rejected_batches})
  var until:=Time.get_ticks_msec()+500
  while Time.get_ticks_msec()<until:await process_frame
 check(settled(),"all ground cover owners settled")
 var settle_ms:=Time.get_ticks_msec()-begin
 var c=game.ground_cover
 print("COVER_STATE residents=",c.resident.size()," wanted=",c._wanted.size()," dirty=",c._dirty.size()," requests=",c._requests.size()," scatter_owner=",c._scatter_job.get("key")," layer=",c._scatter_job.get("layer")," support=",c._support_job.keys())
 game.camera.global_position=center+Vector3(28,15,32);game.camera.look_at(center+Vector3(0,2,0))
 for frame in 60:await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/southern_vegetation/overview.png")
 var foot:=center+Vector3(28,0,32)
 await wait_for(func():return not game._terrain_pick(foot+Vector3.UP*12,foot-Vector3.UP*12).is_empty(),8)
 var hit:Dictionary=game._terrain_pick(foot+Vector3.UP*12,foot-Vector3.UP*12)
 if check(not hit.is_empty(),"walking height terrain hit"):
  game.camera.global_position=hit.position+Vector3.UP*1.7
  game.camera.look_at(center+Vector3(0,1.5,0))
 for frame in 60:await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/southern_vegetation/ground.png")
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 for frame in 30:await RenderingServer.frame_post_draw
 var timings:Array=[];var gpu:Array=[];var previous:=Time.get_ticks_usec()
 for frame in 120:
  await RenderingServer.frame_post_draw
  var now:=Time.get_ticks_usec();timings.append((now-previous)/1000.0);previous=now
  gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
 timings.sort();gpu.sort()
 var performance:={"frame_median":timings[60],"frame_p95":timings[113],"worst":timings.back(),"gpu_median":gpu[60]}
 var render:Array=[]
 for batch in game.ground_cover.batches:
  var stat:Dictionary=batch.render_stats();render.append(stat)
  check(stat.budget_deferred==0,"no deferred vegetation pages")
 FileAccess.open("res://reports/southern_vegetation/result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"settle_ms":settle_ms,"progress":progress,"render":render,"performance":performance},"  "))
 await done()

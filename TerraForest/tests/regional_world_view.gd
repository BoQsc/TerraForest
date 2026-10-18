# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+60000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 if game.loading_active or game.terrain.backend.world_generator not in [7,8,9,10,11]:quit(1);return
 game.set_physics_process(false);game._clear_motion()
 var plan:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 var site_index:=0
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--regional-site="):site_index=int(arg.trim_prefix("--regional-site="))
 if site_index<0 or site_index>=plan.sites.size():quit(1);return
 var center:Vector3=plan.sites[site_index].position
 game.teleport(center+Vector3(0,0,100))
 deadline=Time.get_ticks_msec()+45000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 if game.loading_active:quit(1);return
 game.camera.global_position=center+Vector3(35,25,125);game.camera.look_at(center+Vector3(0,0,50))
 if site_index>0:
  game.camera.global_position=center+Vector3(25,18,20);game.camera.look_at(center+Vector3(-15,2,-20))
 if "--ground-eye" in OS.get_cmdline_user_args():
  game.camera.global_position=center+Vector3(25,2,20);game.camera.look_at(center+Vector3(10,0,5))
 if "--dense-ground-check" in OS.get_cmdline_user_args():
  deadline=Time.get_ticks_msec()+45000
  var ready:=false
  while not ready and Time.get_ticks_msec()<deadline:
   await process_frame
   ready=true
   var owner:=Vector2i(floori(game.camera.global_position.x/32),floori(game.camera.global_position.z/32))
   for x in range(-1,2):
    for z in range(-1,2):
     var key:=owner+Vector2i(x,z)
     ready=ready and game.ground_cover.resident.has(key) and game.ground_cover._resident_layers.get(key,0)==16 and not game.ground_cover._dirty.has(key)
  var clumps:=0
  for batch in game.ground_cover.batches:clumps+=batch.get_ids().size()
  print("REGIONAL_DENSE_GROUND ready=",ready," clumps=",clumps," rejected=",game.ground_cover.rejected_batches)
  if not ready or game.ground_cover.rejected_batches>0:quit(1);return
 for i in 120:await process_frame
 var frames:Array[float]=[]
 var last:=Time.get_ticks_usec()
 for i in 180:
  await process_frame
  var now:=Time.get_ticks_usec();frames.append(float(now-last)/1000.0);last=now
 frames.sort()
 print("REGIONAL_VIEW_FRAME_MS median=",frames[90]," p95=",frames[171]," max=",frames[179]," scope=stationary_after_arrival")
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/regional_world_view_%d.png" % site_index)
 print("REGIONAL_WORLD_VIEW generator=",game.terrain.backend.world_generator," buildings_cells=",game.structures.blocks.stats().cells," roads=",plan.roads.size())
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit()

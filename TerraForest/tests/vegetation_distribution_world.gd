# SPDX-License-Identifier: 0BSD
extends "res://tests/southern_vegetation.gd"
func capture_density(label:String)->Dictionary:
 game.player_hud.set_open(false)
 for frame in 45:await RenderingServer.frame_post_draw
 var frames:Array=[];var gpu:Array=[];var previous:=Time.get_ticks_usec()
 for frame in 120:
  await RenderingServer.frame_post_draw
  var now:=Time.get_ticks_usec();frames.append((now-previous)/1000.0);previous=now
  gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
 frames.sort();gpu.sort()
 root.get_texture().get_image().save_png("res://reports/vegetation_distribution/"+label+".png")
 return {"label":label,"frame_p95":frames[113],"worst":frames.back(),"gpu_median":gpu[60]}
func run()->void:
 DirAccess.make_dir_recursive_absolute("res://reports/vegetation_distribution")
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.max_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"world ready"):await done();return
 var center:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator).sites[4].position
 center+=Vector3(28,0,32);center.x=roundf(center.x/32)*32;center.z=roundf(center.z/32)*32
 var found:=false
 for offset in [0,32,-32,64,-64,96,-96,128]:
  var candidate:=center+Vector3(offset,0,0);var room:=true
  for dz in [-1,0]:
   for dx in [-1,0]:
    var count:=0
    for species in game.ground_cover.removed.query(Vector2i(int(candidate.x/32)+dx,int(candidate.z/32)+dz)):count+=species.ids.size()
    if count>80:room=false
  if room:center=candidate;found=true;break
 if not check(found,"reference owners have room before planting"):await done();return
 game.teleport(center)
 if not check(await wait_for(func():return not game.loading_active,45),"arrival ready"):await done();return
 game.set_physics_process(false);game._clear_motion()
 if not check(await wait_for(settled,20),"cover ready"):await done();return
 await wait_for(func():return not game._terrain_pick(center+Vector3.UP*12,center-Vector3.UP*12).is_empty(),8)
 var hit:Dictionary=game._terrain_pick(center+Vector3.UP*12,center-Vector3.UP*12)
 if not check(not hit.is_empty(),"ground hit"):await done();return
 center.y=hit.position.y
 var c=game.ground_cover
 var original:PackedByteArray=c.removed.capture_storage_snapshot()
 game.camera.global_position=center+Vector3(0,2.0,5);game.camera.look_at(center+Vector3(0,0.25,-1))
 for material in c.foliage_materials:material.set_shader_parameter("wind_strength",0.0)
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 var phases:Array=[]
 phases.append(await capture_density("normal"))
 var planted:Dictionary={"ok":true,"density":"unchanged"}
 var route:Array=[]
 for step in 180:
  game.camera.global_position=center+Vector3(step/30.0,2,5)
  game.camera.look_at(center+Vector3(step/30.0,0.25,-1))
  var tick:=Time.get_ticks_usec();await RenderingServer.frame_post_draw
  route.append((Time.get_ticks_usec()-tick)/1000.0)
 route.sort();print("TRAVEL_P95 ",route[170]," WORST ",route.back())
 phases.append(await capture_density("travel_end"))
 check(c.removed.capture_storage_snapshot()==original,"source vegetation state unchanged")
 check(c.rejected_batches==0,"no rejected publications")
 check(root.size==Vector2i(1920,1080),"1080p comparison")
 FileAccess.open("res://reports/vegetation_distribution/result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"planted":planted,"center":str(center),"phases":phases,"scope":"Native distribution at unchanged candidate budget; 6m camera travel, no authored extra planting."},"  "))
 await done()

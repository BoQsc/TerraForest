# SPDX-License-Identifier: 0BSD
extends "res://tests/southern_vegetation.gd"
func run()->void:
 DirAccess.make_dir_recursive_absolute("res://reports/vegetation_near_shadows")
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.max_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"world ready"):await done();return
 var center:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator).sites[4].position
 game.teleport(center+Vector3(28,0,32))
 if not check(await wait_for(func():return not game.loading_active,45),"arrival ready"):await done();return
 game.set_physics_process(false);game._clear_motion()
 if not check(await wait_for(settled,20),"cover ready"):await done();return
 var foot:Vector3=center+Vector3(28,0,32)
 await wait_for(func():return not game._terrain_pick(foot+Vector3.UP*12,foot-Vector3.UP*12).is_empty(),8)
 var hit:Dictionary=game._terrain_pick(foot+Vector3.UP*12,foot-Vector3.UP*12)
 if not check(not hit.is_empty(),"ground hit"):await done();return
 game.camera.global_position=hit.position+Vector3.UP*1.7
 game.camera.look_at(hit.position+Vector3(-1,0,-3))
 for material in game.ground_cover.foliage_materials:material.set_shader_parameter("wind_strength",0.0)
 print("SHADOW_BASE ",game.sun.directional_shadow_mode," splits ",game.sun.directional_shadow_split_1," ",game.sun.directional_shadow_split_2," ",game.sun.directional_shadow_split_3)
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 check(is_equal_approx(game.sun.directional_shadow_split_1,0.035) and game.sun.directional_shadow_blend_splits and ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")==4096,"production near-shadow configuration")
 if "--shadow-slope" in OS.get_cmdline_user_args():
  await shadow_slope(center)
  await done();return
 if "--shadow-travel" in OS.get_cmdline_user_args():
  await shadow_travel(hit.position)
  await done();return
 var results:Array=[]
 for variant in ["baseline","focused","focused_low_bias","focused_4096"]:
  if variant=="baseline":
   RenderingServer.directional_shadow_atlas_set_size(2048,false)
   game.sun.directional_shadow_split_1=0.1
   game.sun.directional_shadow_split_2=0.2
   game.sun.directional_shadow_split_3=0.5
   game.sun.directional_shadow_blend_splits=false
  if variant!="baseline":
   game.sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
   game.sun.directional_shadow_split_1=0.035
   game.sun.directional_shadow_split_2=0.12
   game.sun.directional_shadow_split_3=0.35
   game.sun.directional_shadow_blend_splits=true
  if variant=="focused_low_bias":game.sun.shadow_normal_bias=0.7
  if variant=="focused_4096":
   game.sun.shadow_normal_bias=2.0
   RenderingServer.directional_shadow_atlas_set_size(4096,false)
  for frame in 45:await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/vegetation_near_shadows/"+variant+".png")
  for frame in 30:await RenderingServer.frame_post_draw
  var gpu:Array=[]
  for frame in 60:
   await RenderingServer.frame_post_draw
   gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
  gpu.sort();results.append({"variant":variant,"gpu_median":gpu[30]})
 check(game.ground_cover.rejected_batches==0,"no rejected cover")
 FileAccess.open("res://reports/vegetation_near_shadows/result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"phases":results},"  "))
 await done()

func shadow_travel(foot:Vector3)->void:
 var start:=foot+Vector3.UP*1.7
 var snapshot:PackedByteArray=game.ground_cover.removed.capture_storage_snapshot()
 var frames:Array=[];var gpu:Array=[]
 var previous:=Time.get_ticks_usec()
 for step in 360:
  game.camera.global_position=start+Vector3(float(step)/30.0,0,0)
  game.camera.look_at(foot+Vector3(0,0,-5))
  await RenderingServer.frame_post_draw
  var now:=Time.get_ticks_usec();frames.append((now-previous)/1000.0);previous=now
  gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
 # Replay representative poses for visual evidence, outside the timed route.
 for step in [0,60,120,180,240,359]:
  game.camera.global_position=start+Vector3(float(step)/30.0,0,0)
  game.camera.look_at(foot+Vector3(0,0,-5))
  for frame in 3:await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/vegetation_near_shadows/travel_%03d.png"%step)
 check(game.ground_cover.removed.capture_storage_snapshot()==snapshot,"shadow travel preserves collected and placed state")
 check(game.ground_cover.rejected_batches==0,"shadow travel has no rejected cover")
 check(root.size==Vector2i(1920,1080),"fullscreen 1080p viewport")
 frames.sort();gpu.sort()
 FileAccess.open("res://reports/vegetation_near_shadows/travel.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"frame_p95":frames[int(frames.size()*0.95)],"frame_worst":frames.back(),"gpu_median":gpu[180],"scope":"12 m camera orbit/translation across directional cascade boundaries. Wind frozen, no screenshot readback during timing. Sparse replay images do not prove absence of temporal shimmer."},"  "))

func shadow_slope(center:Vector3)->void:
 var probes:=PackedVector3Array()
 for z in 8:
  for x in 8:probes.append(Vector3(center.x-112+x*32,0,center.z-112+z*32))
 var response:Dictionary={}
 var token:int=preload("res://addons/volumetric_terrain/surface_tokens.gd").allocate()
 var receive:=func(id:int,points:PackedVector3Array,normals:PackedVector3Array,epoch:int,revision:int):
  if id==token:response.merge({"points":points,"normals":normals,"epoch":epoch,"revision":revision})
 game.terrain.surface_batch_ready.connect(receive)
 var admitted:bool=await wait_for(func():return game.terrain.request_surface_batch(probes,token),5)
 if admitted:await wait_for(func():return not response.is_empty(),5)
 game.terrain.surface_batch_ready.disconnect(receive)
 if not check(admitted and response.get("points",PackedVector3Array()).size()==64,"slope support sample ready"):return
 var index:=-1;var best:=1.0
 for i in 64:
  var n:Vector3=response.normals[i]
  if n.y>0.82 and n.y<best:best=n.y;index=i
 if not check(index>=0 and best<0.98,"find vegetation-bearing slope"):return
 var foot:Vector3=response.points[index]
 game.teleport(foot)
 if not check(await wait_for(func():return not game.loading_active,30),"slope terrain ready"):return
 game.set_physics_process(false);game._clear_motion()
 if not check(await wait_for(settled,20),"slope cover ready"):return
 game.camera.global_position=foot+Vector3.UP*1.7
 var normal:Vector3=response.normals[index]
 var downhill:=Vector3(normal.x,0,normal.z).normalized()
 game.camera.look_at(foot+downhill*5)
 for material in game.ground_cover.foliage_materials:material.set_shader_parameter("wind_strength",0.0)
 for label in ["slope_on","slope_off","slope_on_repeat"]:
  game.sun.shadow_enabled=label!="slope_off"
  for frame in 45:await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/vegetation_near_shadows/"+label+".png")
 FileAccess.open("res://reports/vegetation_near_shadows/slope.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"point":str(foot),"normal_y":best,"angle_degrees":rad_to_deg(acos(best)),"scope":"Fixed downhill view, frozen foliage wind; shadow on/off/repeat. No claim for moving-view shimmer or all terrain slopes."},"  "))

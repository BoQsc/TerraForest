# SPDX-License-Identifier: 0BSD
extends "res://tests/southern_vegetation.gd"
func pose(center:Vector3,frame:int)->void:
 game.camera.global_position=center+Vector3(0,1.7,float(frame)*6.0/119.0)
 game.camera.look_at(game.camera.global_position+Vector3(10,-1.2,0))
func motion_phase(label:String,center:Vector3)->Dictionary:
 game.player_hud.set_open(false)
 pose(center,0)
 for frame in 45:await RenderingServer.frame_post_draw
 var frames:Array=[];var gpu:Array=[];var previous:=Time.get_ticks_usec()
 for frame in 120:
  pose(center,frame)
  await RenderingServer.frame_post_draw
  var now:=Time.get_ticks_usec();frames.append((now-previous)/1000.0);previous=now
  gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
 frames.sort();gpu.sort()
 # Separate identical replay: synchronous screenshots must not contaminate timings.
 pose(center,0)
 for frame in 45:await RenderingServer.frame_post_draw
 for frame in 120:
  pose(center,frame)
  await RenderingServer.frame_post_draw
  if frame>=54 and frame<62:
   root.get_texture().get_image().save_png("res://reports/vegetation_motion_diagnostic/%s_%03d.png"%[label,frame])
 return {"label":label,"frame_p95":frames[113],"worst":frames.back(),"gpu_median":gpu[60],"taa":root.use_taa}
func run()->void:
 DirAccess.make_dir_recursive_absolute("res://reports/vegetation_motion_diagnostic")
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.max_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"world ready"):await done();return
 var center:=Vector3(1089,62,1792)
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
 game.camera.global_position=center+Vector3(0,1.7,0);game.camera.look_at(center+Vector3(10,0.5,0))
 for material in c.foliage_materials:material.set_shader_parameter("wind_strength",0.0)
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 var phases:Array=[]
 var original_taa:bool=root.use_taa
 root.use_taa=false
 phases.append(await motion_phase("normal",center))
 root.use_taa=true
 phases.append(await motion_phase("taa",center))
 root.use_taa=false
 phases.append(await motion_phase("normal_repeat",center))
 root.use_taa=original_taa
 check(c.removed.capture_storage_snapshot()==original,"source vegetation state unchanged")
 check(c.rejected_batches==0,"no rejected publications")
 check(root.size==Vector2i(1920,1080),"1080p comparison")
 FileAccess.open("res://reports/vegetation_motion_diagnostic/result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"center":str(center),"phases":phases,"scope":"Repeated six-metre camera path. Timing excludes image capture replay. Production settings unchanged."},"  "))
 await done()

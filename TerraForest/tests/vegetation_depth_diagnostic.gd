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
 root.get_texture().get_image().save_png("res://reports/vegetation_depth_diagnostic/"+label+".png")
 return {"label":label,"frame_p95":frames[113],"worst":frames.back(),"gpu_median":gpu[60]}
func run()->void:
 DirAccess.make_dir_recursive_absolute("res://reports/vegetation_depth_diagnostic")
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
 phases.append(await capture_density("normal"))
 var original_shader:Shader=c.grass_material.shader
 var lifted:=Shader.new()
 lifted.code=original_shader.code.replace("float age =", "VERTEX.y += 0.75*smoothstep(20.0,40.0,view_distance);\n    float age =")
 for material in c.foliage_materials:material.shader=lifted
 phases.append(await capture_density("lifted_far_cover"))
 for material in c.foliage_materials:material.shader=original_shader
 phases.append(await capture_density("normal_repeat"))
 check(c.removed.capture_storage_snapshot()==original,"source vegetation state unchanged")
 check(c.rejected_batches==0,"no rejected publications")
 check(root.size==Vector2i(1920,1080),"1080p comparison")
 FileAccess.open("res://reports/vegetation_depth_diagnostic/result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"center":str(center),"phases":phases,"scope":"Temporary far-cover elevation isolates terrain depth intersections; not a proposed production fix."},"  "))
 await done()

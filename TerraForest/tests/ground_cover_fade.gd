# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func rows(batch:Node)->Dictionary:
 var result:Dictionary={}
 for child in batch.get_children():
  if child is MultiMeshInstance3D:
   for i in child.multimesh.instance_count:
    var t:Transform3D=child.multimesh.get_instance_transform(i)
    result[roundi(t.origin.x+child.position.x)]=child.multimesh.get_instance_custom_data(i)
 return result
func run()->void:
 if DisplayServer.get_name()=="headless":
  print("Requires graphical renderer for MultiMesh readback");quit(2);return
 var batch=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch)
 check(batch.configure_asset("fade/test",BoxMesh.new()),"asset configured")
 check(batch.configure_appearance_fade(),"native appearance packet enabled")
 check(batch.configure_render_streaming(true,80,128,256,2,128),"strict 64-byte upload/residency budgets")
 var ids:=PackedInt64Array([1,2]);var poses:Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3(1,0,0)),Transform3D(Basis.IDENTITY,Vector3(2,0,0))]
 batch.upsert_transforms(ids,poses)
 for frame in 8:await process_frame
 var first:=rows(batch);var saved:PackedByteArray=batch.capture_storage_snapshot() if batch.has_method("capture_storage_snapshot") else batch.capture_snapshot()
 check(first.size()==2 and first[1].g==1,"both native instances carry fade start")
 await create_timer(0.1).timeout
 batch.upsert_transforms(PackedInt64Array([3]),[Transform3D(Basis.IDENTITY,Vector3(3,0,0))])
 for frame in 8:await process_frame
 var second:=rows(batch)
 check(second.size()==3 and second[1]==first[1] and second[2]==first[2] and second[3].r>first[1].r,"page rebuild preserves old appearances and fades only new identities")
 check(batch.render_stats().resident_transform_bytes==192 and batch.render_stats().page_capacity==2,"GPU byte accounting includes fade packet")
 batch.remove_instances(PackedInt64Array([3]))
 for frame in 8:await process_frame
 check(batch.capture_snapshot()==saved,"visual fades leave authoritative snapshot unchanged")
 batch.remove_instances(PackedInt64Array([1,2]))
 check(batch.render_stats().appearance_records==0,"retirement releases appearance records")
 batch.free()
 await visual_fade()
 print("GROUND_COVER_FADE failures=",failures);quit(1 if failures else 0)

func lit_pixels()->int:
 await RenderingServer.frame_post_draw
 var image:=root.get_texture().get_image()
 var count:=0
 for y in range(0,image.get_height(),4):
  for x in range(0,image.get_width(),4):
   var color:=image.get_pixel(x,y)
   if maxf(color.r,maxf(color.g,color.b))>0.08:count+=1
 return count
func visual_fade()->void:
 var world:=Node3D.new();root.add_child(world)
 var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,0.4,1.4);camera.look_at(Vector3(0,0.3,0));camera.current=true
 var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color.BLACK;env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=1.0;world.add_child(env)
 var mesh:=preload("res://addons/world_ecosystem/woodland_mesh.gd").build(2)
 var material:ShaderMaterial=mesh.surface_get_material(0);material.set_shader_parameter("wind_strength",0.0)
 var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.use_custom_data=true;multi.mesh=mesh;multi.instance_count=1;multi.set_instance_transform(0,Transform3D.IDENTITY);multi.set_instance_custom_data(0,Color(10,1,0,0))
 var instance:=MultiMeshInstance3D.new();instance.multimesh=multi;world.add_child(instance)
 DirAccess.make_dir_recursive_absolute("res://reports/cover_fade")
 var counts:Array[int]=[]
 for age in [0.0,0.325,0.7]:
  material.set_shader_parameter("cover_clock",10.0+age)
  for frame in 3:await RenderingServer.frame_post_draw
  counts.append(await lit_pixels())
  root.get_texture().get_image().save_png("res://reports/cover_fade/age_%s.png"%age)
 check(counts[0]==0 and counts[1]>counts[2]*0.25 and counts[1]<counts[2]*0.75 and counts[2]>100,"production shader fades from invisible through partial coverage to full grass")
 material.set_shader_parameter("distance_fade_start",36.0);material.set_shader_parameter("distance_fade_end",56.0)
 material.set_shader_parameter("cover_eye",Vector3(46,0,0))
 for frame in 3:await RenderingServer.frame_post_draw
 var halfway:=await lit_pixels()
 material.set_shader_parameter("cover_eye",Vector3(57,0,0))
 for frame in 3:await RenderingServer.frame_post_draw
 check(halfway>counts[2]*0.25 and halfway<counts[2]*0.75 and await lit_pixels()==0,"same opaque shader fades smoothly over distance")
 print("FADE_PIXEL_COUNTS ",counts," distance_mid=",halfway)
 world.free();await process_frame

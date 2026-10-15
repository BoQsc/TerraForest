# SPDX-License-Identifier: 0BSD
extends "res://tests/water_raised_world.gd"
func run():
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Normal disposable world ready")
 if failures:await finish();return
 game.set_process(false);game.set_physics_process(false);game._clear_motion()
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var center:=Vector3(entry.seed.x,entry.level,entry.seed.z)
 var material:ShaderMaterial=game.lakes._material
 var original:Shader=material.shader
 var solid:=Shader.new()
 solid.code="shader_type spatial; render_mode unshaded, cull_disabled; void fragment(){ ALBEDO=FRONT_FACING ? vec3(0.05,0.8,0.2) : vec3(0.9,0.1,0.2); }"
 var bank:=center+Vector3(5,0,0)
 for step in range(1,81):
  var p:Vector3=center+Vector3(step*.25,0,0)
  var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*4,p-Vector3.UP*4,1))
  if not hit.is_empty() and hit.position.y>entry.level+.15 and hit.position.y<entry.level+.9:
   bank=hit.position;break
 var wedge_count:=0
 for step in range(-8,3):
  var cell:=Vector3(floorf((bank.x+step*.25)*2)*.5,floorf((entry.level-.5)*2)*.5,floorf(bank.z*2)*.5)
  var low:=INF;var high:=-INF;var valid:=true
  for corner:Vector3 in [Vector3.ZERO,Vector3(.5,0,0),Vector3(0,0,.5),Vector3(.5,0,.5)]:
   var p:Vector3=cell+corner
   var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*4,p-Vector3.UP*4,1))
   if hit.is_empty():valid=false;break
   low=minf(low,hit.position.y);high=maxf(high,hit.position.y)
  var profile:Dictionary=game.lakes.water.cell_geometry(cell+Vector3.ONE*.25)
  if valid and low<cell.y+.48 and high>cell.y+.52 and not profile.is_empty():
   wedge_count+=1
   check(profile.capacity_ml>0,"Sloping bank cell retains its real air wedge")
 check(wedge_count>0,"Regression exercises partially submerged bank cells")
 var gaps:Array=[]
 for instance:MeshInstance3D in game.lakes._meshes.values():
  var mesh:Mesh=instance.mesh
  if mesh==null or mesh.get_surface_count()==0:continue
  var vertices:PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
  for index in range(0,vertices.size(),9):
   var p:Vector3=vertices[index]
   if p.y>entry.level-.05 or p.y<entry.level-1 or absf(p.z-bank.z)>1 or absf(p.x-bank.x)>2:continue
   var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*3,p-Vector3.UP*3,1))
   if not hit.is_empty():gaps.append({"point":p,"gap":p.y-hit.position.y})
 gaps.sort_custom(func(a,b):return a.gap>b.gap)
 print("SHORE_CONTACT_GAPS count=",gaps.size()," largest=",gaps.slice(0,12))
 for view:int in 2:
  game.camera.global_position=center+Vector3(0,-1.2,4) if view==0 else bank+Vector3(1.5,1.5,1.5)
  game.camera.look_at(center+Vector3(0,-1.3,-4) if view==0 else bank-Vector3(1,0,0),Vector3.UP)
  game.water_camera.update()
  for mode:int in 3:
   material.shader=solid if mode==1 else original
   for instance:MeshInstance3D in game.lakes._meshes.values():instance.visible=mode!=2
   for frame in 5:await process_frame
   await photo("res://reports/water_boundary_%d_%d.png"%[view,mode])
 material.shader=original
 await finish()
func finish():
 if game!=null:game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_BOUNDARY_DIAGNOSTIC failures=",failures,"; visual diagnosis required");quit(failures)

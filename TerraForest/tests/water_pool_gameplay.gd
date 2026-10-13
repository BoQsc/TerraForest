# SPDX-License-Identifier: 0BSD
extends "res://tests/water_bucket_roundtrip.gd"
var initial_world:PackedByteArray
var pool_target:=Vector3.ZERO
func run():
 capture_writer=preload("res://tests/visual_capture_writer.gd").new()
 if capture_writer.start()!=OK:capture_writer=null;check(false,"Screenshot writer starts")
 process_frame.connect(record_frame)
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready") and game.temporary_world,"Temporary actual world ready")
 if failures:await finish();return
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var source:=Vector3(entry.seed.x+3,entry.level,entry.seed.z)
 var origin:Vector3=game.player.global_position+Vector3(0,0,10)
 var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin+Vector3.UP*30,origin-Vector3.UP*30,1))
 check(not hit.is_empty(),"Pool target has ordinary terrain")
 if failures:await finish();return
 var target:Vector3=hit.position
 var initial:PackedByteArray=game.lakes.capture_snapshot()
 initial_world=initial;pool_target=target
 var total:int=game.lakes.statistics().water_ml
 var offsets:Array[Vector3]=[Vector3.ZERO,Vector3.RIGHT,Vector3.BACK,Vector3(1,0,1),Vector3.ZERO,Vector3.RIGHT]
 results.actions=[]
 var sources:Array[Vector3]=[]
 for i in offsets.size():sources.append(source+Vector3(i%3,0,i/3))
 for index in offsets.size():
  var offset:Vector3=offsets[index]
  aim(sources[index])
  var scoop:Dictionary=await measured_click(MOUSE_BUTTON_LEFT)
  check(scoop.ready and held_ml()==1000000,"Collect one whole unit for the pool")
  if failures:await finish();return
  aim(target+offset)
  var pour:Dictionary=await measured_click(MOUSE_BUTTON_RIGHT)
  check(pour.ready and held_ml()==0,"Place whole unit beside or above existing water")
  check(game.lakes.statistics().water_ml==total,"Every placement conserves lake plus pool quantity")
  results.actions.append({"offset":offset,"scoop":scoop,"pour":pour})
  if failures:await finish();return
 var snapshot:PackedByteArray=game.lakes.capture_snapshot()
 var delta:=water_delta(initial,snapshot,target)
 results.components=local_components(delta.new_wet_cells)
 check(results.components.water_ml==6000000 and results.components.components.size()==1,"Six poured units form one connected local pool")
 results.topology=pool_topology(target)
 check(results.topology.triangles>0 and results.topology.unpaired_edges==0,"Actual published pool mesh is closed across all region packets")
 await capture_volume_side(target,6)
 check(game.lakes.restore_snapshot(snapshot),"Pool snapshot reloads through the world water component")
 check(await wait_publication(),"Cached pool surface republishes")
 check(amounts(game.lakes.capture_snapshot())==amounts(snapshot),"Cached reload preserves every lake and pool cell")
 check(game.lakes.statistics().sampled_nodes==0,"Cached pool reload needs no terrain resampling")
 results.recovery=[]
 # Aim at a visible top surface, not an old position that may now be empty.
 for i in range(offsets.size()-1,-1,-1):
  var visible:=visible_pool_top(target)
  check(visible.is_finite(),"Remaining pool has an aimable rendered top")
  if not visible.is_finite():await finish();return
  aim(visible)
  var scoop:Dictionary=await measured_click(MOUSE_BUTTON_LEFT)
  check(scoop.ready and held_ml()==1000000,"Recover a full unit from the reloaded pool")
  if failures:await finish();return
  var remaining_pool:=water_delta(initial,game.lakes.capture_snapshot(),target)
  var connected:=local_components(remaining_pool.new_wet_cells)
  check(connected.components.size()<=1,"Scoop leaves at most one connected pool, never isolated remnants")
  var topology:=pool_topology(target)
  check(topology.unpaired_edges==0 and topology.components<=1,"Remaining rendered water is closed and has no disconnected surface fragments")
  aim(sources[i])
  var pour:Dictionary=await measured_click(MOUSE_BUTTON_RIGHT)
  check(pour.ready and held_ml()==0,"Return recovered unit to lake")
  check(game.lakes.statistics().water_ml==total,"Recovery preserves total water")
  results.recovery.append({"scoop":scoop,"pour":pour,"components":connected,"topology":topology})
  if failures:await finish();return
 var remaining:=water_delta(initial,game.lakes.capture_snapshot(),target)
 check(remaining.new_wet_cells.is_empty(),"Recovery leaves no small stranded pool remnants")
 check(not game.lakes.water.surface_near(target,2.5).is_finite(),"Recovered pool leaves no stale visible surface")
 await finish()
func visible_pool_top(target:Vector3)->Vector3:
 var best:=Vector3.INF;var height:float=-INF
 # Probe the actual published triangles in a small visible footprint; no
 # authoritative cell metadata is used to find an otherwise invisible target.
 for z in range(-2,7):
  for x in range(-2,7):
   var point:=target+Vector3(x*0.25,0,z*0.25)
   var hit:Dictionary=game.lakes.water.raycast_surface(point+Vector3.UP*3,point-Vector3.UP)
   if hit.hit and hit.normal.y>0.5 and hit.point.y>height:best=hit.point;height=best.y
 return best
func pool_topology(target:Vector3,radius:float=4.0)->Dictionary:
 var edges:Dictionary={};var triangles:=0;var parents:Array[int]=[]
 for instance:MeshInstance3D in game.lakes._meshes.values():
  if instance.mesh==null:continue
  var vertices:PackedVector3Array=instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
  for i in range(0,vertices.size(),3):
   if ((vertices[i]+vertices[i+1]+vertices[i+2])/3.0).distance_to(target)>radius:continue
   parents.append(triangles);triangles+=1
   for j in 3:
    var a:Vector3=vertices[i+j];var b:Vector3=vertices[i+(j+1)%3]
    var forward:bool=a.x<b.x or (a.x==b.x and (a.y<b.y or (a.y==b.y and a.z<b.z)))
    var key:Array=[a,b] if forward else [b,a]
    if not edges.has(key):edges[key]=[]
    edges[key].append(triangles-1)
 var bad:=0
 for incident:Array in edges.values():
  if incident.size()!=2:bad+=1
  for i in range(1,incident.size()):
   var a:int=incident[0];var b:int=incident[i]
   while parents[a]!=a:a=parents[a]
   while parents[b]!=b:b=parents[b]
   parents[b]=a
 var components:=0
 for i in parents.size():
  if parents[i]==i:components+=1
 return {"triangles":triangles,"unpaired_edges":bad,"components":components}
func finish():
 if failures and not initial_world.is_empty():
  var remaining:=water_delta(initial_world,game.lakes.capture_snapshot(),pool_target)
  results.remaining_cells=remaining
  results.remaining_components=local_components(remaining.new_wet_cells)
  var dump:=FileAccess.open("res://reports/water_pool_recovery_failure.bin",FileAccess.WRITE);dump.store_buffer(game.lakes.capture_snapshot());dump.close()
  results.failed_from=game.camera.global_position;results.failed_to=game.camera.global_position-game.camera.global_basis.z*3.5
 if capture_writer!=null:
  while capture_writer.pending()>0:await process_frame
  results.png_jobs=capture_writer.close()
  for job:Dictionary in results.png_jobs:check(job.error==OK,"Review image saved")
 results.failures=failures;results.captures=captures
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/water_pool_gameplay.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 if is_instance_valid(game):game.terrain.shutdown();game.queue_free()
 await process_frame;await process_frame
 print("WATER_POOL_GAMEPLAY failures=",failures);quit(failures)

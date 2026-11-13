# SPDX-License-Identifier: 0BSD
extends "res://tests/water_material_surface.gd"

func _initialize():call_deferred("run_worker_checks")
func publication_fixture():
 # Publication is tested with a resolved body. Thin-film representation has
 # separate coverage and must not turn this into an empty-mesh comparison.
 var water=fixture(3,0,true)
 water.brush(Vector3(41.75,41.501,41.75),0.0,99000)
 return water

func run_worker_checks() -> void:
 var reference=publication_fixture();var expected:Dictionary={}
 for n in 100:
  var packet:Dictionary=reference.next_mesh()
  if packet.is_empty():break
  if packet.vertices>0:expected[packet.coordinate]=packet.arrays
 var water=publication_fixture();var actual:Dictionary={};var changed:=false;var completed:=false
 var reference_depth:float=reference.depth_at(Vector3(41.75,41.501,41.75))
 var jobs:=0;var pending_single:=true;var published:=false
 for n in 500:
  var packet:Dictionary=water.next_mesh_batch(true)
  if packet.is_empty():break
  if packet.has("job"):
   jobs+=1
   var repeated:Dictionary=water.next_mesh_batch(true)
   pending_single=pending_single and repeated.get("pending",false) and not repeated.has("job") and not repeated.complete
   if not changed:
    changed=water.brush(Vector3(41.75,41.501,41.75),0.0,1000)==1000
   var task:=WorkerThreadPool.add_task(packet.job.prepare,false,"Water mesh regression")
   while not WorkerThreadPool.is_task_completed(task):await process_frame
   WorkerThreadPool.wait_for_task_completion(task)
   check(packet.job.is_ready(),"Worker publishes completion after immutable arrays are ready")
   continue
  if packet.has("coordinate"):actual[packet.coordinate]=packet.arrays
  if packet.complete:
   completed=true
   check(not water.raycast_surface(Vector3(41.75,42.5,41.75),Vector3(41.75,41.5,41.75)).hit,"Completed worker arrays remain hidden before render publication")
   check(water.depth_at(Vector3(41.75,41.501,41.75))==0,"Unpublished water cannot change immersion")
   published=water.commit_mesh_batch(packet.batch)
   break
 check(jobs>0 and pending_single,"Only one prepared mesh job is returned while a worker is pending")
 check(changed and completed and actual==expected,"Live mutation cannot alter a worker's frozen mesh batch")
 check(published and water.raycast_surface(Vector3(41.75,42.5,41.75),Vector3(41.75,41.5,41.75)).hit,"Render commit publishes the matching worker query geometry")
 check(is_equal_approx(water.depth_at(Vector3(41.75,41.501,41.75)),reference_depth),"Immersion publishes the frozen occupied state alongside geometry")
 check(water.statistics().mesh_worker_reserved_bytes==0,"Consumed worker releases its memory reservation")

 # Cancel before dispatch: a later task must not publish the old terrain.
 var stale:Dictionary=water.next_mesh_batch(true)
 check(stale.has("job"),"Second mesh batch starts after the live edit")
 if stale.has("job"):
  var old_batch:int=stale.batch
  water.invalidate(AABB(Vector3(41.7,41.5,41.7),Vector3.ONE*.1))
  var task:=WorkerThreadPool.add_task(stale.job.prepare,false,"Cancelled water mesh regression")
  while not WorkerThreadPool.is_task_completed(task):await process_frame
  WorkerThreadPool.wait_for_task_completion(task)
  var next:Dictionary=water.next_mesh_batch(true)
  check(next.batch>old_batch and not water.commit_mesh_batch(old_batch),"Terrain invalidation rejects the cancelled worker batch")
  check(water.raycast_surface(Vector3(41.75,42.5,41.75),Vector3(41.75,41.5,41.75)).hit,"Cancelled preparation retains the previous displayed surface")
  # No job should escape this check's process lifetime.
  if next.has("job"):
   next.job.cancel();next.job.prepare()
 stale.clear();water=null;reference=null
 await process_frame
 print("WATER_MESH_WORKER failures=",failures," jobs=",jobs)
 quit(1 if failures else 0)

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
   var coordinator=load("res://addons/volumetric_water/lake_world.gd").new()
   coordinator.water=water
   check(not coordinator.statistics().render_ready,"A dispatched worker is not reported as visible water")
   coordinator.free()
   var repeated:Dictionary=water.next_mesh_batch(true)
   pending_single=pending_single and repeated.get("pending",false) and not repeated.has("job") and not repeated.complete
   if not changed:
    changed=water.brush(Vector3(41.75,41.501,41.75),0.0,1000)==1000
   var task:=WorkerThreadPool.add_task(packet.job.prepare,false,"Water mesh regression")
   while not WorkerThreadPool.is_task_completed(task):await process_frame
   WorkerThreadPool.wait_for_task_completion(task)
   check(packet.job.is_ready(),"Worker publishes completion after immutable arrays are ready")
   continue
  if packet.has("coordinate"):
   actual[packet.coordinate]=packet.arrays
   var compact:Array=packet.render_arrays
   var indices:PackedInt32Array=compact[Mesh.ARRAY_INDEX]
   var matches:bool=indices.size()==packet.arrays[Mesh.ARRAY_VERTEX].size()
   for slot in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_COLOR]:
    for i in indices.size():
     if compact[slot][indices[i]]!=packet.arrays[slot][i]:matches=false;break
   check(matches,"Indexed render buffers exactly reproduce published triangle attributes")
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

 # Exercise the production dispatcher without the packet retaining the job.
 # Native invalidation may drop the store's last reference before task entry.
 for iteration in 24:
  var owned_water=publication_fixture()
  var host=load("res://addons/volumetric_water/lake_world.gd").new()
  root.add_child(host);host.set_process(false);host.water=owned_water
  var dispatched:Dictionary=owned_water.next_mesh_batch(true)
  check(dispatched.has("job"),"Coordinator cancellation has an actual mesh job")
  if not dispatched.has("job"):host.free();break
  var weak:WeakRef=weakref(dispatched.job)
  host._start_mesh_job(dispatched.job)
  dispatched.clear()
  owned_water.invalidate(AABB(Vector3(41.7,41.5,41.7),Vector3.ONE*.1))
  check(weak.get_ref()!=null,"Dispatcher retains cancelled native job until join")
  # Actual exit-tree path must join before releasing its reference.
  host.free()
  check(weak.get_ref()==null,"Joined cancelled job releases its final owner")

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
 var current=publication_fixture()
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var saved:PackedByteArray=current.capture_snapshot(catalog)
 # A v12 cache includes a vacancy-count word even when there are no holes.
 if saved.decode_u32(4)<9:
  saved.resize(saved.size()+4);saved.encode_u32(saved.size()-4,0);saved.encode_u64(24,saved.decode_u64(24)+4)
 saved.encode_u32(4,12)
 # Upgrade the legacy test fixture with an explicit valid air density cache.
 var base:int=32+saved.decode_u32(8);saved.encode_u32(base+12,1)
 for i in 729:saved.encode_float(base+6160+i*4,1.0)
 var coordinator=load("res://addons/volumetric_water/lake_world.gd").new();coordinator.prepare()
 check(coordinator.restore_snapshot(saved) and coordinator.water.statistics().pending_regions==0,"Current 3D occupancy cache restores without resampling")
 saved.encode_u32(4,11)
 check(coordinator.restore_snapshot(saved) and coordinator.water.statistics().pending_regions>0 and coordinator.water.statistics().water_ml==current.statistics().water_ml,"Old occupancy cache migrates through terrain sampling without changing water quantity")
 coordinator.free()
 print("WATER_MESH_WORKER failures=",failures," jobs=",jobs)
 quit(1 if failures else 0)

# SPDX-License-Identifier: 0BSD
extends "res://tests/water_equilibrium.gd"
func _initialize()->void:run_scope.call_deferred()
func run_scope()->void:
 var cells:Dictionary={}
 for z in 64:
  for x in 64:cells[Vector3i(11+x*24,83,11+z*24)]=[0,500,125000]
 var donor:=Vector3i(11,83,11);var receiver:=donor-Vector3i.UP
 cells[receiver]=[0,500,0]
 var water:=fixture(cells)
 var total:int=water.statistics().water_ml
 water.settle_after_edit(AABB(Vector3(donor)*.5,Vector3.ONE*.5))
 var result:=await solve(water)
 check(result.get("ok",false) and result.get("snapshot_regions",4096)<16,"Local edit snapshots only its affected group with 4,096 resident pools: "+str(result))
 check(water.statistics().water_ml==total,"Scoped equilibrium conserves the entire store quantity")
 check(water.depth_at(Vector3(receiver)*.5+Vector3.ONE*.25)>0,"Local receiver fills in the large resident store")
 check(water.depth_at(Vector3(11+63*24,83,11+63*24)*.5+Vector3.ONE*.25)>0,"Unrelated far pool remains intact")
 var editable:=fixture({donor:[0,500,125000],receiver:[0,500,0]})
 for packet_index in 100:
  var packet:Dictionary=editable.next_mesh_batch(false)
  if packet.is_empty():break
  if packet.complete:editable.commit_mesh_batch(packet.batch)
 var original:Dictionary=amounts(editable)
 editable.settle_after_edit(AABB(Vector3(donor)*.5,Vector3.ONE*.5))
 var relaxed:Dictionary=await solve(editable)
 check(relaxed.get("ok",false) and amounts(editable)!=original,"Background relaxation has a real unpublished quantity change")
 var unpublished:Dictionary=editable.next_mesh_batch(true)
 editable.interrupt_relaxation()
 if unpublished.has("job"):unpublished.job.prepare()
 check(amounts(editable)==original and editable.runtime_state().settling_regions>0,"New edit discards only unpublished relaxation and preserves pending work")
 check(editable.brush(Vector3(donor)*.5+Vector3.ONE*.25,0,-1)==1 and editable.statistics().water_ml==124999,"New local edit remains authoritative after interrupting lake publication")
 cells.clear()
 for z in 400:
  for x in 360:cells[Vector3i(81+x,83,81+z)]=[0,500,125000]
 water=fixture(cells);total=water.statistics().water_ml
 water.settle_after_edit(AABB(Vector3(41,41.5,41),Vector3.ONE*.1))
 var local_job:RefCounted=water.begin_equilibrium(0,true)
 check(local_job!=null,"Local response is admitted without a whole-lake snapshot")
 if local_job!=null:
  var local_task:=WorkerThreadPool.add_task(local_job.prepare,false,"Local water response regression")
  while not WorkerThreadPool.is_task_completed(local_task):await process_frame
  WorkerThreadPool.wait_for_task_completion(local_task)
  var local_result:Dictionary=water.finish_equilibrium(local_job)
  check(local_result.get("ok",false) and local_result.get("local_response",false) and local_result.get("snapshot_regions",4096)<32 and local_result.get("cells",144000)<8192,"Local response stays spatially bounded inside a 144,000-cell lake: "+str(local_result))
  check(water.statistics().water_ml==total and water.runtime_state().settling_regions>0,"Local response conserves quantity and leaves wider relaxation pending")
  var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
  var resumed=ClassDB.instantiate("NativeRegionalWater")
  check(resumed.restore_snapshot(water.capture_snapshot(catalog)) and resumed.statistics().water_ml==total and resumed.runtime_state().settling_regions>0,"Saving after local publication preserves quantity and unfinished wider relaxation")
  var resumed_result:Dictionary=await solve(resumed)
  check(resumed_result.get("ok",false) and resumed.statistics().water_ml==total,"Restored local transaction completes wider equilibrium without losing water")
 result=await solve(water)
 check(result.get("ok",false) and result.get("cells",0)>=144000,"Ordinary connected lake exceeds the former cell cutoff within its reservation: "+str(result))
 check(result.get("reserved_bytes",0)==256*1024*1024 and water.statistics().water_ml==total,"Larger finite lake retains the same memory reservation and every millilitre")
 # A large snapshot is captured across frames; edits during capture must
 # restart it before a worker can publish stale quantities.
 water.settle_after_edit(AABB(Vector3(41,41.5,41),Vector3.ONE*.1))
 check(water.begin_equilibrium(1)==null,"Budgeted preparation yields before copying a whole connected lake")
 check(water.brush(Vector3(41.75,41.75,41.75),0,-1)==1,"Concurrent capture edit removes one owned millilitre")
 var job:RefCounted=null;var slices:=0
 while job==null and slices<10000:
  job=water.begin_equilibrium(50);slices+=1
 check(job!=null and slices>1,"Snapshot capture resumes over bounded slices")
 if job!=null:
  var task:=WorkerThreadPool.add_task(job.prepare,false,"Budgeted capture regression")
  while not WorkerThreadPool.is_task_completed(task):await process_frame
  WorkerThreadPool.wait_for_task_completion(task)
  result=water.finish_equilibrium(job)
  check(result.get("ok",false) and water.statistics().water_ml==total-1,"Capture restarts on revision change and preserves the latest quantity: "+str(result)+" quantity="+str(water.statistics().water_ml))
 print("WATER_EQUILIBRIUM_SCOPE checks=",checks," failures=",failures);quit(failures)

# SPDX-License-Identifier: 0BSD
extends "res://tests/water_equilibrium.gd"
func _initialize()->void:run_scope.call_deferred()
func check_new_receiver_scope()->void:
 var shore:=Vector3i(87,83,83)
 var separate:=Vector3i(105,83,83)
 var water:=fixture({shore:[0,500,125000],separate:[0,500,125000],separate+Vector3i.DOWN:[0,500,0]})
 var pocket:=AABB(Vector3(separate)*.5,Vector3.ONE*.25)
 var untouched:PackedByteArray=water.capture_local_snapshot(pocket)
 check(untouched.size()>6000,"The disconnected pool has a stored regional payload")
 var total:int=water.statistics().water_ml
 water.settle_after_edit(AABB(Vector3(shore)*.5,Vector3(.75,.25,.25)))
 var receiver:=Vector3i(11,10,10)
 var requests:Array=water.next_requests(32,false)
 check(receiver in requests,"Shore excavation requests the previously absent receiver")
 check(water.begin_equilibrium(0,true)==null,"First response waits for the receiver occupancy")
 if receiver not in requests:return
 # A sealed new region exercises the membership of the enlarged donor window.
 # The neighbouring pool could drain vertically if it were independently woken.
 var patch=ClassDB.instantiate("NativeWaterTerrainPatch");patch.configure(receiver)
 var terrain=preload("res://tests/water_publication_scale.gd").SolidTerrain.new()
 while patch.sample_terrain(terrain,729,0,0)==0:pass
 check(water.accept_patch(patch),"Receiver accepts sampled terrain")
 var job:RefCounted=water.begin_equilibrium(0,true)
 check(job!=null,"Sampled receiver admits the local response")
 if job==null:return
 job.prepare()
 var result:Dictionary=water.finish_equilibrium(job)
 check(result.get("snapshot_regions",0)==3,"The local snapshot includes the receiver, shore and disconnected candidate")
 check(result.get("ok",false) and water.statistics().water_ml==total,"First response conserves the complete finite quantity")
 check(water.capture_local_snapshot(pocket)==untouched,"A disconnected pool in the donor window remains byte-identical")
func check_sparse_mesh_owners()->void:
 var region:=Vector3i(10,10,10)
 var cells:Dictionary={}
 for z in range(-1,2):
  for x in range(-1,2):
   cells[(region+Vector3i(x,0,z))*8+Vector3i(3,3,3)]=[500,500,0]
 for offset in [1,6]:
  var high:=region*8+Vector3i(offset,3,offset)
  cells[high]=[0,500,125001]
  cells[high+Vector3i.DOWN]=[0,500,0]
 var water:=fixture(cells)
 while not water.next_mesh().is_empty():pass
 var result:=await solve(water)
 check(result.get("ok",false) and water.statistics().water_ml==250002,"Two diagonal pools settle in one region with conserved volume")
 var owners:Array=[]
 while true:
  var mesh:Dictionary=water.next_mesh()
  if mesh.is_empty():break
  owners.append(mesh.coordinate-region)
 var expected:=[Vector3i.ZERO,Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK,Vector3i(-1,0,-1),Vector3i(1,0,1)]
 check(owners.size()==expected.size() and expected.all(func(p):return owners.has(p)),"Sparse edits queue exactly the seven overlapping mesh owners: "+str(owners))
func check_connected_displacement()->void:
 var cells:Dictionary={}
 var donors:Array[Vector3i]=[]
 for x in range(82,86):
  var donor:=Vector3i(x,83,83)
  donors.append(donor)
  cells[donor]=[500,500,50000]
  cells[donor+Vector3i.UP]=[0,500,0]
 var pocket:=Vector3i(81,85,81)
 cells[pocket]=[500,500,123]
 var water:=fixture(cells)
 water.settle_after_edit(AABB(Vector3(41.5,41.5,41.5),Vector3.ONE*.1))
 var job:RefCounted=water.begin_equilibrium(0,true)
 check(job!=null,"Wet deposition admits local displacement")
 if job==null:return
 job.prepare()
 var result:Dictionary=water.finish_equilibrium(job)
 var retained:=amounts(water)
 check(result.get("ok",false) and result.get("displacement_searches",0)==2,
  "Four communicating displaced donors share one search and the sealed pocket gets its own")
 check(retained.get(pocket,0)==123 and water.total_water_ml()==200123,
  "Unreachable excess stays in its own pocket")
 for p in donors:
  check(not retained.has(p) and retained.get(p+Vector3i.UP,0)==50000,
   "Connected receivers contain the displaced volume at a common level")

func connected_bank_edit(region_count:int,deposit:bool)->Dictionary:
 var bank:=Vector3i(83,83,83)
 var cells:Dictionary={}
 for x in range(bank.x+1,80+8*region_count):
  cells[Vector3i(x,bank.y,bank.z)]=[0,500,62500]
 # The same occupancy and pre-edit quantity a terrain patch hands the solver.
 cells[bank]=[500,500,62500] if deposit else [0,500,0]
 var water:=fixture(cells)
 var quantity:int=water.total_water_ml()
 water.settle_after_edit(AABB(Vector3(bank)*.5,Vector3.ONE*.25))
 var job:RefCounted=water.begin_equilibrium(0,true)
 check(job!=null,"Resident connected bank admits an edit")
 if job==null:return {}
 job.prepare()
 var result:Dictionary=water.finish_equilibrium(job)
 var quantities:=amounts(water)
 var bank_ml:int=quantities.get(bank,0)
 check(result.get("ok",false) and quantity==water.total_water_ml(),"Connected bank conserves its entire finite volume")
 check(bank_ml==0 if deposit else bank_ml>0,"The edited bank reflects its new occupancy")
 check(quantities.get(Vector3i(79+8*region_count,83,83),0)==62500,"The distant end remains unchanged on first commit")
 return {"snapshot_regions":result.get("snapshot_regions",-1),"cells":result.get("cells",-1),"visits":result.get("displacement_visits",-1),"bank_ml":bank_ml}

func run_scope()->void:
 for deposit:bool in [false,true]:
  var small:=connected_bank_edit(16,deposit)
  var large:=connected_bank_edit(128,deposit)
  check(not small.is_empty() and small==large,"Eightfold lake length gives the same local work and bank quantity (deposit=%s): %s / %s"%[deposit,small,large])
 check_connected_displacement()
 # The cut connects nine cells across a region boundary. The fixture's
 # surrounding terrain is solid, including the neighbour past either end.
 var bank:Dictionary={}
 for x in range(81,90):
  bank[Vector3i(x,83,83)]=[0,500,90000 if x==84 else 0]
 var basin:=fixture(bank)
 basin.settle_after_edit(AABB(Vector3(42,41.5,41.5),Vector3(3,.5,.5)))
 var basin_job:RefCounted=basin.begin_equilibrium(0,true)
 check(basin_job!=null,"A resident enclosed bank edit starts a local transaction")
 if basin_job!=null:
  basin_job.prepare()
  var commit:Dictionary=basin.finish_equilibrium(basin_job)
  var levels:=amounts(basin)
  check(commit.get("ok",false) and bank.keys().all(func(p):return levels.get(p,0)==10000),
   "First local commit puts 90000 ml at one level across the enclosed bank cut")
 await check_sparse_mesh_owners()
 check_new_receiver_scope()
 var cells:Dictionary={}
 for z in 64:
  for x in 64:cells[Vector3i(11+x*24,83,11+z*24)]=[0,500,125000]
 var donor:=Vector3i(11,83,11);var receiver:=donor-Vector3i.UP
 cells[receiver]=[0,500,0]
 var water:=fixture(cells)
 var total:int=water.statistics().water_ml
 water.settle_after_edit(AABB(Vector3(donor)*.5,Vector3.ONE*.5))
 var first_response:RefCounted=water.begin_equilibrium(0,true)
 check(first_response!=null,"Resident edit admits a first response among 4,096 pools")
 if first_response!=null:
  first_response.prepare()
  var immediate:Dictionary=water.finish_equilibrium(first_response)
  check(immediate.get("ok",false) and immediate.get("snapshot_regions",4096)<16,"First response stays in the edited neighbourhood")
  check(water.statistics().water_ml==total and water.runtime_state().settling_regions>0,"First response conserves water and retains future relaxation")
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

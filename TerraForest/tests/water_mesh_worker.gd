# SPDX-License-Identifier: 0BSD
extends "res://tests/water_material_surface.gd"

func _initialize():call_deferred("run_worker_checks")
func publication_fixture():
 # Publication is tested with a resolved body. Thin-film representation has
 # separate coverage and must not turn this into an empty-mesh comparison.
 var water=fixture(3,0,true)
 water.brush(Vector3(41.75,41.501,41.75),0.0,99000)
 return water

func grouped_fixture(count:int=9,edited:bool=false):
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+count*6160);bytes.fill(0)
 bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,1);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,count);bytes.encode_u64(16,count*100000)
 for i in catalog.size():bytes[32+i]=catalog[i]
 for n in count:
  var base:int=32+catalog.size()+n*6160
  bytes.encode_u64(base,((10+n)<<24)|(10<<12)|10);bytes.encode_u32(base+8,1);base+=16
  for i in 512:bytes.encode_u16(base+i*12+2,500)
  bytes.encode_u64(base+(3+8*3+64*3)*12+4,100000)
 var water=ClassDB.instantiate("NativeRegionalWater")
 if not water.restore_snapshot(bytes):return null
 if edited:
  for n in count:
   var p:=Vector3((10+n)*4+1.75,41.75,41.75)
   if water.brush(p,0,-1000)!=1000:return null
 return water
func check_grouped_owners(dispatch_indexed:=false,edited:=false,stream_indexed:=false)->void:
 var count:=70 if edited else 9
 var reference=grouped_fixture(count,edited);var expected:Dictionary={}
 if reference==null:check(false,"Grouped mesh fixture accepts all edits");return
 for n in 100:
  var packet:Dictionary=reference.next_mesh_batch(false,true) if stream_indexed else reference.next_mesh()
  if packet.is_empty():break
  if packet.has("coordinate"):expected[packet.coordinate]=packet.arrays
  if stream_indexed and packet.complete:reference.commit_mesh_batch(packet.batch)
 var water=grouped_fixture(count,edited);var actual:Dictionary={};var jobs:=0;var committed:=false
 for n in 100:
  var packet:Dictionary=water.next_mesh_batch(true,stream_indexed or (dispatch_indexed and jobs==0))
  if packet.is_empty():break
  if packet.has("job"):
   jobs+=1
   var task:=WorkerThreadPool.add_task(packet.job.prepare,false,"Parallel owner regression")
   while not WorkerThreadPool.is_task_completed(task):
    if stream_indexed:
     var partial:Dictionary=water.next_mesh_batch(true,true,true)
     if partial.has("coordinate"):
      check(not actual.has(partial.coordinate) and not partial.complete,"An early owner appears once before commit")
      actual[partial.coordinate]=partial.arrays
    await process_frame
   WorkerThreadPool.wait_for_task_completion(task);continue
  if packet.has("coordinate"):actual[packet.coordinate]=packet.arrays
  if packet.complete:committed=water.commit_mesh_batch(packet.batch);break
 print("GROUPED_OWNERS jobs=",jobs," committed=",committed," expected=",expected.size()," actual=",actual.size()," equal=",actual==expected)
 check(jobs==1 and committed and expected.size()==count and actual==expected,"Parallel owner group exactly matches serial geometry in stable owner order")
 check(water.statistics().mesh_worker_reserved_bytes==0,"Parallel owner group releases its shared memory reservation")
func run_worker_checks() -> void:
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--water-mesh-replay="):
   replay_meshes(arg.trim_prefix("--water-mesh-replay="));return
 var dry=fixture(3,0,false,Vector3i(10,10,10),3,0)
 var dry_commit:=false;var dry_jobs:=0
 for step in 100:
  var packet:Dictionary=dry.next_mesh_batch(true)
  if packet.is_empty():break
  if packet.has("job"):dry_jobs+=1;packet.job.prepare()
  if packet.complete:dry_commit=dry.commit_mesh_batch(packet.batch)
 check(dry_commit and dry_jobs==0,"Dry resident occupancy publishes without dispatching a boundary worker")
 var dry_point:=Vector3(41.75,41.51,41.75)
 check(dry.brush(dry_point,0.0,100000)==100000,"A previously dry owner accepts water")
 for step in 100:
  var packet:Dictionary=dry.next_mesh_batch(true)
  if packet.is_empty():break
  if packet.has("job"):packet.job.prepare()
  if packet.complete:dry.commit_mesh_batch(packet.batch)
 check(dry.raycast_surface(dry_point+Vector3.UP,dry_point-Vector3.UP).hit,"The newly wet owner publishes its pickable surface")
 await check_grouped_owners()
 await check_grouped_owners(true)
 await check_grouped_owners(false,true)
 await check_grouped_owners(true,true,true)
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
   var old_mesh:=MeshInstance3D.new();var new_mesh:=MeshInstance3D.new()
   root.add_child(old_mesh);root.add_child(new_mesh);new_mesh.visible=false
   check(not water.commit_mesh_batch(packet.batch+1,[old_mesh],[new_mesh]) and old_mesh.visible and not new_mesh.visible,"Rejected publication preserves both visible generations")
   published=water.commit_mesh_batch(packet.batch,[old_mesh],[new_mesh])
   check(not old_mesh.visible and new_mesh.visible,"Query commit atomically replaces the visible mesh generation")
   old_mesh.free();new_mesh.free()
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
 # A current cache includes a vacancy-count word even when there are no holes.
 if saved.decode_u32(4)<9:
  saved.resize(saved.size()+4);saved.encode_u32(saved.size()-4,0);saved.encode_u64(24,saved.decode_u64(24)+4)
 saved.encode_u32(4,13)
 # Upgrade the legacy test fixture with an explicit valid air density cache.
 var base:int=32+saved.decode_u32(8);saved.encode_u32(base+12,1)
 for i in 729:saved.encode_float(base+6160+i*4,1.0)
 var coordinator=load("res://addons/volumetric_water/lake_world.gd").new();coordinator.prepare()
 check(coordinator.restore_snapshot(saved) and coordinator.water.statistics().pending_regions==0,"Current 3D occupancy cache restores without resampling")
 saved.encode_u32(4,12)
 check(coordinator.restore_snapshot(saved) and coordinator.water.statistics().pending_regions>0 and coordinator.water.statistics().water_ml==current.statistics().water_ml,"Old occupancy cache migrates through terrain sampling without changing water quantity")
 coordinator.free()
 print("WATER_MESH_WORKER failures=",failures," jobs=",jobs)
 quit(1 if failures else 0)

# Replay the same resident crater snapshot for before/after native comparisons.
# Hashing and restoration are outside the measured boundary assembly time.
func replay_meshes(path:String)->void:
 var file:=FileAccess.open(path,FileAccess.READ)
 if file==null:check(false,"Captured local water file opens");quit(1);return
 var capture:Dictionary=file.get_var()
 var packet_bytes:PackedByteArray=capture.snapshot
 var expected:=""
 var indexed_only:="--water-indexed-only" in OS.get_cmdline_user_args()
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--water-expected-geometry-sha256="):expected=arg.trim_prefix("--water-expected-geometry-sha256=").to_lower()
 for iteration in 4:
  var store=ClassDB.instantiate("NativeRegionalWater")
  if not store.restore_snapshot(packet_bytes):check(false,"Local water snapshot restores");quit(1);return
  var owners:Dictionary={};var mesh_us:=0;var jobs:=0;var expanded_bytes:=0
  for step in 10000:
   var begin:=Time.get_ticks_usec()
   var packet:Dictionary=store.next_mesh_batch(true,true) if indexed_only else store.next_mesh_batch(true)
   if packet.is_empty():break
   if packet.has("failure"):check(false,str(packet.failure));quit(1);return
   if packet.has("job"):jobs+=1;packet.job.prepare()
   if packet.complete and not store.commit_mesh_batch(packet.batch):
    check(false,"Local water publication commits");quit(1);return
   mesh_us+=Time.get_ticks_usec()-begin
   if packet.has("coordinate"):
    if not indexed_only:
     for slot in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_COLOR]:
      expanded_bytes+=packet.arrays[slot].to_byte_array().size()
    var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
    hash.update(var_to_bytes(packet.render_arrays))
    owners[packet.coordinate]=hash.finish()
  var coordinates:=owners.keys();coordinates.sort()
  var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256)
  for coordinate:Vector3i in coordinates:
   digest.update(var_to_bytes(coordinate));digest.update(owners[coordinate])
  var identity:=digest.finish().hex_encode()
  if expected.is_empty():expected=identity
  check(identity==expected and not owners.is_empty() and store.runtime_state().dirty_meshes==0,"Local replay produces all surface owners deterministically")
  print("WATER_MESH_REPLAY ",JSON.stringify({"iteration":iteration,"jobs":jobs,"owners":owners.size(),"native_us":mesh_us,"expanded_bytes":expanded_bytes,"geometry_sha256":identity,"source_sha256":FileAccess.get_sha256(path)}))
 print("WATER_MESH_REPLAY failures=",failures);quit(failures)

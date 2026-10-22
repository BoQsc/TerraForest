# SPDX-License-Identifier: 0BSD
extends Node3D
const PublicationBudget=preload("res://addons/volumetric_water/publication_budget.gd")
# Native static storage/meshing. Script only coordinates worker hand-off, scene and UI.
signal cached_preparation_profiled(worker_ms:float,queue_ms:float,status:int)
signal bucket_completed(slot:int)
signal interaction_finished(message:String)
signal catalog_changed
signal lake_ready(id:int)
signal lake_failed(id:int,status:int)
signal exclusion_changed(bounds:AABB)
@export var terrain:Node3D
var blocks:Node3D
var _structure_revision:=0
var _builder_structure_revision:=-1
@export_range(1,16) var max_lakes:int=16
var _lakes:Dictionary={}
var _next_id:=1
var _catalog:RefCounted
var water:RefCounted
var _builder_patches:Array=[]
var _builder:RefCounted
var _busy:=false
var _occupancy_failure:String=""
var last_restore_profile:Dictionary={}
var _retirement_jobs:Array[Dictionary]=[]
var _cached_task:int=-1
var _cached_job:Dictionary={}
var _builder_reused:=false
var _revision:=-1
var _token:=0
var _epoch:=-1
# Offline preparation publishes completed generated fills, not each frontier.
var offline_preparation:=false
var _filling_id:=0
var _meshes:Dictionary={}
var _staged_meshes:Dictionary={}
var _mesh_batch_id:int=0
var _published_mesh_batch_id:int=0
var _exclusion_notify_us:int=0
var _accept_patch_us:int=0
var _hull_snapshot_us:int=0
var _mesh_publish_us:int=0
var _mesh_max_publish_us:int=0
var _mesh_commit_us:int=0
var _mesh_max_commit_us:int=0
var _mesh_faces:Dictionary={}
var _ocean_horizon:MeshInstance3D
var _surrounding_ocean:Node3D
var _ocean_admitting:=false
var _material:=ShaderMaterial.new()
var _pending_bucket:Dictionary={}
var _bucket_native_us:=0
var _max_bucket_native_us:=0
var _pending_dev:Dictionary={}
var _last_changes:=0
var _notify_seconds:=0.0
var _changed_bounds:=AABB()
var _have_bounds:=false
var _capacity_reported:=false
func prepare() -> bool:
 if not ClassDB.class_exists("NativeRegionalWater"):GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 if not ClassDB.class_exists("NativeRegionalWater"):return false
 if _catalog==null:_catalog=ClassDB.instantiate("NativeLakeCatalog")
 if water==null:water=ClassDB.instantiate("NativeRegionalWater")
 return true
func snapshot_validator() -> RefCounted:return water
func empty_snapshot() -> PackedByteArray:
 var empty=ClassDB.instantiate("NativeRegionalWater")
 return empty.capture_snapshot(_catalog.encode([]))
func capture_snapshot() -> PackedByteArray:
 return _capture(false)
func capture_storage_snapshot() -> Variant:
 return _capture(true)
func _capture(deferred:bool) -> Variant:
 # Do not silently save a partially authored/generated lake as a completed one.
 for item:Dictionary in _lakes.values():
  if item.dirty:return PackedByteArray()
 var records:Array=[]
 for item:Dictionary in _lakes.values():records.append({"id":item.id,"origin":item.origin,"cells":item.cells,"spacing":item.spacing,"level":item.level,"seed":item.seed})
 var catalog:PackedByteArray=_catalog.encode(records,_next_id)
 return water.capture_storage_snapshot(catalog) if deferred else water.capture_snapshot(catalog)
func snapshot_preparer()->RefCounted:
 return ClassDB.instantiate("NativeWaterMapIdentity")
func restore_prepared_snapshot(prepared:RefCounted)->bool:
 var restored:=restore_snapshot(prepared.get_bytes(),prepared)
 if restored:
  # Keep the handoff alive until the pool has destroyed its retired native store.
  _retirement_jobs.append({"state":prepared,"task":WorkerThreadPool.add_task(prepared.retire,false,"Retire loaded water state")})
 return restored
func restore_snapshot(bytes:PackedByteArray,prepared:RefCounted=null) -> bool:
 var catalog_bytes:PackedByteArray=prepared.get_catalog() if prepared!=null else water.snapshot_catalog(bytes)
 if catalog_bytes.is_empty():return false
 var decoded:Dictionary=_catalog.decode(catalog_bytes)
 if not decoded.ok:return false
 var restore_begin:=Time.get_ticks_usec()
 clear(prepared!=null);_next_id=decoded.next_id
 last_restore_profile={"scene_clear_us":Time.get_ticks_usec()-restore_begin}
 restore_begin=Time.get_ticks_usec()
 var cached:bool=bytes.decode_u32(0)==0x31575256
 if cached:
  if not (water.restore_prepared(prepared) if prepared!=null else water.restore_snapshot(bytes)):return false
 last_restore_profile["native_install_us"]=Time.get_ticks_usec()-restore_begin
 # Old saves retain quantities but rebuild contacts to include explicit terrain cubes.
 if cached and bytes.decode_u32(4)<8:water.invalidate(AABB(Vector3.ZERO,Vector3(2000,256,2000)),true)
 for record:Dictionary in decoded.records:
  record.dirty=not cached;record.failure=""
  var state:PackedByteArray=record.get("water_state",PackedByteArray())
  record.amount=-1 if state.is_empty() else int(state.decode_u64(16))
  _lakes[record.id]=record
 catalog_changed.emit();return true
func _ready() -> void:
 if terrain==null or not prepare():set_process(false);return
 _material.shader=preload("res://addons/volumetric_water/water.gdshader")
 _material.set_shader_parameter("ripple_normal",preload("res://addons/volumetric_water/textures/water_ripples_normal.png"))
 terrain.lake_slice_ready.connect(_slice_ready);terrain.region_invalidated.connect(_invalidate)
 terrain.water_edit_admission=func(bounds:AABB,_selected:Array)->bool:return not water.has_deferred_overlap(bounds.grow(0.5))
 terrain.solid_deposited.connect(func(bounds:AABB):water.invalidate(bounds,true))
 # Mining is admitted normally. Invalid regions retain their water and wait for
 # the committed terrain worker samples; they never flow against stale solids.
 # Accepted terrain occupancy patches remove water replaced by solid terrain.
 if blocks!=null:
  blocks.cells_changed.connect(func(bounds:AABB):water.invalidate_buildings(blocks.global_transform*bounds);_occupancy_failure="";_discard_builder())
  blocks.changed.connect(func():_structure_revision+=1)
 _epoch=terrain.epoch
func add_lake(origin:Vector3,cells:Vector3i,spacing:float,level:float,seed:Vector3) -> int:
 if _lakes.size()>=max_lakes:return 0
 var record:Dictionary={"id":_next_id,"origin":origin,"cells":cells,"spacing":spacing,"level":level,"seed":seed}
 if _catalog.encode([record]).is_empty():return 0
 record.dirty=true;record.failure="";record.amount=-1
 _lakes[_next_id]=record;_next_id+=1;catalog_changed.emit();return record.id
func remove_lake(id:int) -> void:
 if not _lakes.has(id) or _filling_id!=0:return
 var item:Dictionary=_lakes[id]
 water.remove_bounds(AABB(item.origin,Vector3(item.cells)*item.spacing))
 _lakes.erase(id);terrain.changed_since_save=true;catalog_changed.emit()
func clear(preserve_store:bool=false) -> void:
 _ocean_admitting=false
 _occupancy_failure=""
 _lakes.clear();_filling_id=0;_pending_bucket.clear();_pending_dev.clear()
 for mesh:MeshInstance3D in _meshes.values():mesh.queue_free()
 _meshes.clear();_mesh_faces.clear();_staged_meshes.clear();_mesh_batch_id=0;_published_mesh_batch_id=0
 if not preserve_store:water=ClassDB.instantiate("NativeRegionalWater")
 if _surrounding_ocean!=null:
  var empty:=PackedByteArray();empty.resize(500*500);empty.fill(0);_surrounding_ocean.publish(empty)
 _discard_builder()
 _have_bounds=false;_last_changes=0
func _invalidate(bounds:AABB) -> void:
 _occupancy_failure=""
 water.invalidate(bounds)
 _discard_builder()
var last_process_us:int=0
func _process(delta:float) -> void:
 var measured_begin:=Time.get_ticks_usec()
 _measured_step(delta)
 last_process_us=Time.get_ticks_usec()-measured_begin

func _measured_step(delta:float)->void:
 for i in range(_retirement_jobs.size()-1,-1,-1):
  if WorkerThreadPool.is_task_completed(_retirement_jobs[i].task):
   WorkerThreadPool.wait_for_task_completion(_retirement_jobs[i].task);_retirement_jobs.remove_at(i)
 _poll_cached_task()
 if terrain==null or not terrain.world_ready:return
 water.set_western_ocean(terrain.backend.world_generator==18)
 water.set_surrounding_ocean(terrain.backend.world_generator==19)
 if terrain.backend.world_generator==19 and _surrounding_ocean==null:
  _surrounding_ocean=preload("res://addons/volumetric_water/ocean_presentation.gd").new()
  add_child(_surrounding_ocean);_surrounding_ocean.setup(_material)
 elif terrain.backend.world_generator!=19 and _surrounding_ocean!=null:
  _surrounding_ocean.queue_free();_surrounding_ocean=null;_material.set_shader_parameter("surrounding_ocean",false)
 if _surrounding_ocean==null or not _pending_bucket.is_empty() or not _pending_dev.is_empty():_ocean_admitting=false
 if _surrounding_ocean!=null and not _busy and _builder==null and not terrain.pending_edit and _pending_bucket.is_empty() and _pending_dev.is_empty():
  var residency:Dictionary=water.update_ocean_residency(terrain.focus,16)
  _ocean_admitting=int(residency.get("admitted",0))>0

 if terrain.backend.world_generator==18 and _ocean_horizon==null:
  _material.set_shader_parameter("coastal_join",true)
  _ocean_horizon=preload("res://addons/volumetric_water/coastal_inlet.gd").horizon(_material);add_child(_ocean_horizon)
 elif terrain.backend.world_generator!=18 and _ocean_horizon!=null:
  _ocean_horizon.queue_free();_ocean_horizon=null
  _material.set_shader_parameter("coastal_join",false)
 if _epoch!=terrain.epoch:_epoch=terrain.epoch;_occupancy_failure="";_discard_builder()
 var before:Dictionary=water.statistics()
 if _filling_id!=0 and not before.fill_active:
  var id:=_filling_id;_filling_id=0
  if _lakes.has(id):_lakes[id].dirty=false;lake_ready.emit(id);catalog_changed.emit()
 if _filling_id==0:
  for item:Dictionary in _lakes.values():
   if not item.dirty:continue
   if water.begin_fill(AABB(item.origin,Vector3(item.cells)*item.spacing),item.level,item.seed,item.amount):_filling_id=item.id
   else:item.dirty=false;item.failure="Water authoring bounds unavailable";lake_failed.emit(item.id,-2);catalog_changed.emit()
   break
 # Show edits before advancing their flow. Native immutable batches retain
 # that state if publication spans more than one frame.
 if (not offline_preparation or _filling_id==0) and not _ocean_admitting:_publish_meshes()
 # Explicit lake creation only. Resting or edited water has no flow tick.
 if _filling_id!=0:water.advance(2048,delta)
 if not _busy and not terrain.pending_edit and _occupancy_failure.is_empty():
  var request:Dictionary=water.next_request()
  if not request.is_empty():
   if (_builder==null or _revision!=terrain.published_revision) and _surrounding_ocean!=null and _pending_bucket.is_empty() and _pending_dev.is_empty():
    _prepare_ocean_batch()
   if _builder==null or _revision!=terrain.published_revision:
    _builder=ClassDB.instantiate("NativeWaterTerrainPatch");_builder.configure(request.coordinate);_builder_reused=false;_revision=terrain.published_revision
    _builder_structure_revision=_structure_revision
    if blocks!=null:
     var hull_started:=Time.get_ticks_usec()
     var solids:Dictionary=blocks.solid_hulls(AABB(Vector3(request.coordinate)*4,Vector3(4,4,4)))
     if not solids.ok or not _builder.set_structure_hulls(solids.hulls):_discard_builder()
     if _builder!=null:_builder_reused=water.reuse_building_occupancy(_builder)
     _hull_snapshot_us=Time.get_ticks_usec()-hull_started
   if _builder!=null:
    _token=_builder.get_instance_id()
    if _builder_reused:
     _cached_job={"builder":_builder,"token":_token,"epoch":terrain.epoch,"revision":_revision,"submitted_us":Time.get_ticks_usec()}
     _cached_task=WorkerThreadPool.add_task(_builder.prepare_cached,false,"Water cached building occupancy")
     if _cached_task>=0:_busy=true
     else:
      _cached_job={}
      if terrain.request_lake_slice(_builder,_token):_busy=true
    elif terrain.request_lake_slice(_builder,_token):_busy=true
 if not _pending_bucket.is_empty():
  var p:=_pending_bucket
  # Expiration is a precondition: never execute a stale click first and
  # discover afterwards that its loading deadline already passed.
  var result:Dictionary={"ok":false,"pending":false,"reason":"Water action timed out; bucket unchanged. Try again."} if Time.get_ticks_msec()>p.deadline else _transfer_bucket(p.from,p.to,p.pour,p.inventory,p.slot,p.revision)
  if result.ok or not result.pending or Time.get_ticks_msec()>p.deadline:
   _pending_bucket={}
   if result.pending:result.reason="Water action timed out; bucket unchanged. Try again."
   if result.ok:terrain.changed_since_save=true;bucket_completed.emit(p.slot)
   terrain.message_changed.emit(result.reason)
   interaction_finished.emit(result.reason)
 if not _pending_dev.is_empty():
  var p:=_pending_dev
  var result:Dictionary={"ok":false,"pending":false,"reason":"Water placement timed out; no water placed. Try again."} if Time.get_ticks_msec()>p.deadline else water.place_water(p.point,p.amount)
  if result.ok or not result.pending or Time.get_ticks_msec()>p.deadline:
   _pending_dev={}
   if result.pending:result.reason="Water placement timed out; no water placed. Try again."
   if result.ok:terrain.changed_since_save=true
   terrain.message_changed.emit(result.reason)
   interaction_finished.emit(result.reason)
 var after:Dictionary=water.statistics()
 if after.capacity_reached and not _capacity_reported:
  _capacity_reported=true;terrain.message_changed.emit("Water resident-region limit reached; quantities retained, expansion paused")
 if after.changes!=_last_changes:terrain.changed_since_save=true;_last_changes=after.changes
 _notify_seconds+=delta
 if _have_bounds and _notify_seconds>=0.25:
  _notify_seconds=0;_have_bounds=false
  var notify_started:=Time.get_ticks_usec()
  exclusion_changed.emit(_changed_bounds)
  _exclusion_notify_us=Time.get_ticks_usec()-notify_started
func _publish_meshes() -> void:
 # Build/upload within the existing soft budget; only a complete immutable
 # batch becomes visible. Flow may advance between calls without mixed edges.
 var mesh_started:=Time.get_ticks_usec()
 for publication in PublicationBudget.MAX_PACKETS:
  var update:Dictionary=water.next_mesh_batch()
  if update.is_empty():break
  if update.batch!=_mesh_batch_id:
   _staged_meshes.clear();_mesh_batch_id=update.batch
  if update.has("coordinate"):
   var geometry:ArrayMesh=null
   if update.vertices>0:
    geometry=ArrayMesh.new();geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,update.arrays)
   _staged_meshes[update.coordinate]={"mesh":geometry,"faces":update.faces}
  if update.complete:
   var commit_started:=Time.get_ticks_usec()
   for coordinate:Vector3i in _staged_meshes:
    var staged:Dictionary=_staged_meshes[coordinate]
    if staged.mesh==null:
     if _meshes.has(coordinate):_meshes[coordinate].queue_free();_meshes.erase(coordinate)
     _mesh_faces.erase(coordinate)
    else:
     if not _meshes.has(coordinate):
      var node:=MeshInstance3D.new();node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.material_override=_material;add_child(node);_meshes[coordinate]=node
     _mesh_faces[coordinate]=staged.faces
     _meshes[coordinate].mesh=staged.mesh
    var bounds:=AABB(Vector3(coordinate)*4,Vector3(4,4,4))
    _changed_bounds=_changed_bounds.merge(bounds) if _have_bounds else bounds;_have_bounds=true
   if not water.commit_mesh_batch(update.batch):push_error("Water query publication did not match rendered batch")
   _published_mesh_batch_id=update.batch
   if _surrounding_ocean!=null:_surrounding_ocean.publish(water.ocean_publication_mask())
   _staged_meshes.clear()
   _mesh_commit_us=Time.get_ticks_usec()-commit_started;_mesh_max_commit_us=maxi(_mesh_max_commit_us,_mesh_commit_us)
  if Time.get_ticks_usec()-mesh_started>=PublicationBudget.SOFT_TIME_US:break
 _mesh_publish_us=Time.get_ticks_usec()-mesh_started;_mesh_max_publish_us=maxi(_mesh_max_publish_us,_mesh_publish_us)
func _prepare_ocean_batch() -> void:
 _discard_builder()
 _builder_reused=false
 _revision=terrain.published_revision
 _builder_structure_revision=_structure_revision
 var hull_started:=Time.get_ticks_usec()
 for coordinate:Vector3i in water.next_requests(8):
  var patch:RefCounted=ClassDB.instantiate("NativeWaterTerrainPatch")
  if not patch.configure(coordinate):_discard_builder();return
  if blocks!=null:
   var solids:Dictionary=blocks.solid_hulls(AABB(Vector3(coordinate)*4,Vector3(4,4,4)))
   if not solids.ok or not patch.set_structure_hulls(solids.hulls):_discard_builder();return
  _builder_patches.append(patch)
 _hull_snapshot_us=Time.get_ticks_usec()-hull_started
 var batch:RefCounted=ClassDB.instantiate("NativeWaterTerrainBatch")
 if batch.configure(_builder_patches):_builder=batch
 else:_discard_builder()
func _discard_builder() -> void:
 if not _cached_job.is_empty():_cached_job.builder.cancel_cached()
 _builder=null
 _builder_patches.clear()
func _poll_cached_task() -> void:
 if _cached_task<0 or not WorkerThreadPool.is_task_completed(_cached_task):return
 WorkerThreadPool.wait_for_task_completion(_cached_task)
 var job:=_cached_job;var info:Dictionary=job.builder.statistics()
 _cached_task=-1;_cached_job={}
 cached_preparation_profiled.emit(info.cached_worker_us/1000.0,maxi(0,info.cached_started_us-job.submitted_us)/1000.0,info.status)
 _slice_ready(job.token,info.status,job.epoch,job.revision)
func _exit_tree() -> void:
 for job:Dictionary in _retirement_jobs:WorkerThreadPool.wait_for_task_completion(job.task)
 _retirement_jobs.clear()
 if _cached_task>=0:
  _cached_job.builder.cancel_cached()
  WorkerThreadPool.wait_for_task_completion(_cached_task)
  _cached_task=-1;_cached_job={}
func _slice_ready(token:int,status:int,epoch_id:int,revision:int) -> void:
 if token!=_token:return
 _busy=false
 if _builder==null or _builder_structure_revision!=_structure_revision or epoch_id!=terrain.epoch or revision!=terrain.published_revision or terrain.pending_edit or status==-4:_discard_builder();return
 if status==0:return
 if status==1:
  var accept_started:=Time.get_ticks_usec()
  var patches:Array=_builder_patches if not _builder_patches.is_empty() else [_builder]
  for patch:RefCounted in patches:
   if not water.accept_patch(patch):
    _occupancy_failure="Water occupancy cache budget reached; edit remains pending until the world changes"
    break
  _accept_patch_us=Time.get_ticks_usec()-accept_started
 else:_occupancy_failure="Water occupancy preparation failed; edit remains pending until the world changes"
 if not _occupancy_failure.is_empty():terrain.message_changed.emit(_occupancy_failure)
 _discard_builder()
func _transfer_bucket(from:Vector3,to:Vector3,pour:bool,inventory:RefCounted,slot:int,revision:int)->Dictionary:
 var started:=Time.get_ticks_usec()
 var result:Dictionary=water.transfer_bucket(from,to,pour,inventory,slot,revision)
 _bucket_native_us=Time.get_ticks_usec()-started
 _max_bucket_native_us=maxi(_max_bucket_native_us,_bucket_native_us)
 return result
func bucket(from:Vector3,to:Vector3,pour:bool,inventory:RefCounted,slot:int,revision:int) -> Dictionary:
 # A new intent supersedes queued edits, even if this new target is rejected.
 _pending_bucket.clear();_pending_dev.clear()
 if not terrain.world_ready or terrain.pending_edit:return {"ok":false,"reason":"Wait for the terrain edit to finish"}
 var result:Dictionary=_transfer_bucket(from,to,pour,inventory,slot,revision)
 if result.pending:_pending_bucket={"from":from,"to":to,"pour":pour,"inventory":inventory,"slot":slot,"revision":revision,"deadline":Time.get_ticks_msec()+5000}
 if result.ok:terrain.changed_since_save=true
 return result
func dev_brush(point:Vector3,remove:bool,radius:float=2.0) -> Dictionary:
 # A new intent supersedes queued edits, even if this new target is rejected.
 _pending_bucket.clear();_pending_dev.clear()
 if not terrain.world_ready or terrain.pending_edit:return {"ok":false,"pending":false,"reason":"Wait for the terrain edit to finish"}
 if not point.is_finite():return {"ok":false,"pending":false,"reason":"Aim at a surface within 5 m"}
 if remove:
  var removed:int=water.brush(point,radius,-0x10000000000000)
  if removed>0:terrain.changed_since_save=true
  return {"ok":removed>0,"pending":false,"water_ml":removed,"reason":"Removed %.3f m³ of water"%(float(removed)/1000000.0) if removed>0 else "No water removed; the target is empty or water is preparing"}
 var result:Dictionary=water.place_water(point,1000000)
 if result.pending:_pending_dev={"point":point,"amount":1000000,"deadline":Time.get_ticks_msec()+5000}
 if result.ok:terrain.changed_since_save=true
 terrain.message_changed.emit(result.reason)
 return result
func placement_mask(transforms:Array[Transform3D]) -> PackedByteArray:return water.placement_mask(transforms)
func depth_at(point:Vector3) -> float:return water.depth_at(point)
func statistics() -> Dictionary:
 var s:Dictionary=water.statistics();s.lakes=_lakes.size();s.ready=0;s.outstanding_slices=int(_busy);s.resident_occupancy_bytes=s.resident_cell_bytes
 for item:Dictionary in _lakes.values():
  if not item.dirty and item.failure.is_empty():s.ready+=1
 s.occupancy_failure=_occupancy_failure
 s.bucket_native_us=_bucket_native_us;s.max_bucket_native_us=_max_bucket_native_us
 s.exclusion_notify_us=_exclusion_notify_us;s.accept_patch_us=_accept_patch_us;s.hull_snapshot_us=_hull_snapshot_us
 s.mesh_publish_us=_mesh_publish_us;s.max_mesh_publish_us=_mesh_max_publish_us
 s.mesh_commit_us=_mesh_commit_us;s.max_mesh_commit_us=_mesh_max_commit_us;s.staged_meshes=_staged_meshes.size()
 s.render_ready=_staged_meshes.is_empty() and s.dirty_meshes==0 and s.pending_regions==0 and not s.fill_active
 return s
func descriptions() -> Array[Dictionary]:
 var rows:Array[Dictionary]=[]
 for item:Dictionary in _lakes.values():rows.append({"id":item.id,"state":"Preparing" if item.dirty else "Ready" if item.failure.is_empty() else "Failed","reason":item.failure,"level":item.level,"origin":item.origin})
 return rows
func retry_lake(id:int) -> bool:
 if not _lakes.has(id) or _lakes[id].dirty:return false
 if _lakes[id].failure.is_empty():return false
 _lakes[id].dirty=true;_lakes[id].failure="";return true

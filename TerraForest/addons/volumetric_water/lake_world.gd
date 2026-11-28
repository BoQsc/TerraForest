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
var _surface_failure:String=""
var _mesh_task:int=-1
# Native method Callables identify an Object; a task ID does not retain it.
# Invalidation releases the store's reference, so the dispatcher owns the job
# until the worker has been joined, including cancelled batches and shutdown.
var _mesh_job:RefCounted
var _equilibrium_task:int=-1
var _equilibrium_job:RefCounted
var _local_response_pending:=false
var _local_publication_pending:=false
var _local_response_started_us:=0
var _local_response_us:=0
var _edit_equilibrium_jobs:=0
var _edit_dependency_rounds:=0
var _edit_dependency_regions:=0
var _edit_worker_us:=0
var _edit_capture_us:=0
var _slice_callbacks:=0
var _slice_last_status:=-99
var _slice_failure:Dictionary={}
var _equilibrium_last_result:Dictionary={}
var _equilibrium_failure:=""
var _ocean_exchange_ml:int=0
var _equilibrium_failed_revision:int=-1
var _equilibrium_retry_us:=0
var _equilibrium_phases:PackedInt64Array=PackedInt64Array()
var _equilibrium_worker_us:int=0
var _equilibrium_cells:int=0
var _equilibrium_commit_us:int=0
var _equilibrium_blocked_ml:int=0
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
var loading_active:Callable
var settling_active:Callable
var settling_enabled:Callable
var _filling_id:=0
var _render_pages=preload("res://addons/volumetric_water/water_render_pages.gd").new()
var _render_page_changes:Dictionary={}
var _meshes:Dictionary={}
var _staged_meshes:Dictionary={}
# Hidden superseded instances are destroyed under the normal frame budget.
var _retired_mesh_nodes:Array[MeshInstance3D]=[]
var _staged_bounds:=AABB()
var _have_staged_bounds:=false
var _residency_focus:=Vector2i(-9999,-9999)
var _residency_revision:=-1
var _residency_due:=0
var _mesh_commit_nodes_us:=0
var _mesh_commit_native_us:=0
var _mesh_commit_mask_us:=0
var _mesh_commit_count:=0
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
var _published_over_capacity_ml:=0
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
func _init()->void:
 _render_pages.name="WaterRenderPages";_render_pages.material=_material;add_child(_render_pages)
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
func _save_catalog()->PackedByteArray:
 var records:Array=[]
 for item:Dictionary in _lakes.values():records.append({"id":item.id,"origin":item.origin,"cells":item.cells,"spacing":item.spacing,"level":item.level,"seed":item.seed})
 return _catalog.encode(records,_next_id)
func capacity_usage()->Dictionary:
 if water==null or _catalog==null:return {}
 return water.capacity_usage(_save_catalog().size(),_catalog.encode([]).size())
func _capture(deferred:bool) -> Variant:
 # Do not silently save a partially authored/generated lake as a completed one.
 for item:Dictionary in _lakes.values():
  if item.dirty:print("WATER_CAPTURE_REJECTED unfinished_lake=",item.id);return PackedByteArray()
 var catalog:=_save_catalog()
 var captured:Variant=water.capture_storage_snapshot(catalog) if deferred else water.capture_streaming_snapshot(catalog)
 if captured is PackedByteArray and captured.is_empty():print("WATER_CAPTURE_REJECTED catalog_bytes=",catalog.size()," state=",JSON.stringify(water.statistics()))
 return captured
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
 # Configure the same world before installing its certified native snapshot.
 # Applying these flags on the first process tick would invalidate that identity.
 if terrain!=null:
  water.set_western_ocean(terrain.backend.world_generator==18)
  water.set_surrounding_ocean(terrain.backend.world_generator in [19,21,23,25,27,29,31,33,35,36,37,38])
 last_restore_profile={"scene_clear_us":Time.get_ticks_usec()-restore_begin}
 restore_begin=Time.get_ticks_usec()
 var cached:bool=bytes.decode_u32(0)==0x31575256
 if cached:
  if not (water.restore_prepared(prepared) if prepared!=null else water.restore_snapshot(bytes)):return false
 last_restore_profile["native_install_us"]=Time.get_ticks_usec()-restore_begin
 # Old saves retain quantities but rebuild full 3D terrain air contacts.
 if cached and bytes.decode_u32(4)<13:water.invalidate(AABB(Vector3.ZERO,Vector3(2000,256,2000)),true)
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
 terrain.edit_field_ready.connect(_field_ready)
 RenderingServer.frame_pre_draw.connect(_before_water_draw)
 terrain.edit_region_installed.connect(_terrain_region_installed)
 terrain.edit_geometry_installed.connect(_terrain_geometry_installed)
 terrain.region_changed.connect(_settle_committed_edit)
 terrain.water_edit_admission=func(bounds:AABB,_selected:Array)->int:
  if water.has_deferred_overlap(bounds.grow(0.5)):return ERR_UNAVAILABLE
  var status:int=water.prepare_ocean_edit_status(bounds)
  if status==ERR_BUSY and not _occupancy_failure.is_empty():return ERR_CANT_CREATE
  return status
 terrain.solid_deposited.connect(func(bounds:AABB):
  for area:AABB in terrain.water_edit_areas(bounds,true):water.invalidate(area,true))
 # Mining is admitted normally. Invalid regions retain their water and wait for
 # the committed terrain worker samples; they never flow against stale solids.
 # Occupancy patches retain displaced quantity until redistribution can place it.
 if blocks!=null:
  blocks.set_edit_admission(func(bounds:AABB)->bool:return not water.has_deferred_overlap(blocks.global_transform*bounds))
  blocks.cells_changed.connect(_building_changed)
  _structure_revision=blocks.survey_content_revision_id()
  blocks.changed.connect(func():_structure_revision=blocks.survey_content_revision_id())
 _epoch=terrain.epoch
var location_reset_hold:=false
var _held_buildings:=AABB()
func _building_changed(bounds:AABB)->void:
 bounds=blocks.global_transform*bounds
 if location_reset_hold:
  _held_buildings=bounds if not _held_buildings.has_volume() else _held_buildings.merge(bounds)
  return
 water.invalidate_buildings(bounds);_occupancy_failure="";_discard_builder()
 _settle_committed_edit(bounds,0)
func release_location_reset()->void:
 location_reset_hold=false
 if _held_buildings.has_volume():
  water.invalidate_buildings(_held_buildings);_occupancy_failure="";_discard_builder()
  _settle_committed_edit(_held_buildings,0)
 _held_buildings=AABB()
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
 _retire_anticipated_edit()
 _settlement_ticket=-1;_installed_edit_ticket=-1
 _waiting_mesh_commit=-1;_edit_patch_attempt=-1
 _local_response_pending=false;_local_publication_pending=false
 if _equilibrium_job!=null:_equilibrium_job.cancel()
 _equilibrium_failure="";_equilibrium_failed_revision=-1
 _ocean_exchange_ml=0
 _ocean_admitting=false
 _occupancy_failure=""
 _lakes.clear();_filling_id=0;_pending_bucket.clear();_pending_dev.clear()
 _render_pages.clear()
 for mesh:MeshInstance3D in _meshes.values():mesh.queue_free()
 _clear_staged_meshes();_meshes.clear();_mesh_faces.clear();_mesh_batch_id=0;_published_mesh_batch_id=0
 _published_over_capacity_ml=0
 if not preserve_store:water=ClassDB.instantiate("NativeRegionalWater")
 if _surrounding_ocean!=null:
  var empty:=PackedByteArray();empty.resize(500*500);empty.fill(0);_surrounding_ocean.publish(empty)
 _discard_builder()
 _have_bounds=false;_last_changes=0
var _settlement_ticket:=-1
var _waiting_mesh_commit:=-1
var _installed_edit_ticket:=-1
func _terrain_region_installed(ticket:int,_keys:Array)->void:
 if ticket==_installed_edit_ticket:return
 var bounds:=AABB(terrain.geometry_lo,terrain.geometry_hi-terrain.geometry_lo)
 for area:AABB in terrain.water_edit_areas(bounds):
  if not terrain.edit_geometry_ready_in(area):return
 _terrain_geometry_installed(ticket)

func _terrain_geometry_installed(ticket:int)->void:
 if ticket==_installed_edit_ticket:return
 if terrain.water_sampling_revision()<0:return
 _installed_edit_ticket=ticket
 _begin_terrain_settlement(ticket)
 if _waiting_mesh_commit>=0:_commit_prepared_water(_waiting_mesh_commit)

func _begin_terrain_settlement(ticket:int)->void:
 if _settlement_ticket==ticket:return
 _settlement_ticket=ticket
 if not _anticipated_edit.is_empty() and not water.owns_edit_input(_anticipated_edit.transaction):
  _retire_anticipated_edit()
 var low:Vector3=terrain.geometry_lo.min(terrain.edit_lo)
 var high:Vector3=terrain.geometry_hi.max(terrain.edit_hi)
 _queue_settlement(AABB(low,high-low),true)

func _settle_committed_edit(bounds:AABB,_revision:int)->void:
 if _revision>0 and settling_enabled.is_valid() and not settling_enabled.call():return
 if _revision>0 and is_instance_valid(terrain) and _settlement_ticket==terrain.edit_ticket:
  # An offscreen edit may complete without installing a visible terrain tile.
  _terrain_geometry_installed(terrain.edit_ticket)
  return
 _queue_settlement(bounds,_revision>0)

func _queue_settlement(bounds:AABB,terrain_edit:bool)->void:
 # Mining, blasts and other terrain edits share the committed revision. Queue
 # even while paused; advancement remains separately gated by gameplay state.
 # The notification includes terrain meshing/shadow padding. Water connectivity
 # starts at the edited density bounds and supplies its own dependency halo.
 if terrain_edit and is_instance_valid(terrain):
  for area:AABB in terrain.water_edit_areas(bounds):water.settle_after_edit(area)
 else:water.settle_after_edit(bounds)
 if is_instance_valid(terrain) and terrain.world_ready and not (loading_active.is_valid() and loading_active.call()):
  _interrupt_edit_work()
  _local_response_pending=true;_local_publication_pending=false
  _local_response_started_us=Time.get_ticks_usec()
  _edit_equilibrium_jobs=0
  _edit_dependency_rounds=0
  _edit_dependency_regions=0
  _edit_worker_us=0
  _edit_capture_us=0
  _resident_edit_fallback=""
func _interrupt_equilibrium()->void:
 if _equilibrium_task>=0:
  _equilibrium_job.cancel()
  _retirement_jobs.append({"state":_equilibrium_job,"task":_equilibrium_task})
  _equilibrium_task=-1;_equilibrium_job=null
 _equilibrium_failure="";_equilibrium_failed_revision=-1
func _interrupt_edit_work()->void:
 if _edit_patch_task>=0 and _edit_patch_job.has("transaction"):_edit_patch_job.transaction.cancel()
 _interrupt_equilibrium()
 _ocean_exchange_ml+=water.interrupt_relaxation()
 if _mesh_task>=0:
  _mesh_job.cancel()
  _retirement_jobs.append({"state":_mesh_job,"task":_mesh_task})
  _mesh_task=-1;_mesh_job=null
 _clear_staged_meshes();_mesh_batch_id=-1
func _invalidate(bounds:AABB) -> void:
 _retire_anticipated_edit()
 _settlement_ticket=-1;_installed_edit_ticket=-1
 _waiting_mesh_commit=-1;_edit_patch_attempt=-1
 _interrupt_edit_work()
 _occupancy_failure=""
 var areas:Array[AABB]=terrain.water_edit_areas(bounds)
 var wet_areas:Array[AABB]=[]
 for area:AABB in areas:
  water.invalidate(area,false,terrain.edit_ticket if terrain.pending_edit and terrain.field_handoff!=null else -1)
  if settling_active.is_valid() and settling_active.call() and water.overlaps_occupied(area.grow(.5)):
   wet_areas.append(area)
 if not wet_areas.is_empty():terrain.reserve_joint_edit(terrain.edit_ticket,wet_areas)
 _discard_builder()
 if terrain.joint_edit_pending() and not _busy and _edit_patch_task<0 and terrain.field_handoff!=null:
  _subscribe_to_edit_field(areas,bounds)
var last_process_us:int=0
var last_process_work:Dictionary={}
var _process_deadline:=0
var _work_frame:=-1
var _work_spent_us:=0
var _accepted_field_us:=0

func _remaining_frame_work()->int:
 var frame:=Engine.get_process_frames()
 if frame!=_work_frame:
  _work_frame=frame
  _work_spent_us=0
 return maxi(0,850-_work_spent_us)

func _field_ready(ticket:int)->void:
 if not terrain.joint_edit_pending():return
 _accepted_field_us=Time.get_ticks_usec()
 _continue_joint_edit(ticket,terrain.epoch)

func _before_water_draw()->void:
 if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not is_instance_valid(terrain):return
 if terrain.joint_edit_pending():
  _continue_joint_edit(terrain.edit_ticket,terrain.epoch)
 elif _local_publication_pending:
  _publish_water_command()

func _water_command_committed(started:int)->void:
 _local_publication_pending=true
 _local_response_started_us=started
 # Outside the normal water tick the input handler can dispatch its surface
 # worker now. Inside the tick the regular publication pass follows the retry.
 if _process_deadline==0:_publish_water_command()

func _publish_water_command()->void:
 if not _local_publication_pending or _local_response_pending or terrain.pending_edit or not terrain.world_ready or not is_processing() or not can_process():return
 var allowance:=_remaining_frame_work()
 if allowance<=0:return
 var began:=Time.get_ticks_usec()
 _process_deadline=began+allowance
 _publish_meshes()
 _finish_local_publication()
 _process_deadline=0
 _work_spent_us+=Time.get_ticks_usec()-began

func _continue_joint_edit(ticket:int,epoch:int)->void:
 if not is_inside_tree() or not is_processing() or not can_process() or not terrain.world_ready or terrain.epoch!=epoch or terrain.edit_ticket!=ticket or not terrain.joint_edit_pending():return
 if _resident_batch_ready>=0:
  terrain.publish_joint_edit(ticket,_commit_prepared_water.bind(_resident_batch_ready))
  _finish_local_publication()
  return
 var allowance:=_remaining_frame_work()
 # Receiving an accepted field and handing off an already prepared local
 # revision are event work. Background occupancy and equilibrium can consume
 # their allowance before either event arrives in this same rendered frame.
 var dispatch:bool=_settlement_ticket!=ticket and terrain.water_sampling_revision()>=0
 var completed:bool=_ready_transaction!=null or (_edit_patch_task>=0 and WorkerThreadPool.is_group_task_completed(_edit_patch_task))
 if allowance<=0 and not dispatch and not completed:return
 var began:=Time.get_ticks_usec()
 _process_deadline=began+allowance
 if _settlement_ticket!=ticket and terrain.water_sampling_revision()>=0:_begin_terrain_settlement(ticket)
 if _settlement_ticket==ticket and not _busy and _edit_patch_task<0 and _edit_patch_attempt!=ticket:
  _start_edit_patches(terrain.water_sampling_revision())
 _poll_edit_patches()
 if _filling_id==0 and _local_response_pending and _edit_patch_task<0 and Time.get_ticks_usec()<_process_deadline:_advance_equilibrium()
 if _local_publication_pending and Time.get_ticks_usec()<_process_deadline:_publish_meshes()
 _finish_local_publication()
 _process_deadline=0
 _work_spent_us+=Time.get_ticks_usec()-began

func _finish_local_publication()->void:
 if _local_publication_pending:
  var publication_state:Dictionary=water.runtime_state()
  if publication_state.urgent_meshes==0 and not publication_state.urgent_batch:
   # An accepted recut can leave every water quantity and surface unchanged.
   if terrain.joint_edit_pending():
    terrain.publish_joint_edit(terrain.edit_ticket,func()->bool:return true)
   if not terrain.joint_edit_pending():
    _local_publication_pending=false;_local_response_us=Time.get_ticks_usec()-_local_response_started_us

func _prepare_water_job(job:RefCounted,ticket:int,epoch:int)->void:
 job.prepare()
 _continue_joint_edit.call_deferred(ticket,epoch)

func _process(delta:float) -> void:
 var measured_begin:=Time.get_ticks_usec()
 _process_deadline=measured_begin+_remaining_frame_work()
 last_process_work.clear()
 _measured_step(delta)
 if Time.get_ticks_usec()<_process_deadline:_render_pages.step()
 # Retirement uses the unused portion of this frame, not an additional budget.
 var retired_begin:=Time.get_ticks_usec()
 var retirement_deadline:=mini(_process_deadline,retired_begin+150)
 var retired_count:=0
 while not _retired_mesh_nodes.is_empty() and retired_count<4 and Time.get_ticks_usec()<retirement_deadline:
  _retired_mesh_nodes.pop_back().queue_free();retired_count+=1
 last_process_work.retirement=Time.get_ticks_usec()-retired_begin
 last_process_us=Time.get_ticks_usec()-measured_begin
 _work_spent_us+=last_process_us
 _process_deadline=0

func _measured_step(delta:float)->void:
 for i in range(_retirement_jobs.size()-1,-1,-1):
  var retired:Dictionary=_retirement_jobs[i]
  if retired.get("group",false):
   if not WorkerThreadPool.is_group_task_completed(retired.task):continue
   WorkerThreadPool.wait_for_group_task_completion(retired.task)
  else:
   if not WorkerThreadPool.is_task_completed(retired.task):continue
   WorkerThreadPool.wait_for_task_completion(retired.task)
  _retirement_jobs.remove_at(i)
 _poll_cached_task()
 if terrain==null or not terrain.world_ready:return
 # Sampling and settlement consume the accepted density revision. The native
 # published occupancy and visible nodes stay on the prior revision until
 # the corresponding terrain geometry and collision are ready.
 if terrain.pending_edit and _settlement_ticket!=terrain.edit_ticket and terrain.water_sampling_revision()>=0:
  _begin_terrain_settlement(terrain.edit_ticket)
 if blocks!=null:blocks.set_occupancy_interest(PackedVector3Array())
 _poll_edit_patches()
 if terrain.joint_edit_pending() and _settlement_ticket==terrain.edit_ticket and not _busy and _edit_patch_task<0 and _edit_patch_attempt!=terrain.edit_ticket:
  _start_edit_patches(terrain.water_sampling_revision())
 var geometry_ready:bool=not terrain.pending_edit or _installed_edit_ticket==terrain.edit_ticket
 if not _prepared_slice.is_empty() and (geometry_ready or _settlement_ticket==terrain.edit_ticket):
  var prepared:=_prepared_slice
  _prepared_slice={}
  _slice_ready(prepared.token,1,prepared.epoch,prepared.revision)
 water.set_western_ocean(terrain.backend.world_generator==18)
 water.set_surrounding_ocean(terrain.backend.world_generator in [19,21,23,25,27,29,31,33,35,36,37,38])
 if terrain.backend.world_generator in [19,21,23,25,27,29,31,33,35,36,37,38] and _surrounding_ocean==null:
  _surrounding_ocean=preload("res://addons/volumetric_water/ocean_presentation.gd").new()
  add_child(_surrounding_ocean);_surrounding_ocean.setup(_material)
 elif terrain.backend.world_generator not in [19,21,23,25,27,29,31,33,35,36,37,38] and _surrounding_ocean!=null:
  _surrounding_ocean.queue_free();_surrounding_ocean=null;_material.set_shader_parameter("surrounding_ocean",false)
 if _surrounding_ocean==null or not _pending_bucket.is_empty() or not _pending_dev.is_empty():_ocean_admitting=false
 if _surrounding_ocean!=null and not _local_response_pending and not _local_publication_pending and not _busy and _builder==null and not terrain.pending_edit and _pending_bucket.is_empty() and _pending_dev.is_empty():
  var focus:=Vector2i(floori(terrain.focus.x/4),floori(terrain.focus.z/4))
  var revision:int=water.survey_revision_id()
  var now:=Time.get_ticks_usec()
  if focus!=_residency_focus or revision!=_residency_revision or now>=_residency_due:
   var residency:Dictionary=water.update_ocean_residency(terrain.focus,16 if loading_active.is_valid() and loading_active.call() else 4)
   last_process_work.residency=Time.get_ticks_usec()-now
   _ocean_admitting=int(residency.get("admitted",0))>0
   _residency_focus=focus;_residency_revision=water.survey_revision_id()
   # Stable residency has no per-frame work. Movement/edits retry immediately;
   # the bounded periodic pass expires temporary remote-blast interests.
   _residency_due=0 if _ocean_admitting or int(residency.get("retired",0))>0 else now+250000

 if terrain.backend.world_generator==18 and _ocean_horizon==null:
  _material.set_shader_parameter("coastal_join",true)
  _ocean_horizon=preload("res://addons/volumetric_water/coastal_inlet.gd").horizon(_material);add_child(_ocean_horizon)
 elif terrain.backend.world_generator!=18 and _ocean_horizon!=null:
  _ocean_horizon.queue_free();_ocean_horizon=null
  _material.set_shader_parameter("coastal_join",false)
 if _epoch!=terrain.epoch:_epoch=terrain.epoch;_occupancy_failure="";_discard_builder()
 var command_regions:=_retry_pending_commands()
 var before:Dictionary=water.runtime_state()
 if _filling_id!=0 and not before.fill_active:
  var id:=_filling_id;_filling_id=0
  if _lakes.has(id):_lakes[id].dirty=false;lake_ready.emit(id);catalog_changed.emit()
 if _filling_id==0:
  for item:Dictionary in _lakes.values():
   if not item.dirty:continue
   if water.begin_fill(AABB(item.origin,Vector3(item.cells)*item.spacing),item.level,item.seed,item.amount):_filling_id=item.id
   else:item.dirty=false;item.failure="Water authoring bounds unavailable";lake_failed.emit(item.id,-2);catalog_changed.emit()
   break
 # A resident edit can hand its commit to publication on this same frame.
 # Wider equilibrium still waits for the previous publication.
 var can_solve:bool=_filling_id==0 and (geometry_ready or (_local_response_pending and _settlement_ticket==terrain.edit_ticket)) and ((loading_active.is_valid() and loading_active.call()) or (settling_active.is_valid() and settling_active.call()) or terrain.joint_edit_pending())
 var solving_local:bool=can_solve and _local_response_pending
 if solving_local:
  var began:=Time.get_ticks_usec();_advance_equilibrium();last_process_work.equilibrium=Time.get_ticks_usec()-began
 # Show edits before advancing their flow. Native immutable batches retain
 # that state if publication spans more than one frame.
 var can_publish:bool=not solving_local or _process_deadline==0 or Time.get_ticks_usec()<_process_deadline
 if can_publish and (not offline_preparation or _filling_id==0) and (not _ocean_admitting or before.urgent_meshes>0 or before.urgent_batch) and not _local_response_pending:
  var prior_task:=_mesh_task
  var began:=Time.get_ticks_usec();_publish_meshes();last_process_work.publication=Time.get_ticks_usec()-began
  if solving_local and _mesh_task>=0 and _mesh_task!=prior_task:last_process_work.local_mesh_dispatched=true
 _finish_local_publication()
 # Authored filling and blast-woken settling have separate native budgets.
 if _filling_id!=0:water.advance(2048,delta)
 # A restored unfinished transaction must settle during loading: the loading
 # gate itself waits for its matching water geometry. Paused gameplay still waits.
 elif can_solve and not solving_local:
  var began:=Time.get_ticks_usec();_advance_equilibrium();last_process_work.equilibrium=Time.get_ticks_usec()-began
 var occupancy_started:=Time.get_ticks_usec()
 var sampling_revision:int=terrain.water_sampling_revision()
 if not _busy and _edit_patch_task<0 and _prepared_slice.is_empty() and sampling_revision>=0 and _occupancy_failure.is_empty():
  var request:Dictionary=water.next_request()
  if not request.is_empty():
   var preparing_load:bool=loading_active.is_valid() and loading_active.call()
   if _builder==null or _revision!=sampling_revision:
    if not command_regions.is_empty():
     _prepare_terrain_batch(command_regions,sampling_revision)
     request={"coordinate":command_regions[0]}
    elif (preparing_load or _surrounding_ocean!=null or before.settling_regions>0) and _pending_bucket.is_empty() and _pending_dev.is_empty():
     var ocean_only:bool=before.settling_regions==0 and not preparing_load and not terrain.pending_edit
     _prepare_terrain_batch(water.next_requests(8 if ocean_only else 32,ocean_only),sampling_revision)
   if _builder==null or _revision!=sampling_revision:
    _builder=ClassDB.instantiate("NativeWaterTerrainPatch");_builder.configure(request.coordinate);_builder_reused=false;_revision=sampling_revision
    _builder_structure_revision=_structure_revision
    if blocks!=null:
     var hull_started:=Time.get_ticks_usec()
     var solids:Dictionary=_structure_hulls(AABB(Vector3(request.coordinate)*4,Vector3(4,4,4)))
     if not solids.ok or not _builder.set_structure_hulls(solids.hulls):_discard_builder()
     if _builder!=null:_builder_reused=water.reuse_building_occupancy(_builder)
     _hull_snapshot_us=Time.get_ticks_usec()-hull_started
   if _builder!=null:_submit_occupancy_builder()
 last_process_work.occupancy=Time.get_ticks_usec()-occupancy_started

 var after:Dictionary=water.runtime_state()
 if after.capacity_reached and not _capacity_reported:
  _capacity_reported=true;terrain.message_changed.emit("Water resident-region limit reached; quantities retained, expansion paused")
 if after.changes!=_last_changes:terrain.changed_since_save=true;_last_changes=after.changes
 _notify_seconds+=delta
 if _have_bounds and _notify_seconds>=0.25 and not after.mesh_batch_active and not after.mesh_publish_pending and _mesh_publish_us<100:
  _notify_seconds=0;_have_bounds=false
  var notify_started:=Time.get_ticks_usec()
  exclusion_changed.emit(_changed_bounds)
  _exclusion_notify_us=Time.get_ticks_usec()-notify_started
func _advance_equilibrium()->void:
 if _edit_patch_task>=0 and _edit_patch_job.get("transaction")!=null:return
 if _equilibrium_task>=0:
  if not WorkerThreadPool.is_task_completed(_equilibrium_task):return
  WorkerThreadPool.wait_for_task_completion(_equilibrium_task);_equilibrium_task=-1
  var started:=Time.get_ticks_usec()
  var result:Dictionary=water.finish_equilibrium(_equilibrium_job)
  if result.get("local_response",false):
   _edit_equilibrium_jobs+=1
   _edit_worker_us+=int(result.get("worker_us",0))
   if result.get("pending",false):
    _edit_patch_attempt=-1
    _edit_dependency_rounds+=1
    _edit_dependency_regions+=int(result.get("required_regions",0))
   result.edit_equilibrium_jobs=_edit_equilibrium_jobs
   result.edit_dependency_rounds=_edit_dependency_rounds
   result.edit_dependency_regions=_edit_dependency_regions
   result.edit_worker_us=_edit_worker_us
   if not _resident_edit_fallback.is_empty():result.resident_fallback=_resident_edit_fallback
   result.edit_capture_us=_edit_capture_us
   result.edit_elapsed_us=Time.get_ticks_usec()-_local_response_started_us
  if result.get("ok",false) and result.get("local_response",false):
   _local_response_pending=false;_local_publication_pending=true
  _equilibrium_last_result=result
  _equilibrium_job=null
  _equilibrium_commit_us=Time.get_ticks_usec()-started
  last_process_work.equilibrium_commit=_equilibrium_commit_us
  if result.get("ok",false):_equilibrium_blocked_ml=int(result.get("blocked_ml",0))
  if result.get("ok",false):_ocean_exchange_ml+=int(result.get("ocean_exchange_ml",0))
  _equilibrium_phases=result.get("phase_us",PackedInt64Array())
  _equilibrium_worker_us=int(result.get("worker_us",0));_equilibrium_cells=int(result.get("cells",0))
  if result.get("reason","")=="Water equilibrium memory reservation unavailable":
   # Interrupted workers release their reservations without changing the water
   # revision. Retry on the clock so a joint terrain edit can finish in place.
   _equilibrium_retry_us=Time.get_ticks_usec()+50000
  elif result.get("ok",false) or result.get("pending",false) or result.get("stale",false):
   _equilibrium_failure="";_equilibrium_failed_revision=-1
  else:
   _equilibrium_failure=str(result.get("reason","Water equilibrium failed"))
   _equilibrium_failed_revision=water.survey_revision_id()
   terrain.message_changed.emit(_equilibrium_failure)
  return
 if _equilibrium_failed_revision==water.survey_revision_id():return
 if Time.get_ticks_usec()<_equilibrium_retry_us:return
 if _local_publication_pending:return
 var state:Dictionary=water.runtime_state()
 if _local_response_pending and state.settling_regions==0:
  _local_response_pending=false;_local_publication_pending=true;return
 # Direct edits get their own publication before any wider equilibrium starts.
 if not _local_response_pending and (state.mesh_batch_active or state.mesh_publish_pending or (state.dirty_meshes>0 and state.settling_regions==0)):return
 var capture_started:=Time.get_ticks_usec()
 if capture_started>=_process_deadline:return
 _equilibrium_job=water.begin_equilibrium(mini(350,_process_deadline-capture_started),_local_response_pending)
 last_process_work.equilibrium_capture=Time.get_ticks_usec()-capture_started
 if _local_response_pending:_edit_capture_us+=int(last_process_work.equilibrium_capture)
 if _equilibrium_job!=null:
  var local:bool=_local_response_pending and terrain.joint_edit_pending()
  if local:
   var field:Dictionary=terrain.resident_edit_surface
   if field.get("ticket",-1)==terrain.edit_ticket and field.epoch==terrain.epoch and field.revision==terrain.density_revision:
    var area:AABB=terrain.water_occupancy_edit_bounds(AABB(terrain.edit_lo,terrain.edit_hi-terrain.edit_lo)).grow(6)
    if area.get_volume()>512*64:
     var survey:=_edit_structure_survey(area)
     if not survey.is_empty():
      _equilibrium_job.set_edit_field(field.groups,survey.bounds,survey.solids,field.revision,terrain.backend.build_epoch)
  var work:Callable=_prepare_water_job.bind(_equilibrium_job,terrain.edit_ticket,terrain.epoch) if local else _equilibrium_job.prepare
  _equilibrium_task=WorkerThreadPool.add_task(work,local,"Water connected-body equilibrium")
var _replacement_faces:Dictionary={}
var _staged_over_capacity_delta_ml:=0
var _replacement_removals:Array[Vector3i]=[]
var _replacement_hidden:Array[MeshInstance3D]=[]
var _replacement_visible:Array[MeshInstance3D]=[]
var _resident_water_meshes:Dictionary[Vector3i,ArrayMesh]={}
var _resident_batch_ready:=-1
func _clear_replacement_bookkeeping()->void:
 _render_page_changes.clear()
 _replacement_faces.clear();_replacement_removals.clear()
 _staged_over_capacity_delta_ml=0
 _replacement_hidden.clear();_replacement_visible.clear();_resident_water_meshes.clear()
func _clear_staged_meshes()->void:
 _resident_batch_ready=-1
 _waiting_mesh_commit=-1
 for coordinate:Vector3i in _staged_meshes:
  var node:MeshInstance3D=_staged_meshes[coordinate]
  if is_instance_valid(node) and _meshes.get(coordinate)!=node:_retired_mesh_nodes.append(node)
 _staged_meshes.clear();_have_staged_bounds=false
 _clear_replacement_bookkeeping()

func _start_mesh_job(job:RefCounted)->void:
 _mesh_job=job
 var local:bool=is_instance_valid(terrain) and terrain.joint_edit_pending()
 var work:Callable=job.prepare
 if local:work=_prepare_water_job.bind(job,terrain.edit_ticket,terrain.epoch)
 elif _local_publication_pending:work=_prepare_command_mesh.bind(job,terrain.epoch)
 _mesh_task=WorkerThreadPool.add_task(work,local or _local_publication_pending,"Water boundary mesh")
 if _mesh_task<0:
  # Preserve progress if dispatch is unavailable; the job stays owned throughout.
  _mesh_job.prepare();_mesh_job=null

func _prepare_command_mesh(job:RefCounted,epoch:int)->void:
 job.prepare()
 _command_mesh_ready.call_deferred(job,epoch)

func _command_mesh_ready(job:RefCounted,epoch:int)->void:
 if _mesh_job==job and is_instance_valid(terrain) and terrain.epoch==epoch:_publish_water_command()

var last_publication_work:Dictionary={}
func _stage_render_owner(update:Dictionary)->void:
 var coord:Vector3i=update.coordinate
 var previous:MeshInstance3D=_meshes.get(coord)
 if previous==null and update.vertices==0:return
 var old_faces:Dictionary=_mesh_faces.get(coord,{})
 _staged_over_capacity_delta_ml-=int(old_faces.get("over_capacity_ml",0))
 var bounds:=AABB(Vector3(coord)*4,Vector3(4,4,4))
 _staged_bounds=_staged_bounds.merge(bounds) if _have_staged_bounds else bounds;_have_staged_bounds=true
 if update.vertices>0:
  _replacement_faces[coord]=update.faces
  _staged_over_capacity_delta_ml+=int(update.faces.get("over_capacity_ml",0))
  var digest:PackedByteArray=update.faces.get("render_digest",PackedByteArray())
  if previous!=null and digest.size()==32 and digest==old_faces.get("render_digest",PackedByteArray()):
   # The native batch still commits the new picking and immersion state.
   return
 if update.vertices==0:
  if previous!=null:_replacement_hidden.append(previous)
  _replacement_removals.append(coord)
  _staged_meshes[coord]=null
  _render_page_changes[coord]={}
  return
 var geometry:ArrayMesh=update.get("render_mesh")
 if geometry==null:
  geometry=ArrayMesh.new()
  geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,update.render_arrays)
 if previous!=null and terrain.joint_edit_pending():
  _staged_meshes[coord]=previous
  _resident_water_meshes[coord]=geometry
  _render_page_changes[coord]={"node":previous,"arrays":update.render_arrays}
  return
 if previous!=null:_replacement_hidden.append(previous)
 var node:=MeshInstance3D.new()
 node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.material_override=_material
 node.position=bounds.position;node.visible=false;node.mesh=geometry;add_child(node)
 _staged_meshes[coord]=node
 _render_page_changes[coord]={"node":node,"arrays":update.render_arrays}
 _replacement_visible.append(node)

func _publish_meshes() -> void:
 if terrain.joint_edit_pending() and (_settlement_ticket!=terrain.edit_ticket or not _local_publication_pending):return
 last_publication_work.clear()
 var prepared_only:=_mesh_task>=0 and not WorkerThreadPool.is_task_completed(_mesh_task)
 if _mesh_task>=0 and not prepared_only:
  WorkerThreadPool.wait_for_task_completion(_mesh_task);_mesh_task=-1;_mesh_job=null
 # Build/upload within the existing soft budget; only a complete immutable
 # batch becomes visible. Flow may advance between calls without mixed edges.
 var mesh_started:=Time.get_ticks_usec()
 var loading:bool=loading_active.is_valid() and loading_active.call()
 var packets:int=PublicationBudget.LOADING_MAX_PACKETS if loading else PublicationBudget.MAX_PACKETS
 var budget_us:int=PublicationBudget.LOADING_SOFT_TIME_US if loading else mini(PublicationBudget.SOFT_TIME_US,maxi(0,_process_deadline-mesh_started)) if _process_deadline>0 else PublicationBudget.SOFT_TIME_US
 if budget_us<=0:return
 for publication in packets:
  var packet_started:=Time.get_ticks_usec()
  var update:Dictionary=water.next_mesh_batch(true,true,prepared_only,terrain.joint_edit_pending())
  last_publication_work.native_packet=int(last_publication_work.get("native_packet",0))+Time.get_ticks_usec()-packet_started
  if update.is_empty():break
  if update.has("failure"):
   _clear_staged_meshes()
   if _surface_failure.is_empty():
    _surface_failure=str(update.failure);terrain.message_changed.emit(_surface_failure)
   break
  _surface_failure=""
  if update.has("job"):
   _start_mesh_job(update.job)
   break
  if update.get("pending",false):break
  if update.batch!=_mesh_batch_id:
   _clear_staged_meshes();_mesh_batch_id=update.batch
  var upload_started:=Time.get_ticks_usec()
  if update.has("coordinate"):
   _stage_render_owner(update)
  last_publication_work.upload=int(last_publication_work.get("upload",0))+Time.get_ticks_usec()-upload_started
  if update.complete:
   # Commit on its own short slice if staging already consumed this frame.
   if terrain.joint_edit_pending():
    terrain.publish_joint_edit(terrain.edit_ticket,_commit_prepared_water.bind(update.batch))
    break
   if Time.get_ticks_usec()-mesh_started>150:break
   if terrain.pending_edit and _installed_edit_ticket!=terrain.edit_ticket:
    _waiting_mesh_commit=update.batch
    break
   _commit_prepared_water(update.batch)
   if not _surface_failure.is_empty():break
  if Time.get_ticks_usec()-mesh_started>=budget_us:break
 _mesh_publish_us=Time.get_ticks_usec()-mesh_started;_mesh_max_publish_us=maxi(_mesh_max_publish_us,_mesh_publish_us)
func _commit_prepared_water(batch:int)->bool:
 _resident_batch_ready=-1
 _waiting_mesh_commit=-1
 var commit_started:=Time.get_ticks_usec()
 var native_started:=Time.get_ticks_usec()
 if not water.commit_mesh_batch(batch,_replacement_hidden,_replacement_visible):
  _clear_staged_meshes();_surface_failure="Water query publication did not match rendered batch"
  push_error(_surface_failure);return false
 _mesh_commit_native_us=Time.get_ticks_usec()-native_started
 var bookkeeping_started:=Time.get_ticks_usec()
 _mesh_commit_count=_staged_meshes.size()
 # Install only this revision's changed owners, in the same main-thread
 # call as the native visibility and picking commit.
 for coord:Vector3i in _resident_water_meshes:
  _staged_meshes[coord].mesh=_resident_water_meshes[coord]
 _meshes.merge(_staged_meshes,true)
 _mesh_faces.merge(_replacement_faces,true)
 _published_over_capacity_ml+=_staged_over_capacity_delta_ml
 for coordinate:Vector3i in _replacement_removals:
  _meshes.erase(coordinate);_mesh_faces.erase(coordinate)
 _retired_mesh_nodes.append_array(_replacement_hidden)
 _render_pages.commit(_render_page_changes)
 if _have_staged_bounds:
  _changed_bounds=_changed_bounds.merge(_staged_bounds) if _have_bounds else _staged_bounds;_have_bounds=true
 _mesh_commit_nodes_us=Time.get_ticks_usec()-bookkeeping_started
 last_publication_work.commit_nodes=_mesh_commit_nodes_us
 last_publication_work.commit_native=_mesh_commit_native_us
 _published_mesh_batch_id=batch
 var mask_started:=Time.get_ticks_usec()
 if _surrounding_ocean!=null:_surrounding_ocean.publish(water.ocean_publication_mask())
 _mesh_commit_mask_us=Time.get_ticks_usec()-mask_started
 # Every staged node now belongs to _meshes; no cancellation cleanup scan.
 _staged_meshes={};_have_staged_bounds=false;_clear_replacement_bookkeeping()
 _mesh_commit_us=Time.get_ticks_usec()-commit_started;_mesh_max_commit_us=maxi(_mesh_max_commit_us,_mesh_commit_us)
 if terrain.joint_edit_pending() and _equilibrium_last_result.get("timed_ticket",-1)==terrain.edit_ticket:
  _equilibrium_last_result.joint_install_us=Time.get_ticks_usec()-terrain.edit_accepted_us

 return true

func _structure_hulls(bounds:AABB)->Dictionary:
 var result:Dictionary=blocks.solid_hulls(bounds)
 if result.get("unavailable",false):
  # The pager reads this exact saved region asynchronously within its existing
  # budgets. Unknown solids never become empty space or block loading forever.
  blocks.set_occupancy_interest(PackedVector3Array([bounds.get_center()]))
 return result

var _receiver_survey:Dictionary={}
func _edit_structure_survey(bounds:AABB)->Dictionary:
 # Survey the block pager on its owning thread. A known-empty 16 m chunk
 # certifies all 64 of its water regions. Only occupied chunks need details.
 if _receiver_survey.get("ticket",-1)==terrain.edit_ticket and _receiver_survey.epoch==terrain.epoch and _receiver_survey.revision==_structure_revision:
  return _receiver_survey
 var first:=Vector3i((bounds.position/16).floor()).clamp(Vector3i.ZERO,Vector3i(125,16,125))
 var end:=Vector3i((bounds.end/16).ceil()).clamp(Vector3i.ZERO,Vector3i(125,16,125))
 var count:Vector3i=end-first
 if count.x*count.y*count.z>512 or count.x<=0 or count.y<=0 or count.z<=0:return {}
 var area:=AABB(Vector3(first)*16,Vector3(count)*16)
 var solids:Dictionary={}
 if blocks!=null:
  var transforms:Array[Transform3D]=[]
  for z in range(first.z,end.z):
   for y in range(first.y,end.y):
    for x in range(first.x,end.x):transforms.append(Transform3D(Basis.IDENTITY,Vector3(x,y,z)*16))
  var mask:PackedByteArray=blocks.overlap_mask(transforms,AABB(Vector3.ZERO,Vector3.ONE*16))
  if mask.size()!=transforms.size():return {}
  var subregions:Array[Transform3D]=[]
  for i in mask.size():
   if not mask[i]:continue
   if subregions.size()>=2048:return {}
   for z in 4:
    for y in 4:
     for x in 4:subregions.append(Transform3D(Basis.IDENTITY,transforms[i].origin+Vector3(x,y,z)*4))
  if not subregions.is_empty():
   var occupied:PackedByteArray=blocks.overlap_mask(subregions,AABB(Vector3.ZERO,Vector3.ONE*4))
   if occupied.size()!=subregions.size():return {}
   for i in occupied.size():
    if not occupied[i]:continue
    var origin:=subregions[i].origin
    var result:Dictionary=blocks.solid_hulls(AABB(origin,Vector3.ONE*4))
    solids[Vector3i(origin/4)]=result.hulls if result.ok else null
 _receiver_survey={"ticket":terrain.edit_ticket,"epoch":terrain.epoch,"revision":_structure_revision,"bounds":area,"solids":solids}
 return _receiver_survey

# The native placement planner has already identified this intent's missing
# bricks. Submit them at input, without waiting for the next water tick to
# rediscover the same coordinates. A worker already in flight retains ownership.
func _start_command_occupancy(coordinates:Array)->void:
 if coordinates.is_empty() or _busy or _builder!=null or _edit_patch_task>=0 or not _prepared_slice.is_empty() or not _occupancy_failure.is_empty():return
 if not terrain.world_ready or terrain.pending_edit or _epoch!=terrain.epoch:return
 var revision:int=terrain.water_sampling_revision()
 if revision<0:return
 _prepare_terrain_batch(coordinates,revision)
 if _builder!=null:_submit_occupancy_builder()

func _submit_occupancy_builder()->void:
 _token=_builder.get_instance_id()
 if _builder_reused:
  _cached_job={"builder":_builder,"token":_token,"epoch":terrain.epoch,"revision":_revision,"submitted_us":Time.get_ticks_usec()}
  _cached_task=WorkerThreadPool.add_task(_builder.prepare_cached,false,"Water cached building occupancy")
  if _cached_task>=0:_busy=true
  else:
   _cached_job={}
   if terrain.request_lake_slice(_builder,_token):_busy=true
 elif terrain.request_lake_slice(_builder,_token):_busy=true

func _prepare_terrain_batch(coordinates:Array,sampling_revision:int) -> void:
 _discard_builder()
 _builder_reused=false
 _revision=sampling_revision
 _builder_structure_revision=_structure_revision
 var hull_started:=Time.get_ticks_usec()
 for coordinate:Vector3i in coordinates:
  var patch:RefCounted=ClassDB.instantiate("NativeWaterTerrainPatch")
  if not patch.configure(coordinate):_discard_builder();return
  if blocks!=null:
   var solids:Dictionary=_structure_hulls(AABB(Vector3(coordinate)*4,Vector3(4,4,4)))
   if not solids.ok or not patch.set_structure_hulls(solids.hulls):
    if _builder_patches.is_empty():_discard_builder();return
    break
   # Cached building-only patches share the same bounded batch worker; loading
   # thousands of unchanged regions must not require one rendered frame each.
   water.reuse_building_occupancy(patch)
  _builder_patches.append(patch)
 _hull_snapshot_us=Time.get_ticks_usec()-hull_started
 var batch:RefCounted=ClassDB.instantiate("NativeWaterTerrainBatch")
 if batch.configure(_builder_patches):_builder=batch
 else:_discard_builder()
# The terrain field and construction hulls are immutable for this worker.
# It prepares every pending patch of the local edit in one trip. No live
# water ownership or scene nodes are handed to the worker.
var _edit_patch_task:=-1
var _edit_patch_job:Dictionary={}
var _anticipated_edit:Dictionary={}
var _ready_transaction:RefCounted

# This callback runs on the scene thread after the worker has sealed every
# packet and written its final timestamp. WorkerThreadPool can still be
# returning from the callback at this point. Its task handle is retired
# independently of the revision that is ready to draw.
func _water_worker_ready(ticket:int,epoch:int,transaction:RefCounted)->void:
 if _anticipated_edit.get("transaction")==transaction or _edit_patch_job.get("transaction")==transaction:
  _ready_transaction=transaction
  _continue_joint_edit(ticket,epoch)

func _subscribe_to_edit_field(areas:Array[AABB],bounds:AABB)->void:
 var resident:RefCounted=water.capture_local_edit(false,areas)
 if resident==null:return
 var survey:=_edit_structure_survey(terrain.water_occupancy_edit_bounds(bounds).grow(6))
 if survey.is_empty():return
 var job:={"ticket":terrain.edit_ticket,"epoch":terrain.epoch,"revision":terrain.published_revision+1,
  "structures":_structure_revision,"cancel":terrain.backend.build_epoch,"transaction":resident,
  "samples_field":true,"anticipated":true,"patches":[],"groups":[],"ready":false}
 # Only frozen references and the post-commit notification cross the worker
 # boundary. Both the authority and the renderer keep their old live surfaces.
 var handoff:RefCounted=terrain.field_handoff
 _anticipated_edit={"job":job,"handoff":handoff,"transaction":resident}
 handoff.subscribe(_prepare_sealed_water.bind(job,survey,DisplayServer.get_name()!="headless",_water_worker_ready))

static func _prepare_sealed_water(_index:int,surface:Dictionary,job:Dictionary,survey:Dictionary,render:bool,notify:Callable)->void:
 job.worker_started_us=Time.get_ticks_usec()
 job.dispatch_us=surface.dispatch_us
 job.field=surface.revision
 if job.ticket==surface.ticket and job.epoch==surface.epoch and job.transaction.set_field(surface.groups,survey.bounds,survey.solids,job.field,job.cancel):
  job.transaction.set_terrain_writes(surface.get("writes",[]),surface.get("prior_field",-1),job.ticket)
  job.occupancy_supplied_us=Time.get_ticks_usec()
  job.transaction.prepare([],render)
 job.worker_ready_us=Time.get_ticks_usec()
 notify.call_deferred(job.ticket,job.epoch,job.transaction)

func _retire_anticipated_edit()->void:
 _ready_transaction=null
 if _anticipated_edit.is_empty():return
 _anticipated_edit.transaction.cancel()
 var task:int=_anticipated_edit.handoff.detach()
 if task>=0:_retirement_jobs.append({"state":_anticipated_edit.transaction,"task":task,"group":true})
 _anticipated_edit={}

static func _group_edit_patches(coords:Array,patches:Array,bounds:Rect2i)->Array:
 if bounds.size.x<=64 and bounds.size.y<=64:return [{"bounds":bounds,"patches":patches}]
 var groups:Dictionary={}
 for index in coords.size():
  var coord:Vector3i=coords[index]
  var area:=Rect2i(coord.x*4,coord.z*4,4,4)
  var key:=area.position/64
  if not groups.has(key):groups[key]={"bounds":area,"patches":[]}
  var group:Dictionary=groups[key]
  group.bounds=Rect2i(group.bounds).merge(area)
  group.patches.append(patches[index])
 return groups.values()

static func _contact_groups(coords:Array,patches:Array,bounds:Rect2i,fields:Array)->Array:
 if fields.is_empty():return _group_edit_patches(coords,patches,bounds)
 var groups:Array=[]
 for field:Dictionary in fields:
  groups.append({"bounds":field.bounds,"core":field.core,"patches":[]})
 var remaining_coords:Array=[]
 var remaining_patches:Array=[]
 var remaining_bounds:=Rect2i()
 for index in coords.size():
  var coord:Vector3i=coords[index]
  var area:=Rect2i(coord.x*4,coord.z*4,4,4)
  var covered:=false
  for group:Dictionary in groups:
   if Rect2i(group.bounds).encloses(area):
    group.patches.append(patches[index])
    covered=true
    break
  if covered:continue
  remaining_coords.append(coord)
  remaining_patches.append(patches[index])
  remaining_bounds=remaining_bounds.merge(area) if remaining_bounds.has_area() else area
 for i in range(groups.size()-1,-1,-1):
  if groups[i].patches.is_empty():groups.remove_at(i)
 if not remaining_coords.is_empty():groups.append_array(_group_edit_patches(remaining_coords,remaining_patches,remaining_bounds))
 return groups

func _start_edit_patches(revision:int)->bool:
 if _edit_patch_task>=0 or _busy or not terrain.joint_edit_pending():return false
 if not _anticipated_edit.is_empty():
  var task:int=_anticipated_edit.handoff.detach()
  if task>=0:
   _edit_patch_job=_anticipated_edit.job;_edit_patch_task=task;_edit_patch_attempt=terrain.edit_ticket
   _anticipated_edit={}
   return true
  _anticipated_edit={}
 var surface:Dictionary=terrain.resident_edit_surface
 var fields:Array=[]
 if surface.get("ticket",-1)==terrain.edit_ticket and surface.epoch==terrain.epoch and surface.revision==terrain.density_revision:
  fields=surface.groups
 if not fields.is_empty() and _resident_edit_fallback.is_empty():
  var resident:RefCounted=water.capture_local_edit(true)
  if resident==null:resident=water.capture_local_edit(false)
  if resident!=null:
   var area:AABB=terrain.water_occupancy_edit_bounds(AABB(terrain.edit_lo,terrain.edit_hi-terrain.edit_lo)).grow(6)
   var survey:=_edit_structure_survey(area)
   if not survey.is_empty() and resident.set_field(fields,survey.bounds,survey.solids,surface.revision,terrain.backend.build_epoch):
    _edit_patch_job={"ticket":terrain.edit_ticket,"epoch":terrain.epoch,"revision":revision,
     "structures":_structure_revision,"field":surface.revision,"cancel":terrain.backend.build_epoch,
     "transaction":resident,"samples_field":true,"patches":[],"groups":[],"ready":false,"dispatch_us":Time.get_ticks_usec()}
    _edit_patch_task=WorkerThreadPool.add_group_task(_prepare_resident_water.bind(terrain.backend.native,_edit_patch_job),1,1,true,"Resident terrain and water edit")
    if _edit_patch_task>=0:
     _edit_patch_attempt=terrain.edit_ticket
     return true
 var coords:Array=water.pending_edit_patches()
 if coords.is_empty():
  _edit_patch_attempt=terrain.edit_ticket
  return false
 var first:Vector3i=coords[0]
 var bounds:=Rect2i(first.x*4,first.z*4,4,4)
 var patches:Array[RefCounted]=[]
 for coord:Vector3i in coords:
  bounds=bounds.merge(Rect2i(coord.x*4,coord.z*4,4,4))
  var patch:RefCounted=ClassDB.instantiate("NativeWaterTerrainPatch")
  if not patch.configure(coord):return false
  if blocks!=null:
   var solids:Dictionary=_structure_hulls(AABB(Vector3(coord)*4,Vector3(4,4,4)))
   if not solids.ok or not patch.set_structure_hulls(solids.hulls):return false
  patches.append(patch)
 _edit_patch_job={"ticket":terrain.edit_ticket,"epoch":terrain.epoch,"revision":revision,
  "structures":_structure_revision,"field":terrain.density_revision,"cancel":terrain.backend.build_epoch,
  "patches":patches,"groups":_contact_groups(coords,patches,bounds,fields),"ready":false,"dispatch_us":Time.get_ticks_usec()}
 var groups:Array=_edit_patch_job.groups
 var transaction:RefCounted=water.capture_local_edit()
 if transaction!=null:
  _edit_patch_job.transaction=transaction
  _edit_patch_task=WorkerThreadPool.add_group_task(_prepare_resident_water.bind(terrain.backend.native,_edit_patch_job),1,1,true,"Resident water edit")
 else:
  _edit_patch_task=WorkerThreadPool.add_group_task(_sample_contact_group.bind(terrain.backend.native,_edit_patch_job),groups.size(),mini(groups.size(),4),true,"Local edited water contacts")
 if _edit_patch_task>=0:_edit_patch_attempt=terrain.edit_ticket
 return _edit_patch_task>=0

func _sample_contact_group(index:int,core:Object,job:Dictionary)->void:
 var group:Dictionary=job.groups[index]
 group.ready=false
 var snapshot:Object=group.get("core")
 if snapshot==null:snapshot=core.capture_contact_core(group.bounds,job.field,job.cancel)
 if snapshot==null:return
 for patch:RefCounted in group.patches:
  var status:int=patch.sample_terrain(snapshot,2048,job.field,job.cancel)
  while status==0:status=patch.sample_terrain(snapshot,2048,job.field,job.cancel)
  if status!=1:
   group.failure=patch.statistics()
   return
 group.ready=true
 if not job.has("transaction"):_continue_joint_edit.call_deferred(job.ticket,job.epoch)

func _prepare_resident_water(_index:int,core:Object,job:Dictionary)->void:
 job.worker_started_us=Time.get_ticks_usec()
 var groups:Array=job.groups
 if groups.size()==1:
  _sample_contact_group(0,core,job)
 elif groups.size()>1:
  var sampling:=WorkerThreadPool.add_group_task(_sample_contact_group.bind(core,job),groups.size(),mini(groups.size(),4),true,"Resident water contacts")
  if sampling>=0:WorkerThreadPool.wait_for_group_task_completion(sampling)
 _finish_contact_groups(job)
 job.occupancy_supplied_us=Time.get_ticks_usec()
 if job.ready:job.transaction.prepare(job.patches,DisplayServer.get_name()!="headless")
 job.worker_ready_us=Time.get_ticks_usec()
 _water_worker_ready.call_deferred(job.ticket,job.epoch,job.transaction)

func _finish_contact_groups(job:Dictionary)->void:
 job.ready=false
 for group:Dictionary in job.groups:
  if not group.get("ready",false):
   job.failure=group.get("failure",{})
   return
 job.ready=true

var _shared_contact_patches:=0
var _resident_edit_fallback:=""
var _edit_patch_attempt:=-1
func _poll_edit_patches()->void:
 if _edit_patch_task<0:return
 if WorkerThreadPool.is_group_task_completed(_edit_patch_task):
  WorkerThreadPool.wait_for_group_task_completion(_edit_patch_task)
 elif _ready_transaction!=null and _edit_patch_job.get("transaction")==_ready_transaction:
  _retirement_jobs.append({"state":_ready_transaction,"task":_edit_patch_task,"group":true})
 else:return
 _ready_transaction=null
 var job:=_edit_patch_job
 _finish_contact_groups(job)
 _edit_patch_task=-1;_edit_patch_job={}
 if job.ticket!=terrain.edit_ticket or job.epoch!=terrain.epoch or not terrain.joint_edit_pending():return
 if job.structures!=_structure_revision or job.cancel!=terrain.backend.build_epoch or job.revision!=terrain.water_sampling_revision():
  _edit_patch_attempt=-1
  return
 if not job.ready:
  _slice_failure=job.get("failure",{})
  if _slice_failure.get("status",-4)==-4:
   _edit_patch_attempt=-1
  else:
   _occupancy_failure="Local water occupancy preparation failed at %s (status %s)"%[_slice_failure.coordinate,_slice_failure.status]
   terrain.message_changed.emit(_occupancy_failure)
  return
 for group:Dictionary in job.groups:
  if group.has("core"):_shared_contact_patches+=group.patches.size()
 if job.has("transaction"):
  var adopt_started:=Time.get_ticks_usec()
  var result:Dictionary=water.accept_local_edit(job.transaction)
  if result.get("ok",false):
   _clear_staged_meshes();_mesh_batch_id=result.batch
   for packet:Dictionary in result.packets:_stage_render_owner(packet)
   result.erase("packets")
   _equilibrium_last_result=result
   var admitted:int=terrain.edit_accepted_us
   result.timed_ticket=job.ticket
   result.field_ready_us=_accepted_field_us-admitted
   result.dispatch_us=job.dispatch_us-admitted
   result.worker_started_us=job.worker_started_us-admitted
   result.occupancy_supplied_us=job.occupancy_supplied_us-admitted
   result.worker_ready_us=job.worker_ready_us-admitted
   result.adopt_started_us=adopt_started-admitted
   result.water_staged_us=Time.get_ticks_usec()-admitted
   _edit_equilibrium_jobs+=1
   _equilibrium_worker_us=int(result.get("worker_us",0));_edit_worker_us+=_equilibrium_worker_us
   _equilibrium_phases=result.get("phase_us",PackedInt64Array());_equilibrium_cells=int(result.get("cells",0))
   _equilibrium_blocked_ml=int(result.get("blocked_ml",0));_ocean_exchange_ml+=int(result.get("ocean_exchange_ml",0))
   _local_response_pending=false;_local_publication_pending=true
   if result.prepared_publication:
    _resident_batch_ready=result.batch
    terrain.publish_joint_edit(job.ticket,_commit_prepared_water.bind(_resident_batch_ready))
   terrain.water_preparation_revision+=1
   return
  if job.get("anticipated",false):
   _edit_patch_attempt=-1
   return
  _resident_edit_fallback=result.get("fallback","superseded water revision")
  if job.get("samples_field",false):
   _edit_patch_attempt=-1
   return
 for patch:RefCounted in job.patches:
  if not water.accept_patch(patch):
   _occupancy_failure="Local water occupancy cache budget reached"
   terrain.message_changed.emit(_occupancy_failure)
   return
 if job.patches.size()==64:_edit_patch_attempt=-1
 terrain.water_preparation_revision+=1

var _prepared_slice:Dictionary={}
func _discard_builder() -> void:
 _prepared_slice={}
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
 _retire_anticipated_edit()
 if _edit_patch_task>=0:WorkerThreadPool.wait_for_group_task_completion(_edit_patch_task)
 if _equilibrium_task>=0:
  _equilibrium_job.cancel();WorkerThreadPool.wait_for_task_completion(_equilibrium_task);_equilibrium_task=-1
 if _mesh_task>=0:
  WorkerThreadPool.wait_for_task_completion(_mesh_task);_mesh_task=-1;_mesh_job=null
 for job:Dictionary in _retirement_jobs:
  if job.get("group",false):WorkerThreadPool.wait_for_group_task_completion(job.task)
  else:WorkerThreadPool.wait_for_task_completion(job.task)
 _retirement_jobs.clear()
 if _cached_task>=0:
  _cached_job.builder.cancel_cached()
  WorkerThreadPool.wait_for_task_completion(_cached_task)
  _cached_task=-1;_cached_job={}
func _slice_ready(token:int,status:int,epoch_id:int,revision:int) -> void:
 _slice_callbacks+=1;_slice_last_status=status
 if status<0:
  for patch:RefCounted in _builder_patches:
   var info:Dictionary=patch.statistics()
   if int(info.status)<0:_slice_failure=info
 if token!=_token:return
 _busy=false
 if _builder==null or _builder_structure_revision!=_structure_revision or epoch_id!=terrain.epoch or revision!=terrain.water_sampling_revision() or status==-4:_discard_builder();return
 if status==0:return
 if status==1 and terrain.pending_edit and _settlement_ticket!=terrain.edit_ticket:
  _prepared_slice={"token":token,"epoch":epoch_id,"revision":revision}
  return
 if status==1:
  terrain.water_preparation_revision+=1
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
 if status==1 and _occupancy_failure.is_empty() and not terrain.pending_edit and (not _pending_bucket.is_empty() or not _pending_dev.is_empty()):
  _start_command_occupancy(_retry_pending_commands())

func _retry_pending_commands()->Array:
 var command_regions:Array
 if not _pending_bucket.is_empty():
  var p:=_pending_bucket
  # Expiration is a precondition: never execute a stale click first and
  # discover afterwards that its loading deadline already passed.
  var result:Dictionary={"ok":false,"pending":false,"reason":"Water action timed out; bucket unchanged. Try again."} if Time.get_ticks_msec()>p.deadline else _transfer_bucket(p.from,p.to,p.pour,p.inventory,p.slot,p.revision)
  if result.has("occupancy_regions"):command_regions=result.occupancy_regions
  if result.ok or not result.pending or Time.get_ticks_msec()>p.deadline:
   _pending_bucket={}
   if result.pending:result.reason="Water action timed out; bucket unchanged. Try again."
   if result.ok:terrain.changed_since_save=true;bucket_completed.emit(p.slot)
   terrain.message_changed.emit(result.reason)
   interaction_finished.emit(result.reason)
 if not _pending_dev.is_empty():
  var p:=_pending_dev
  var result:Dictionary={"ok":false,"pending":false,"reason":"Water placement timed out; no water placed. Try again."} if Time.get_ticks_msec()>p.deadline else water.place_water(p.point,p.amount)
  if result.has("occupancy_regions"):command_regions=result.occupancy_regions
  if result.ok or not result.pending or Time.get_ticks_msec()>p.deadline:
   _pending_dev={}
   if result.pending:result.reason="Water placement timed out; no water placed. Try again."
   if result.ok:
    terrain.changed_since_save=true
    _water_command_committed(p.started)
   terrain.message_changed.emit(result.reason)
   interaction_finished.emit(result.reason)
 return command_regions

func _transfer_bucket(from:Vector3,to:Vector3,pour:bool,inventory:RefCounted,slot:int,revision:int)->Dictionary:
 var started:=Time.get_ticks_usec()
 if _pending_bucket.is_empty():_interrupt_edit_work()
 var result:Dictionary=water.transfer_bucket(from,to,pour,inventory,slot,revision)
 if result.get("ok",false):
  _interrupt_equilibrium()
  _water_command_committed(_pending_bucket.get("started",started))
 _bucket_native_us=Time.get_ticks_usec()-started
 _max_bucket_native_us=maxi(_max_bucket_native_us,_bucket_native_us)
 return result
func bucket(from:Vector3,to:Vector3,pour:bool,inventory:RefCounted,slot:int,revision:int) -> Dictionary:
 # A new intent supersedes queued edits, even if this new target is rejected.
 _pending_bucket.clear();_pending_dev.clear()
 if not terrain.world_ready or terrain.pending_edit:return {"ok":false,"reason":"Wait for the terrain edit to finish"}
 var started:=Time.get_ticks_usec()
 var result:Dictionary=_transfer_bucket(from,to,pour,inventory,slot,revision)
 if result.pending:
  _pending_bucket={"from":from,"to":to,"pour":pour,"inventory":inventory,"slot":slot,"revision":revision,"started":started,"deadline":Time.get_ticks_msec()+5000}
  _start_command_occupancy(result.get("occupancy_regions",[]))
 if result.ok:terrain.changed_since_save=true
 return result
func dev_brush(point:Vector3,remove:bool,radius:float=2.0,amount_ml:int=1000000) -> Dictionary:
 # A new intent supersedes queued edits, even if this new target is rejected.
 _pending_bucket.clear();_pending_dev.clear()
 if not terrain.world_ready or terrain.pending_edit:return {"ok":false,"pending":false,"reason":"Wait for the terrain edit to finish"}
 if not point.is_finite():return {"ok":false,"pending":false,"reason":"Aim at a surface within 5 m"}
 var started:=Time.get_ticks_usec()
 if remove:
  var removed:int=water.brush(point,radius,-0x10000000000000)
  if removed>0:
   terrain.changed_since_save=true
   _water_command_committed(started)
  return {"ok":removed>0,"pending":false,"water_ml":removed,"reason":"Removed %.3f m³ of water"%(float(removed)/1000000.0) if removed>0 else "No water removed; the target is empty or water is preparing"}
 var result:Dictionary=water.place_water(point,amount_ml)
 if result.pending:
  _pending_dev={"point":point,"amount":amount_ml,"started":started,"deadline":Time.get_ticks_msec()+5000}
  _start_command_occupancy(result.get("occupancy_regions",[]))
 if result.ok:
  terrain.changed_since_save=true
  _water_command_committed(started)
 terrain.message_changed.emit(result.reason)
 return result
func placement_mask(transforms:Array[Transform3D]) -> PackedByteArray:return water.placement_mask(transforms)
func depth_at(point:Vector3) -> float:return water.depth_at(point)
# Generation/persistence barrier: geometry may publish later, but authored
# quantities and sampled terrain/building contacts must stop changing first.
func preparation_ready()->bool:
 if water==null or _busy or _builder!=null or _equilibrium_task>=0 or _ocean_admitting:return false
 var state:Dictionary=water.runtime_state()
 return not state.fill_active and state.pending_regions==0 and state.settling_regions==0

func statistics() -> Dictionary:
 var s:Dictionary=water.statistics();s.render_pages=_render_pages.statistics();s.lakes=_lakes.size();s.ready=0;s.outstanding_slices=int(_busy);s.resident_occupancy_bytes=s.resident_cell_bytes
 s.preparation={"busy":_busy,"builder":_builder!=null,"ocean_admitting":_ocean_admitting,"local_response":_local_response_pending,"local_publication":_local_publication_pending,"cached_task":_cached_task,"offline":offline_preparation}
 s.ocean_boundary_exchange_ml=_ocean_exchange_ml
 for item:Dictionary in _lakes.values():
  if not item.dirty and item.failure.is_empty():s.ready+=1
 s.shared_edit_contact_patches=_shared_contact_patches
 s.occupancy_failure=_occupancy_failure
 s.equilibrium_blocked_ml=_equilibrium_blocked_ml
 s.mesh_commit_nodes_us=_mesh_commit_nodes_us;s.mesh_commit_native_us=_mesh_commit_native_us;s.mesh_commit_mask_us=_mesh_commit_mask_us;s.mesh_commit_count=_mesh_commit_count;s.retired_mesh_nodes=_retired_mesh_nodes.size()
 s.slice_failure=_slice_failure;s.slice_callbacks=_slice_callbacks;s.slice_last_status=_slice_last_status;s.next_occupancy_request=water.next_request();s.occupancy_busy=_busy;s.occupancy_builder_present=_builder!=null;
 s.equilibrium_failure=_equilibrium_failure;s.equilibrium_result=_equilibrium_last_result
 s.equilibrium_phases=_equilibrium_phases
 s.equilibrium_worker_us=_equilibrium_worker_us
 s.equilibrium_cells=_equilibrium_cells
 s.equilibrium_commit_us=_equilibrium_commit_us
 s.equilibrium_pending=_equilibrium_task>=0
 s.surface_failure=_surface_failure
 s.published_over_capacity_ml=_published_over_capacity_ml
 s.bucket_native_us=_bucket_native_us;s.max_bucket_native_us=_max_bucket_native_us
 s.exclusion_notify_us=_exclusion_notify_us;s.accept_patch_us=_accept_patch_us;s.hull_snapshot_us=_hull_snapshot_us
 s.mesh_publish_us=_mesh_publish_us;s.max_mesh_publish_us=_mesh_max_publish_us
 s.mesh_commit_us=_mesh_commit_us;s.max_mesh_commit_us=_mesh_max_commit_us;s.staged_meshes=_staged_meshes.size()
 s.render_ready=_staged_meshes.is_empty() and s.dirty_meshes==0 and s.pending_regions==0 and not s.fill_active and _mesh_task<0 and not s.mesh_batch_active and not s.mesh_publish_pending
 return s
func descriptions() -> Array[Dictionary]:
 var rows:Array[Dictionary]=[]
 for item:Dictionary in _lakes.values():rows.append({"id":item.id,"state":"Preparing" if item.dirty else "Ready" if item.failure.is_empty() else "Failed","reason":item.failure,"level":item.level,"origin":item.origin})
 return rows
func retry_lake(id:int) -> bool:
 if not _lakes.has(id) or _lakes[id].dirty:return false
 if _lakes[id].failure.is_empty():return false
 _lakes[id].dirty=true;_lakes[id].failure="";return true

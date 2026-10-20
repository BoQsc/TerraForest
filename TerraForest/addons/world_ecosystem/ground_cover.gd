# SPDX-License-Identifier: 0BSD
extends Node3D
const Catalog=preload("res://addons/world_ecosystem/ground_catalog.gd")
const Tokens=preload("res://addons/volumetric_terrain/surface_tokens.gd")
var terrain: Node3D
var camera: Camera3D
var structures: Node3D
var water: Node3D
var seed: int=1703
var seed_source: Callable
var shelter_source: Callable
var picker: RefCounted
var native: RefCounted
var removed: RefCounted
var grass_material: ShaderMaterial
var grass_texture_enabled:=false
var foliage_materials:Array[ShaderMaterial]=[]
var batches: Array[Node3D]=[]
var resident: Dictionary={}
var _wanted: Dictionary={}
var _requests: Dictionary={}
var _pending: Dictionary={}
var _dirty: Dictionary={}
var _view_forward:=Vector3.ZERO
var _view_eye:=Vector3.ZERO
var _view_fov:float=-1.0
var _view_range:float=124.0
var _last_cell:=Vector2i(-999,-999)
var rejected_batches:=0
var _support_job: Dictionary={}
var _exclusion_revision:=0
var _scatter_job:Dictionary={}
var _resident_layers:Dictionary={}
func _layers(key:Vector2i)->int:
	# Maintain cover density through the full resident area; mesh LOD reduces cost.
	return 16

func prepare(persistence: RefCounted) -> bool:
	for addon in ["vegetation_runtime","structures"]:
		GDExtensionManager.load_extension("res://addons/%s/%s.gdextension"%[addon,addon])
	native=ClassDB.instantiate("NativeGroundCover")
	picker=ClassDB.instantiate("NativeGroundCoverPicker")
	removed=ClassDB.instantiate("NativeGroundCoverState")
	return persistence.register_component("ground_cover_edits_v1",removed.capture_storage_snapshot,_restore,removed,removed.capture_storage_snapshot())

func _restore(data: PackedByteArray) -> bool:
	if not removed.restore_storage_snapshot(data): return false
	reset()
	return true

func _ready() -> void:
	if native==null or terrain==null or camera==null:
		push_error("Ground cover requires prepared persistence, terrain and camera")
		set_process(false);return
	for species in range(Catalog.COUNT):
		var batch: Node3D=ClassDB.instantiate("NativeStaticBatch")
		add_child(batch)
		if not batch.configure_appearance_fade() or not batch.configure_asset("ground_cover/%d/v1"%species,_mesh(species)) or not batch.configure_render_streaming(true,maxf(144.0,Catalog.DISTANCES[species]),896 if species==2 else 192,7000000 if species==2 else (1600000 if species==1 else 200000),2,8192):
			push_error("Ground cover renderer initialization failed");set_process(false);return
		batch.set_casts_shadows(true)
		batch.set_shadow_distance(24.0 if species==2 else 48.0)
		batches.append(batch)
	if not set_grass_texture(true):push_warning("Grass detail unavailable; using untextured material")
	terrain.surface_batch_ready.connect(_surface_ready)
	terrain.density_batch_ready.connect(_density_ready)
	terrain.region_changed.connect(_terrain_changed)
	terrain.reload_started.connect(reset)
	if structures!=null: structures.vegetation_changed.connect(_exclusion_changed)
	if water!=null: water.exclusion_changed.connect(_exclusion_changed)

func _mesh(species: int) -> Mesh:
	var mesh:=preload("res://addons/world_ecosystem/woodland_mesh.gd").build(species)
	var material:ShaderMaterial=mesh.surface_get_material(0)
	material.set_shader_parameter("distance_fade_end",124.0)
	material.set_shader_parameter("distance_fade_start",100.0)
	foliage_materials.append(material)
	if species==2:grass_material=material
	return mesh

func set_grass_texture(enabled: bool) -> bool:
	if grass_material==null:return false
	if not preload("res://addons/world_ecosystem/woodland_mesh.gd").set_grass_detail(grass_material,enabled):return false
	grass_texture_enabled=enabled
	return true

func reset() -> void:
	var reset_begin:=Time.get_ticks_usec()
	# Reset each native collection once; cell-by-cell removal repeatedly rebuilds
	# the same 32m render groups during a whole-world reload.
	for batch:Node3D in batches:
		if not batch.clear_instances():push_error("Ground cover reset rejected native collection ownership");return
	for key in resident:picker.remove_cell(key)
	resident.clear();_wanted.clear();_dirty.clear();_pending.clear();_requests.clear();_support_job.clear()
	_scatter_job.clear();_resident_layers.clear()
	_last_cell=Vector2i(-999,-999)
	if terrain.has_method("_record_stage"):terrain._record_stage("reload ground cover",(Time.get_ticks_usec()-reset_begin)/1000.0)

func _retire(key: Vector2i) -> void:
	picker.remove_cell(key)
	for species in range(Catalog.COUNT):
		batches[species].remove_instances(resident[key][species].ids)

var last_process_us:int=0
func _process(_delta: float) -> void:
	var measured_begin:=Time.get_ticks_usec()
	_measured_step(_delta)
	last_process_us=Time.get_ticks_usec()-measured_begin

func _measured_step(_delta:float)->void:
	if not terrain.world_ready or terrain.stopping: return
	if seed_source.is_valid(): seed=seed_source.call()
	if not removed.bind_world(seed,1):
		push_error("Ground-cover save belongs to a different generation profile")
		set_process(false);return
	for material in foliage_materials:
		material.set_shader_parameter("cover_eye",camera.global_position)
		material.set_shader_parameter("cover_clock",Time.get_ticks_msec()/1000.0)
	for batch in batches: batch.set_render_focus(camera.global_position)
	var center:=Vector2i(floori(camera.global_position.x/32.0),floori(camera.global_position.z/32.0))
	var forward:Vector3=-camera.global_basis.z
	var zoomed:bool=camera.fov<71.0
	var view_changed:bool=absf(camera.fov-_view_fov)>0.5 or (zoomed and (forward.dot(_view_forward)<0.9975 or camera.global_position.distance_squared_to(_view_eye)>16.0))
	if center!=_last_cell or view_changed:
		_last_cell=center;_wanted.clear()
		_view_fov=camera.fov;_view_forward=forward;_view_eye=camera.global_position
		var viewport_size:Vector2=camera.get_viewport().get_visible_rect().size
		var view:Dictionary=native.wanted_view(_view_eye,forward,camera.fov,viewport_size.x/maxf(1.0,viewport_size.y))
		_view_range=view.range
		for key in view.cells: _wanted[key]=true
		for material in foliage_materials:
			material.set_shader_parameter("distance_fade_start",maxf(48.0,_view_range-24.0))
			material.set_shader_parameter("distance_fade_end",_view_range)
		for batch in batches:batch.set_render_radius(_view_range+20.0)
		# Invalidations also cover owners still awaiting first publication. They
		# have no resident entry to retire below; discard their obsolete work.
		for key in _dirty.keys():
			if not _wanted.has(key):_dirty.erase(key)
		for key in resident.keys():
			if not _wanted.has(key):
				_retire(key);resident.erase(key);_dirty.erase(key);_resident_layers.erase(key)
	for key in resident:
		if _resident_layers.get(key,1)!=_layers(key):_dirty[key]=true
	if terrain.pending_edit or _requests.size()>=1: return
	if not _support_job.is_empty():
		if not _support_job.waiting:
			_support_job.waiting=terrain.request_interpolated_density_batch(_support_job.points,_support_job.token)
		return
	if not _scatter_job.is_empty() and (not _wanted.has(_scatter_job.key) or _scatter_job.layers!=_layers(_scatter_job.key) or _scatter_job.revision!=terrain.published_revision or _scatter_job.exclusion!=_exclusion_revision):_scatter_job.clear()
	for key in _wanted:
		if not _scatter_job.is_empty() and _scatter_job.key!=key:continue
		if (resident.has(key) and not _dirty.has(key)) or _pending.has(key): continue
		if _scatter_job.is_empty():_scatter_job={"key":key,"layer":0,"next_layer":0,"layers":_layers(key),"revision":terrain.published_revision,"exclusion":_exclusion_revision,"packed":[],"shelter":shelter_source.call(key) if shelter_source.is_valid() else PackedVector3Array()}
		# Four existing 64-point jobs per wave; admission may accept fewer.
		# Keep one owner in flight and preserve terrain's foreground priority.
		for slot in 4:
			if _scatter_job.next_layer>=_scatter_job.layers:break
			var data: Dictionary=native.candidates(key,seed,_scatter_job.next_layer,_scatter_job.shelter)
			var token:=Tokens.allocate()
			if not terrain.request_surface_batch(data.points,token):break
			data.key=key;data.layer=_scatter_job.next_layer
			_requests[token]=data;_pending[key]=token
			_scatter_job.next_layer+=1
		break

func _surface_ready(token: int,points: PackedVector3Array,normals: PackedVector3Array,epoch: int,revision: int) -> void:
	if not _requests.has(token): return
	var request: Dictionary=_requests[token];_requests.erase(token)
	if _requests.is_empty():_pending.erase(request.key)
	if not _wanted.has(request.key) or epoch!=terrain.epoch or revision!=terrain.published_revision or terrain.pending_edit or _scatter_job.is_empty() or _scatter_job.exclusion!=_exclusion_revision:
		_scatter_job.clear();return
	var placed: Dictionary=native.place(request.ids,points,normals)
	if not placed.ok: rejected_batches+=1;_scatter_job.clear();return
	var mask: PackedByteArray=removed.mask(placed.ids)
	var structure_mask:=PackedByteArray();var water_mask:=PackedByteArray()
	if structures!=null: structure_mask=structures.overlap_mask(placed.transforms,AABB(Vector3(-0.4,0,-0.4),Vector3(0.8,0.8,0.8)))
	if water!=null: water_mask=water.placement_mask(placed.transforms)
	if (structures!=null and structure_mask.size()!=mask.size()) or (water!=null and water_mask.size()!=mask.size()):
		rejected_batches+=1;_scatter_job.clear();return
	# Only this bounded 64-candidate owner is combined in scene glue.
	for i in range(mask.size()):
		if (structures!=null and structure_mask[i]) or (water!=null and water_mask[i]): mask[i]=1
	var packed: Array=native.pack(placed.ids,placed.transforms,mask,_scatter_job.shelter)
	if packed.size()!=Catalog.COUNT: rejected_batches+=1;_scatter_job.clear();return
	# Replies may arrive in any order; concatenate by original layer for stable IDs.
	if _scatter_job.packed.is_empty():_scatter_job.packed.resize(_scatter_job.layers)
	_scatter_job.packed[request.layer]=packed
	_scatter_job.layer+=1
	if _scatter_job.layer<_scatter_job.layers:return
	packed=_scatter_job.packed[0]
	for layer in range(1,_scatter_job.layers):
		for species in Catalog.COUNT:
			packed[species].ids.append_array(_scatter_job.packed[layer][species].ids)
			packed[species].transforms.append_array(_scatter_job.packed[layer][species].transforms)
	_resident_layers[request.key]=_scatter_job.layers
	_scatter_job.clear()
	var authored_poses: Array[Transform3D]=removed.sample_transforms(request.key)
	if authored_poses.is_empty():
		_publish(request.key,packed,authored_poses,PackedByteArray());return
	_support_job={"key":request.key,"packed":packed,"poses":authored_poses,"points":removed.support_points(request.key),"token":Tokens.allocate(),"waiting":false,"epoch":epoch,"revision":revision,"density_revision":terrain.density_revision,"exclusion_revision":_exclusion_revision}
	_pending[request.key]=-1

func _density_ready(result: Dictionary) -> void:
	if _support_job.is_empty() or result.token!=_support_job.token: return
	var job:=_support_job;_support_job={};_pending.erase(job.key)
	if job.exclusion_revision!=_exclusion_revision or not _wanted.has(job.key) or result.status!="ok" or result.epoch!=terrain.epoch or job.epoch!=terrain.epoch or result.revision!=job.density_revision or terrain.density_revision!=job.density_revision or terrain.published_revision!=job.revision or terrain.pending_edit: return
	var structure_support:=PackedByteArray();structure_support.resize(job.poses.size())
	if structures!=null:
		var probes: Array[Transform3D]=[]
		for pose: Transform3D in job.poses: probes.append(Transform3D(Basis.IDENTITY,pose.origin-Vector3.UP*0.05))
		structure_support=structures.overlap_mask(probes,AABB(Vector3.ONE*-0.03,Vector3.ONE*0.06))
	var unsupported: PackedByteArray=removed.support_mask(result.values,structure_support)
	if unsupported.size()!=job.poses.size(): rejected_batches+=1;return
	_publish(job.key,job.packed,job.poses,unsupported)

func _publish(key: Vector2i,packed: Array,authored_poses: Array[Transform3D],unsupported: PackedByteArray) -> void:
	var authored_blocked:=PackedByteArray();authored_blocked.resize(authored_poses.size())
	var authored_water:=PackedByteArray();authored_water.resize(authored_poses.size())
	if structures!=null: authored_blocked=structures.overlap_mask(authored_poses,AABB(Vector3(-0.4,0,-0.4),Vector3(0.8,0.8,0.8)))
	if water!=null: authored_water=water.placement_mask(authored_poses)
	if authored_blocked.size()!=unsupported.size(): rejected_batches+=1;return
	for i in range(unsupported.size()):
		if unsupported[i]: authored_blocked[i]=1
	var authored: Array=removed.query_filtered(key,authored_blocked,authored_water)
	if authored.size()!=Catalog.COUNT: rejected_batches+=1;return
	for species in range(Catalog.COUNT):
		packed[species].ids.append_array(authored[species].ids)
		packed[species].transforms.append_array(authored[species].transforms)
	# Check the taller species separately; existing low cover keeps its old bounds.
	if structures!=null and not packed[8].ids.is_empty():
		var poses: Array[Transform3D]=[]
		var values: PackedFloat32Array=packed[8].transforms
		for i in packed[8].ids.size():
			var j: int=i*12
			poses.append(Transform3D(Basis(Vector3(values[j],values[j+4],values[j+8]),Vector3(values[j+1],values[j+5],values[j+9]),Vector3(values[j+2],values[j+6],values[j+10])),Vector3(values[j+3],values[j+7],values[j+11])))
		var tall_mask: PackedByteArray=structures.overlap_mask(poses,AABB(Vector3(-0.4,0,-0.4),Vector3(0.8,1.1,0.8)))
		if tall_mask.size()!=poses.size():rejected_batches+=1;return
		for i in range(tall_mask.size()-1,-1,-1):
			if tall_mask[i]:
				packed[8].ids.remove_at(i)
				packed[8].transforms=packed[8].transforms.slice(0,i*12)+packed[8].transforms.slice((i+1)*12)
	if resident.get(key,[])==packed: _dirty.erase(key);return
	var previous: Array=resident.get(key,[])
	if not picker.replace_cell(key,packed): rejected_batches+=1;return
	for species in range(Catalog.COUNT):
		if not batches[species].upsert_instances(packed[species].ids,packed[species].transforms):
			# Restore interaction and all collections if any publication fails.
			if previous.is_empty(): picker.remove_cell(key)
			else: picker.replace_cell(key,previous)
			for rollback in range(Catalog.COUNT):
				batches[rollback].remove_instances(packed[rollback].ids)
				if not previous.is_empty(): batches[rollback].upsert_instances(previous[rollback].ids,previous[rollback].transforms)
			rejected_batches+=1;return
	if not previous.is_empty():
		for species in range(Catalog.COUNT):
			var retired:=PackedInt64Array()
			for id in previous[species].ids:
				if not packed[species].ids.has(id): retired.append(id)
			batches[species].remove_instances(retired)
	resident[key]=packed;_dirty.erase(key)

func _terrain_changed(bounds: AABB,_revision: int) -> void: _exclusion_changed(bounds)
func _exclusion_changed(bounds: AABB) -> void:
	for key: Vector2i in _wanted:
		var owner:=AABB(Vector3(key.x*32,bounds.position.y,key.y*32),Vector3(32,maxf(1,bounds.size.y),32)).grow(8.0)
		if bounds.size==Vector3.ZERO or owner.intersects(bounds):
			_dirty[key]=true;_exclusion_revision+=1

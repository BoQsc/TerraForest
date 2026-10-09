extends Node
signal harvested
## Optional coordinator; neither rendering addon imports this module.
## Candidate IDs and transforms depend only on world seed and cell, never visit order.
const CELL_SIZE: float = 64.0
const GRID: int = 6
@export var terrain: Node3D
@export var vegetation: Node3D
@export var camera: Camera3D
@export var structures: Node3D
@export var water: Node3D
@export var seed: int = 1703
@export_range(64.0, 768.0, 64.0) var stream_radius: float = 384.0
@export_range(9, 625, 1) var max_resident_cells: int = 169
@export_range(0.0, 1.0, 0.05) var density: float = 0.82
@export_range(0.0, 60.0, 1.0) var max_slope_degrees: float = 32.0
var resident: Dictionary = {}
var _wanted: Dictionary = {}
var _requests: Dictionary = {}
var _pending_cells: Dictionary = {}
const SurfaceTokens=preload("res://addons/volumetric_terrain/surface_tokens.gd")
var _token: int = 0
var _scan_timer: float = 0.0
var _last_cell := Vector2i(-9999, -9999)
var _connected: bool = false
var stale_results: int = 0
var rejected_batches: int = 0
var _samples: Dictionary = {}
var _reconcile: Dictionary = {}
var _resample: Dictionary = {}
var last_process_us: int = 0
var harvest_state: RefCounted
var _harvesting:=false
var _native_scatter: RefCounted

func harvest_root(id: int, inventory: RefCounted) -> Dictionary:
	if terrain!=null and (not terrain.world_ready or terrain.pending_edit or terrain.closing or terrain.stopping):
		return {"ok":false,"reason":"World updating; try again"}
	if _harvesting or harvest_state==null or vegetation==null or not vegetation.renderer.roots.has(id) or harvest_state.contains(id):
		return {"ok":false,"reason":"Tree unavailable"}
	# Current generator has exactly 36 stable IDs per owner. Never accept an
	# unrelated authored vegetation ID into this generator's harvest state.
	if id<1 or id>32*32*GRID*GRID: return {"ok":false,"reason":"Tree unavailable"}
	var owner_index: int=(id-1)/(GRID*GRID)
	var key:=Vector2i(owner_index%32,owner_index/32)
	if not _samples.has(key) or not _samples[key].active.has(id): return {"ok":false,"reason":"Tree unavailable"}
	if _resample.has(key) or _pending_cells.has(key) or _reconcile.has(key):
		return {"ok":false,"reason":"Vegetation updating; try again"}
	var before: Dictionary=inventory.snapshot()
	var wood:=PackedInt64Array([102,4])
	if not inventory.can_receive(wood,before.revision).ok: return {"ok":false,"reason":"Make room for 4 wood"}
	_harvesting=true
	if not harvest_state.mark(id):
		_harvesting=false;return {"ok":false,"reason":"Harvest storage full"}
	var grant: Dictionary=inventory.grant_items(wood,before.revision)
	if not grant.ok:
		harvest_state.unmark(id);_harvesting=false
		return {"ok":false,"reason":"Inventory changed; try again"}
	if not vegetation.remove_root(id):
		harvest_state.unmark(id)
		if not inventory.restore(before,grant.revision).ok: push_error("Harvest inventory rollback failed")
		_harvesting=false;return {"ok":false,"reason":"Tree removal failed"}
	_reconcile[key]=true
	# Observers see the exclusion, inventory grant and removal together.
	harvested.emit()
	_harvesting=false
	return {"ok":true,"reason":"Harvested 4 wood"}

func prepare_persistence(persistence: RefCounted) -> bool:
	if harvest_state!=null: return false
	if not ClassDB.class_exists("NativeHarvestState"):
		GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
	if not ClassDB.class_exists("NativeHarvestState"): return false
	harvest_state=ClassDB.instantiate("NativeHarvestState")
	return persistence.register_component("harvested_trees",harvest_state.capture_storage_snapshot,_restore_harvest,harvest_state,harvest_state.capture_storage_snapshot())

func _restore_harvest(data: PackedByteArray) -> bool:
	if not harvest_state.restore_storage_snapshot(data): return false
	_structures_changed()
	return true

func _ready() -> void:
	if terrain == null or vegetation == null or camera == null:
		push_error("WorldEcosystem requires terrain, vegetation and camera")
		set_process(false)
		return
	terrain.surface_batch_ready.connect(_surface_ready)
	terrain.region_changed.connect(_region_changed)
	terrain.reload_started.connect(reset)
	if structures != null:
		structures.vegetation_changed.connect(_structure_region_changed)
	if water!=null: water.exclusion_changed.connect(_water_changed)
	_connected = true

func _cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / CELL_SIZE), floori(point.z / CELL_SIZE))

func _owner(key: Vector2i) -> String:
	return "natural/%d/%d" % [key.x, key.y]

func reset() -> void:
	for key in resident:
		vegetation.remove_chunk(_owner(key))
	resident.clear()
	_samples.clear()
	_reconcile.clear()
	_resample.clear()
	_requests.clear()
	_pending_cells.clear()
	_wanted.clear()
	_last_cell = Vector2i(-9999, -9999)

func _process(delta: float) -> void:
	var begin:=Time.get_ticks_usec()
	_step(delta)
	last_process_us=Time.get_ticks_usec()-begin

func _step(delta: float) -> void:
	if not terrain.world_ready or not vegetation.ready_to_render:
		return
	# Coalesce edits; reconcile at most one 36-candidate owner per frame.
	if not terrain.pending_edit and not _reconcile.is_empty():
		var key: Vector2i = _reconcile.keys()[0]
		_reconcile.erase(key)
		if _samples.has(key) and _wanted.has(key):
			_publish_samples(key)
	_scan_timer -= delta
	var cell: Vector2i = _cell(camera.global_position)
	if cell != _last_cell or _scan_timer <= 0.0:
		_scan_timer = 0.5
		_last_cell = cell
		_refresh(cell)
	if terrain.pending_edit or _requests.size() >= 2:
		return
	# One small batch submitted per frame. Queue admission is owned by TerrainWorld.
	for key in _wanted:
		if (resident.has(key) and not _resample.has(key)) or _pending_cells.has(key):
			continue
		if not resident.has(key) and resident.size()+_requests.size()>=max_resident_cells:
			continue
		var candidates: Dictionary = _candidates(key)
		if candidates["points"].is_empty():
			var empty_transforms: Array[Transform3D]=[]
			_replace_samples(key,PackedInt64Array(),empty_transforms)
			break # Empty owners consume the same per-frame generation budget.
		_token = SurfaceTokens.allocate()
		if terrain.request_surface_batch(candidates["points"], _token):
			candidates["key"] = key
			_requests[_token] = candidates
			_pending_cells[key] = _token
		break

func _refresh(center: Vector2i) -> void:
	var candidates: Array[Vector2i] = _scatter().wanted_cells(center, stream_radius, max_resident_cells)
	_wanted.clear()
	for key in candidates:
		_wanted[key] = true
	for key in resident.keys():
		if not _wanted.has(key):
			vegetation.remove_chunk(_owner(key))
			resident.erase(key)
	# Failed publication has samples but no resident owner; evict those too.
	for key in _samples.keys():
		if not _wanted.has(key):
			_samples.erase(key)
			_reconcile.erase(key)
			_resample.erase(key)
	# Keep outstanding tokens until completion; this bounds work during teleports.
	for key in _resample.keys():
		if not _wanted.has(key):
			_resample.erase(key)

func _candidates(key: Vector2i) -> Dictionary:
	return _scatter().candidates(key,seed,density)

func _scatter() -> RefCounted:
	if _native_scatter==null:
		if not ClassDB.class_exists("NativeVegetationScatter"):
			GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
		_native_scatter=ClassDB.instantiate("NativeVegetationScatter")
	return _native_scatter

func _surface_ready(token: int, points: PackedVector3Array, normals: PackedVector3Array, epoch_id: int, revision: int) -> void:
	if not _requests.has(token):
		stale_results += 1
		return
	var request: Dictionary = _requests[token]
	_requests.erase(token)
	var key: Vector2i = request["key"]
	_pending_cells.erase(key)
	if not _wanted.has(key) or epoch_id != terrain.epoch or revision != terrain.published_revision or terrain.pending_edit:
		stale_results += 1
		return
	var placed: Dictionary=_scatter().place_surface(request["ids"],points,normals,request["rotations"],request["scales"],cos(deg_to_rad(max_slope_degrees)))
	if not placed.ok:
		rejected_batches += 1
		return
	_replace_samples(key,placed.ids,placed.transforms)

func _replace_samples(key: Vector2i,ids: PackedInt64Array,transforms: Array[Transform3D]) -> void:
	# Empty results must retire previously accepted roots as well as their cache.
	var previous: Dictionary = _samples.get(key, {})
	_samples[key] = {"ids": ids, "transforms": transforms, "active": previous.get("active", PackedInt64Array()), "active_transforms": previous.get("active_transforms", []), "published": previous.get("published", false)}
	_resample.erase(key)
	_publish_samples(key)

func _structures_changed() -> void:
	for key in _samples:
		if _samples[key].transforms.is_empty(): continue
		_reconcile[key] = true

func _structure_region_changed(bounds: AABB) -> void:
	if bounds.size==Vector3.ZERO:
		_structures_changed();return
	for key in _samples:
		var sample: Dictionary=_samples[key]
		if sample.transforms.is_empty(): continue
		if not sample.has("exclusion_bounds") or sample.exclusion_bounds.intersects(bounds):
			_reconcile[key]=true

func _water_changed(bounds: AABB) -> void:
	for key: Vector2i in _samples:
		if _samples[key].transforms.is_empty(): continue
		var footprint:=AABB(Vector3(key.x*CELL_SIZE,bounds.position.y,key.y*CELL_SIZE),Vector3(CELL_SIZE,maxf(bounds.size.y,1.0),CELL_SIZE))
		if footprint.intersects(bounds): _reconcile[key]=true

func _publish_samples(key: Vector2i) -> void:
	var sample: Dictionary = _samples[key]
	var transforms: Array[Transform3D] = sample["transforms"]
	if structures!=null and not sample.has("exclusion_bounds") and not transforms.is_empty():
		var prototype: AABB=vegetation.placement_bounds()
		var bounds: AABB=transforms[0]*prototype
		for i in range(1,transforms.size()): bounds=bounds.merge(transforms[i]*prototype)
		sample["exclusion_bounds"]=bounds
	var mask := PackedByteArray()
	if structures != null and not transforms.is_empty():
		mask = structures.overlap_mask(transforms, vegetation.placement_bounds())
		if mask.size() != transforms.size():
			rejected_batches += 1
			_reconcile[key] = true
			return
	var ids := PackedInt64Array()
	var water_mask:=PackedByteArray()
	if water!=null and not transforms.is_empty():
		water_mask=water.placement_mask(transforms)
		if water_mask.size()!=transforms.size():
			rejected_batches+=1;_reconcile[key]=true;return
	var accepted: Array[Transform3D] = []
	var harvested:=PackedByteArray()
	if harvest_state!=null:
		harvested=harvest_state.mask(sample["ids"])
		if harvested.size()!=transforms.size():
			rejected_batches+=1;_reconcile[key]=true;return
	for i in range(transforms.size()):
		if harvest_state!=null and harvested[i]!=0: continue
		if (structures == null or mask[i] == 0) and (water==null or water_mask[i]==0):
			ids.append(sample["ids"][i])
			accepted.append(transforms[i])
	# Stable IDs survive terrain edits; support heights can still change.
	# Compare the accepted transforms too, then let the renderer preserve each
	# unchanged row and its LOD/fade state during an actual owner update.
	if sample["published"] and ids == sample["active"] and accepted == sample.get("active_transforms", []):
		_reconcile.erase(key)
		return
	if vegetation.upsert_chunk(_owner(key), ids, accepted):
		sample["active"] = ids
		sample["active_transforms"] = accepted
		sample["published"] = true
		resident[key] = true
		_reconcile.erase(key)
	else:
		rejected_batches += 1
		_reconcile[key] = true

func _region_changed(bounds: AABB, _revision: int) -> void:
	# Preserve live rows until authoritative support samples arrive. Only owners
	# intersecting the footprint need revalidation, including underground edits.
	for key in _wanted:
		var low := Vector3(key.x * CELL_SIZE, bounds.position.y, key.y * CELL_SIZE)
		var footprint := AABB(low, Vector3(CELL_SIZE, maxf(bounds.size.y, 1.0), CELL_SIZE))
		if footprint.intersects(bounds):
			_resample[key] = true

func _exit_tree() -> void:
	if is_instance_valid(water) and water.exclusion_changed.is_connected(_water_changed):
		water.exclusion_changed.disconnect(_water_changed)
	if is_instance_valid(structures) and structures.vegetation_changed.is_connected(_structure_region_changed):
		structures.vegetation_changed.disconnect(_structure_region_changed)
	if _connected and is_instance_valid(terrain):
		terrain.surface_batch_ready.disconnect(_surface_ready)
		terrain.region_changed.disconnect(_region_changed)
		terrain.reload_started.disconnect(reset)

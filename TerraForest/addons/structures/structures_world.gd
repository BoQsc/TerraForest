extends Node3D
signal changed
signal vegetation_changed(bounds: AABB)
var _block_change_bounds:=AABB()
## Scene/persistence integration only. Storage, validation and rendering are native.
var blocks: Node3D
var _models: Dictionary = {}
var _empty_models: Dictionary = {}
var _empty_blocks := PackedByteArray()
var _codec: RefCounted
var _queries: RefCounted
var _sealed := false
var _dirty := true
var _cached_snapshot := PackedByteArray()
var _cached_storage := PackedByteArray()
var _storage_checkpoint := PackedByteArray()
var _model_checkpoints: Dictionary = {}
var _pager: RefCounted

func enable_region_paging(archive: RefCounted, load_radius: float = 384, unload_radius: float = 512, chunk_limit: int = 1536) -> bool:
	if _pager != null:
		return true
	if not seal():
		return false
	var pager: RefCounted = ClassDB.instantiate("NativeBlockPager")
	if not pager.configure(blocks,archive,load_radius,unload_radius,chunk_limit):
		return false
	_pager = pager
	return true

func step_region_paging(world_focus: Vector3) -> bool:
	if _pager == null:
		return false
	var ok: bool = _pager.step(world_focus,_storage_checkpoint)
	if not ok:
		return false
	var checkpoint: PackedByteArray = _pager.get_checkpoint()
	if checkpoint != _storage_checkpoint:
		_storage_checkpoint = checkpoint
		_cached_storage = PackedByteArray()
	return ok

func region_paging_stats() -> Dictionary:
	return _pager.stats() if _pager != null else {"active":false}

func stop_region_paging() -> void:
	if _pager != null:
		_pager.stop()
		_pager = null

func _exit_tree() -> void:
	stop_region_paging()

func _mark_dirty() -> void:
	_dirty = true
	_cached_storage = PackedByteArray()
	var bounds:=_block_change_bounds;_block_change_bounds=AABB()
	vegetation_changed.emit(bounds)
	changed.emit()

func _block_cells_changed(bounds: AABB) -> void:
	_block_change_bounds=blocks.global_transform*bounds

func _exclusion_changed() -> void:
	vegetation_changed.emit(AABB())
	changed.emit()

func overlap_mask(transforms: Array[Transform3D], bounds: AABB) -> PackedByteArray:
	if not prepare():
		return PackedByteArray()
	return _queries.overlap_mask(blocks,_models.values(),transforms,bounds)

func prepare() -> bool:
	if blocks != null:
		return true
	if not ClassDB.class_exists("NativeStructuresSnapshot"):
		if GDExtensionManager.load_extension("res://addons/structures/structures.gdextension") != OK:
			return false
	blocks = ClassDB.instantiate("NativeBlockWorld")
	if not preload("res://addons/structures/material_startup.gd").prepare(blocks):
		blocks.free();blocks=null;return false
	blocks.name = "Blocks"
	add_child(blocks)
	blocks.changed.connect(_mark_dirty)
	blocks.cells_changed.connect(_block_cells_changed)
	_empty_blocks = blocks.capture_snapshot()
	_codec = ClassDB.instantiate("NativeStructuresSnapshot")
	_queries = ClassDB.instantiate("NativeStructureQueries")
	return true

func register_model(asset_id: String, mesh: Mesh) -> Node3D:
	if _sealed or _models.has(asset_id) or _models.size() >= 256 or not prepare():
		return null
	var collection: Node3D = ClassDB.instantiate("NativeStaticBatch")
	if not collection.configure_asset(asset_id,mesh):
		collection.free()
		return null
	collection.lock_asset_identity()
	collection.configure_render_streaming(true,384,128,4*1024*1024,2,256*1024)
	_models[asset_id] = collection
	_empty_models[asset_id] = collection.capture_snapshot()
	add_child(collection)
	collection.changed.connect(_mark_dirty)
	collection.exclusion_changed.connect(_exclusion_changed)
	return collection

func model(asset_id: String) -> Node3D:
	return _models.get(asset_id)

func is_collision_region_ready(bounds: AABB) -> bool:
	return blocks != null and _queries.is_collision_region_ready(blocks,_models.values(),bounds)

func seal() -> bool:
	if _sealed:
		return true
	if not prepare() or not _codec.configure_assets(PackedStringArray(_models.keys())):
		return false
	_sealed = true
	return true

func snapshot_validator() -> RefCounted:
	return _codec if seal() else null

func empty_snapshot() -> PackedByteArray:
	return _codec.encode(_empty_blocks,_empty_models) if seal() else PackedByteArray()

func capture_snapshot() -> PackedByteArray:
	if not seal():
		return PackedByteArray()
	if not _dirty:
		return _cached_snapshot.duplicate()
	var block_bytes: PackedByteArray = blocks.capture_snapshot()
	var byte_count := 48+block_bytes.size()
	var models: Dictionary = {}
	for id: String in _models:
		var bytes: PackedByteArray = _models[id].capture_snapshot()
		byte_count += 4+bytes.size()
		if bytes.is_empty() or byte_count > 64*1024*1024:
			return PackedByteArray()
		models[id] = bytes
	_cached_snapshot = _codec.encode(block_bytes,models)
	_dirty = _cached_snapshot.is_empty()
	return _cached_snapshot.duplicate()

func capture_storage_snapshot() -> PackedByteArray:
	if not seal():
		return PackedByteArray()
	# Retain the ordinary bundle for fully resident worlds and legacy consumers.
	var fully_resident: bool=blocks.region_stats().whole_snapshot_available
	for collection: Node3D in _models.values():
		fully_resident=fully_resident and collection.region_stats().unloaded_regions==0
	if fully_resident:
		return capture_snapshot()
	if not _cached_storage.is_empty():
		return _cached_storage.duplicate()
	var state: Dictionary = blocks.capture_storage_state()
	var models: Dictionary = {}
	var byte_count: int = 56+_storage_checkpoint.size()+state.resident.size()+state.unavailable_keys.size()/3*44
	for id: String in _models:
		var bytes: PackedByteArray = _models[id].capture_snapshot()
		if _models[id].region_stats().unloaded_regions>0:
			var model_state: Dictionary=_models[id].capture_storage_state()
			bytes=_codec.encode_model_storage(model_state.resident,model_state.unavailable_keys,model_state.unavailable_checksums)
		byte_count += 4+bytes.size()
		if bytes.is_empty() or byte_count > 64*1024*1024:
			return PackedByteArray()
		models[id] = bytes
	_cached_storage = _codec.encode_storage(state.resident,state.unavailable_keys,state.unavailable_checksums,models,_storage_checkpoint)
	return _cached_storage.duplicate()

func restore_storage_snapshot(bytes: PackedByteArray) -> bool:
	if not seal():
		return false
	if _codec.validate_snapshot(bytes):
		return restore_snapshot(bytes)
	var bootstrap: Dictionary = _codec.decode_bootstrap(bytes)
	if bootstrap.get("ok",false):
		var previous: Array=[_storage_checkpoint,_model_checkpoints,_cached_storage,_cached_snapshot,_dirty]
		_storage_checkpoint = bootstrap.checkpoint
		_model_checkpoints = {}
		for id: String in bootstrap.models:
			_model_checkpoints[id] = bootstrap.models[id].slice(16,48)
		_cached_storage = PackedByteArray()
		_cached_snapshot = PackedByteArray()
		_dirty = true
		if not _codec.restore_bootstrap(bytes,blocks,_models):
			_storage_checkpoint=previous[0];_model_checkpoints=previous[1]
			_cached_storage=previous[2];_cached_snapshot=previous[3];_dirty=previous[4]
			return false
		return true
	var decoded: Dictionary = _codec.decode_storage(bytes)
	if not decoded.get("ok",false):
		return false
	# Save envelopes with partial models must first resolve through the archive.
	# Reject before mutating blocks or any other model collection.
	for id: String in _models:
		if not _models[id].validate_snapshot(decoded.models.get(id,_empty_models[id])):
			return false
	# Native replacement validates both maps before changing either of them.
	if not blocks.restore_storage_state(decoded.resident,decoded.unavailable_keys,decoded.unavailable_checksums):
		return false
	for id: String in _models:
		if not _models[id].restore_snapshot(decoded.models.get(id,_empty_models[id])):
			return false
	_model_checkpoints.clear()
	_storage_checkpoint = decoded.checkpoint
	_cached_storage = bytes.duplicate()
	_cached_snapshot = PackedByteArray()
	_dirty = true
	return true

func restore_snapshot(bytes: PackedByteArray) -> bool:
	if not seal():
		return false
	var decoded: Dictionary = _codec.decode(bytes)
	if not decoded.get("ok",false):
		return false
	# Every byte payload and every asset binding was validated before any mutation.
	# Model identities are locked at registration; missing newly added assets restore empty.
	if not blocks.restore_snapshot(decoded.blocks):
		return false
	for id: String in _models:
		if not _models[id].restore_snapshot(decoded.models.get(id,_empty_models[id])):
			return false
	_cached_storage = PackedByteArray()
	_model_checkpoints.clear()
	_storage_checkpoint = PackedByteArray()
	_cached_snapshot = bytes.duplicate()
	_dirty = false
	return true

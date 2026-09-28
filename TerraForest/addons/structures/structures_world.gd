extends Node3D
signal changed
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

func _mark_dirty() -> void:
	_dirty = true
	changed.emit()

func _exclusion_changed() -> void:
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
	blocks.name = "Blocks"
	add_child(blocks)
	blocks.changed.connect(_mark_dirty)
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
	_cached_snapshot = bytes.duplicate()
	_dirty = false
	return true

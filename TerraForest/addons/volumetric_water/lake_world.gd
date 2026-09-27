extends Node3D
## Thin scene/worker orchestration. Density sampling, flood fill, mesh generation
## and occupancy queries are C++. One bounded worker slice is outstanding.
signal lake_ready(id: int)
signal lake_failed(id: int, status: int)
@export var terrain: Node3D
@export_range(1, 16) var max_lakes: int = 8
const WaterShader = preload("res://addons/volumetric_water/water.gdshader")
var _lakes: Dictionary = {}
var _next_id: int = 1
var _token: int = 0
var _busy_id: int = 0
var _epoch: int = -1
var _material := ShaderMaterial.new()
var _available: bool = false
var _catalog: RefCounted
var _discard_completion: bool = false

func prepare() -> bool:
	if not ClassDB.class_exists("NativeLakeCatalog"):
		GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
	_available = ClassDB.class_exists("NativeLakeVolume") and ClassDB.class_exists("NativeLakeCatalog")
	if _available and _catalog == null:
		_catalog = ClassDB.instantiate("NativeLakeCatalog")
	return _available

func snapshot_validator() -> RefCounted:
	return _catalog

func empty_snapshot() -> PackedByteArray:
	return _catalog.encode([])

func capture_snapshot() -> PackedByteArray:
	var records: Array = []
	var ids: Array = _lakes.keys()
	ids.sort()
	for id: int in ids:
		var item: Dictionary = _lakes[id]
		records.append({"id": id, "origin": item["origin"], "cells": item["cells"], "spacing": item["spacing"], "level": item["level"], "seed": item["seed"]})
	return _catalog.encode(records, _next_id)

func restore_snapshot(bytes: PackedByteArray) -> bool:
	var parsed: Dictionary = _catalog.decode(bytes)
	if not parsed.get("ok", false):
		return false
	# Validate every record before removing any current scene state.
	var prepared: Array = []
	for record: Dictionary in parsed["records"]:
		var builder: RefCounted = ClassDB.instantiate("NativeLakeVolume")
		if not builder.configure(record["origin"], record["cells"], record["spacing"], record["level"], record["seed"]):
			return false
		prepared.append(builder)
	clear()
	max_lakes = maxi(max_lakes, prepared.size())
	_next_id = parsed["next_id"]
	for i in range(prepared.size()):
		var record: Dictionary = parsed["records"][i]
		var id: int = record["id"]
		_next_id = maxi(_next_id, id+1)
		_install_lake(id, record["origin"], record["cells"], record["spacing"], record["level"], record["seed"], prepared[i])
	return true

func _ready() -> void:
	if terrain == null or transform != Transform3D.IDENTITY or global_transform != Transform3D.IDENTITY:
		push_error("LakeWorld requires terrain and an identity world transform")
		set_process(false)
		return
	prepare()
	_material.shader = WaterShader
	terrain.lake_slice_ready.connect(_slice_ready)
	terrain.region_invalidated.connect(_invalidate)
	_epoch = terrain.epoch

func add_lake(origin: Vector3, cells: Vector3i, spacing: float, level: float, seed: Vector3) -> int:
	if not _available or _lakes.size() >= mini(max_lakes, 16) or _next_id>9007199254740991:
		return 0
	var builder: RefCounted = ClassDB.instantiate("NativeLakeVolume")
	if not builder.configure(origin, cells, spacing, level, seed):
		return 0
	var id: int = _next_id
	_next_id += 1
	_install_lake(id, origin, cells, spacing, level, seed, builder)
	return id

func _install_lake(id: int, origin: Vector3, cells: Vector3i, spacing: float, level: float, seed: Vector3, builder: RefCounted) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Lake_%d" % id
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.material_override = _material
	add_child(mesh)
	_lakes[id] = {"origin": origin, "cells": cells, "spacing": spacing, "level": level, "seed": seed,
		"bounds": builder.bounds(), "builder": builder, "volume": null, "mesh": mesh,
		"dirty": true, "revision": -1}

func remove_lake(id: int) -> void:
	if not _lakes.has(id):
		return
	if id == _busy_id:
		_discard_completion = true
	_lakes[id]["mesh"].queue_free()
	_lakes.erase(id)

func clear() -> void:
	for id: int in _lakes.keys():
		remove_lake(id)

func _invalidate(bounds: AABB) -> void:
	for item: Dictionary in _lakes.values():
		if item["bounds"].intersects(bounds):
			item["volume"] = null
			item["mesh"].mesh = null
			item["builder"] = null
			item["dirty"] = true

func _process(_delta: float) -> void:
	if not _available or not is_instance_valid(terrain):
		return
	if _epoch != terrain.epoch:
		_epoch = terrain.epoch
		for item: Dictionary in _lakes.values():
			item["volume"] = null
			item["mesh"].mesh = null
			item["builder"] = null
			item["dirty"] = true
	if _busy_id != 0 or not terrain.world_ready or terrain.pending_edit:
		return
	for id: int in _lakes:
		var item: Dictionary = _lakes[id]
		if not item["dirty"]:
			continue
		if item["builder"] == null or item["revision"] != terrain.published_revision:
			var builder: RefCounted = ClassDB.instantiate("NativeLakeVolume")
			if not builder.configure(item["origin"], item["cells"], item["spacing"], item["level"], item["seed"]):
				item["dirty"] = false
				lake_failed.emit(id, -1)
				return
			item["builder"] = builder
			item["revision"] = terrain.published_revision
		_token = item["builder"].get_instance_id()
		if terrain.request_lake_slice(item["builder"], _token):
			_busy_id = id
		return

func _slice_ready(token: int, status: int, epoch_id: int, revision: int) -> void:
	if token != _token or _busy_id == 0:
		return
	var id: int = _busy_id
	_busy_id = 0
	if _discard_completion:
		_discard_completion = false
		return
	if not _lakes.has(id):
		return
	var item: Dictionary = _lakes[id]
	if item["builder"] == null or epoch_id != terrain.epoch or revision != terrain.published_revision or terrain.pending_edit or status == -4:
		item["builder"] = null
		return
	if status == 0:
		return
	item["dirty"] = false
	if status != 1:
		item["builder"] = null
		lake_failed.emit(id, status)
		return
	item["volume"] = item["builder"]
	item["builder"] = null
	var arrays: Array = item["volume"].surface_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if not vertices.is_empty():
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		item["mesh"].mesh = mesh
	lake_ready.emit(id)

func depth_at(point: Vector3) -> float:
	if not is_instance_valid(terrain) or _epoch != terrain.epoch:
		return 0.0
	var depth: float = 0.0
	for item: Dictionary in _lakes.values():
		if item["volume"] != null and item["bounds"].has_point(point):
			depth = maxf(depth, item["volume"].depth_at(point))
	return depth

func statistics() -> Dictionary:
	var ready: int = 0
	var bytes: int = 0
	for item: Dictionary in _lakes.values():
		if item["volume"] != null:
			ready += 1
			bytes += int(item["volume"].statistics()["resident_bytes"])
	return {"lakes": _lakes.size(), "ready": ready, "resident_occupancy_bytes": bytes, "outstanding_slices": 1 if _busy_id != 0 else 0}

func _exit_tree() -> void:
	if is_instance_valid(terrain):
		if terrain.lake_slice_ready.is_connected(_slice_ready):
			terrain.lake_slice_ready.disconnect(_slice_ready)
		if terrain.region_invalidated.is_connected(_invalidate):
			terrain.region_invalidated.disconnect(_invalidate)

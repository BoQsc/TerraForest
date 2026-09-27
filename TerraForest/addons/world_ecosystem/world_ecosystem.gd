extends Node
## Optional coordinator; neither rendering addon imports this module.
## Candidate IDs and transforms depend only on world seed and cell, never visit order.
const CELL_SIZE: float = 64.0
const GRID: int = 6
@export var terrain: Node3D
@export var vegetation: Node3D
@export var camera: Camera3D
@export var seed: int = 1703
@export_range(64.0, 768.0, 64.0) var stream_radius: float = 384.0
@export_range(9, 625, 1) var max_resident_cells: int = 169
@export_range(0.0, 1.0, 0.05) var density: float = 0.82
@export_range(0.0, 60.0, 1.0) var max_slope_degrees: float = 32.0
var resident: Dictionary = {}
var _wanted: Dictionary = {}
var _requests: Dictionary = {}
var _pending_cells: Dictionary = {}
var _token: int = 0
var _scan_timer: float = 0.0
var _last_cell := Vector2i(-9999, -9999)
var _connected: bool = false
var stale_results: int = 0
var rejected_batches: int = 0

func _ready() -> void:
	if terrain == null or vegetation == null or camera == null:
		push_error("WorldEcosystem requires terrain, vegetation and camera")
		set_process(false)
		return
	terrain.surface_batch_ready.connect(_surface_ready)
	terrain.region_changed.connect(_region_changed)
	terrain.reload_started.connect(reset)
	_connected = true

func _cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / CELL_SIZE), floori(point.z / CELL_SIZE))

func _owner(key: Vector2i) -> String:
	return "natural/%d/%d" % [key.x, key.y]

func reset() -> void:
	for key in resident:
		vegetation.remove_chunk(_owner(key))
	resident.clear()
	_requests.clear()
	_pending_cells.clear()
	_wanted.clear()
	_last_cell = Vector2i(-9999, -9999)

func _process(delta: float) -> void:
	if not terrain.world_ready or not vegetation.ready_to_render:
		return
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
		if resident.has(key) or _pending_cells.has(key):
			continue
		var candidates: Dictionary = _candidates(key)
		if candidates["points"].is_empty():
			resident[key] = true
			continue
		_token += 1
		if terrain.request_surface_batch(candidates["points"], _token):
			candidates["key"] = key
			_requests[_token] = candidates
			_pending_cells[key] = _token
		break

func _refresh(center: Vector2i) -> void:
	var candidates: Array[Vector2i] = []
	var radius: int = ceili(stream_radius / CELL_SIZE)
	for z in range(maxi(0, center.y - radius), mini(31, center.y + radius) + 1):
		for x in range(maxi(0, center.x - radius), mini(31, center.x + radius) + 1):
			candidates.append(Vector2i(x, z))
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = (a - center).length_squared()
		var db: int = (b - center).length_squared()
		return da < db if da != db else (a.y * 32 + a.x < b.y * 32 + b.x))
	_wanted.clear()
	for i in range(mini(candidates.size(), max_resident_cells)):
		_wanted[candidates[i]] = true
	for key in resident.keys():
		if not _wanted.has(key):
			vegetation.remove_chunk(_owner(key))
			resident.erase(key)
	# Keep outstanding tokens until completion; this bounds work during teleports.

func _candidates(key: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ ((key.y * 32 + key.x + 1) * 73856093)
	var points := PackedVector3Array()
	var ids := PackedInt64Array()
	var rotations := PackedFloat32Array()
	var scales := PackedFloat32Array()
	for z in range(GRID):
		for x in range(GRID):
			var point := Vector3((key.x + (x + rng.randf_range(0.2, 0.8)) / GRID) * CELL_SIZE, 0.0, (key.y + (z + rng.randf_range(0.2, 0.8)) / GRID) * CELL_SIZE)
			var roll: float = rng.randf()
			var yaw: float = rng.randf_range(0.0, TAU)
			var scale: float = rng.randf_range(0.7, 1.18)
			# Ecological mask: grassy SW biome, tapered at the snow/sand boundaries.
			var biome: float = clampf((1000.0 - point.x) / 100.0, 0.0, 1.0) * clampf((point.z - 1000.0) / 100.0, 0.0, 1.0)
			if roll >= density * biome or not terrain.natural_column_available(point):
				continue
			points.append(point)
			ids.append(1 + (key.y * 32 + key.x) * GRID * GRID + z * GRID + x)
			rotations.append(yaw)
			scales.append(scale)
	return {"points": points, "ids": ids, "rotations": rotations, "scales": scales}

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
	if points.size() != request["ids"].size() or normals.size() != points.size():
		rejected_batches += 1
		return
	var ids := PackedInt64Array()
	var transforms: Array[Transform3D] = []
	var min_up: float = cos(deg_to_rad(max_slope_degrees))
	for i in range(points.size()):
		if not points[i].is_finite() or normals[i].y < min_up or not terrain.natural_column_available(points[i]):
			continue
		var basis := Basis(Vector3.UP, request["rotations"][i]).scaled(Vector3.ONE * request["scales"][i])
		ids.append(request["ids"][i])
		transforms.append(Transform3D(basis, points[i] - Vector3(0.0, 0.2, 0.0)))
	if vegetation.upsert_chunk(_owner(key), ids, transforms):
		resident[key] = true
	else:
		rejected_batches += 1

func _region_changed(bounds: AABB, _revision: int) -> void:
	# Match the conservative 16 m dirty-column exclusion, including boundary roots.
	var low: Vector3 = bounds.position
	var high: Vector3 = bounds.end
	low.x = floorf(low.x / 16.0) * 16.0
	low.z = floorf(low.z / 16.0) * 16.0
	high.x = (floorf(high.x / 16.0) + 1.0) * 16.0
	high.z = (floorf(high.z / 16.0) + 1.0) * 16.0
	low.y = -128.0
	high.y = 512.0
	vegetation.remove_roots_in_bounds(AABB(low, high - low))

func _exit_tree() -> void:
	if _connected and is_instance_valid(terrain):
		terrain.surface_batch_ready.disconnect(_surface_ready)
		terrain.region_changed.disconnect(_region_changed)
		terrain.reload_started.disconnect(reset)

extends Node3D
## Terrain-independent renderer with optional native nearby trunk collision.
signal initialization_failed(message: String)
const Renderer = preload("res://addons/vegetation/forest.gd")
const Assets = preload("res://addons/vegetation/assets.gd")
@export var camera: Camera3D
@export_range(64.0, 2200.0, 16.0) var draw_distance: float = 448.0
@export_range(0.0, 256.0, 8.0) var shadow_distance: float = 128.0
@export_range(0.0, 2.0, 0.05) var wind_strength: float = 0.3
@export var sun_direction := Vector3(-0.35, 0.75, 0.55).normalized()
@export_range(64, 65536, 64) var root_limit: int = 16384
var renderer = Renderer.new()
var assets = Assets.new()
var ready_to_render: bool = false
var _clock: float = 0.0
var trunk_collision: Node3D
var _collision_sync_ok:=true
func enable_trunk_collision() -> bool:
	if trunk_collision!=null: return true
	if not ClassDB.class_exists("NativeStaticBatch") or not renderer.roots.is_empty(): return false
	trunk_collision=ClassDB.instantiate("NativeStaticBatch")
	var proxy:=BoxMesh.new()
	if not trunk_collision.configure_asset("vegetation/trunk_proxy/v1",proxy) or not trunk_collision.configure_collision_only() or not trunk_collision.configure_collision(AABB(Vector3(-.35,0,-.35),Vector3(.7,8,.7)),96,256,16):
		trunk_collision.free();trunk_collision=null;return false
	add_child(trunk_collision)
	return true
func is_collision_region_ready(bounds: AABB) -> bool:
	return _collision_sync_ok and (trunk_collision==null or trunk_collision.is_collision_region_ready(bounds))

func _init() -> void:
	# Parent owns the renderer even if the facade is freed before entering a tree.
	renderer.name = "CellRenderer"
	add_child(renderer)

func _ready() -> void:
	set_process(false)

func initialize() -> Error:
	if ready_to_render:
		return ERR_ALREADY_IN_USE
	if transform != Transform3D.IDENTITY or (is_inside_tree() and global_transform != Transform3D.IDENTITY):
		return ERR_INVALID_PARAMETER
	assets = Assets.new()
	if not assets.build():
		initialization_failed.emit("Vegetation geometry or view data could not be loaded")
		return ERR_FILE_CORRUPT
	renderer.setup(assets.meshes, draw_distance)
	renderer.shadow_reach = shadow_distance
	ready_to_render = true
	set_process(true)
	return OK

func upsert_chunk(key: String, ids: PackedInt64Array, transforms: Array[Transform3D]) -> bool:
	if not ready_to_render:
		return false
	var old_size: int = 0
	for id in renderer.owners.get(key, PackedInt64Array()):
		if renderer.roots.has(id):
			old_size += 1
	if renderer.roots.size() - old_size + ids.size() > root_limit:
		return false
	var previous:=PackedInt64Array()
	for id in renderer.owners.get(key,PackedInt64Array()):
		if renderer.roots.has(id): previous.append(id)
	if trunk_collision!=null:
		for id in ids:
			if id<=0: return false
	if not renderer.upsert_chunk(key, ids, transforms): return false
	if trunk_collision!=null:
		if not trunk_collision.upsert_transforms(ids,transforms): _collision_sync_ok=false;return false
		var removed:=PackedInt64Array()
		for id in previous:
			if not ids.has(id): removed.append(id)
		if not removed.is_empty() and not trunk_collision.remove_instances(removed): _collision_sync_ok=false;return false
	return true

func remove_chunk(key: String) -> void:
	if trunk_collision!=null:
		var ids:=PackedInt64Array()
		for id in renderer.owners.get(key,PackedInt64Array()):
			if renderer.roots.has(id): ids.append(id)
		if not ids.is_empty() and not trunk_collision.remove_instances(ids): _collision_sync_ok=false
	renderer.remove_chunk(key)

func placement_bounds() -> AABB:
	# Maximum supported wind amplitude, before instance scale/rotation.
	return assets.meshes[0].get_aabb().grow(2.0) if ready_to_render else AABB()

func remove_root(id: int) -> bool:
	if not renderer.roots.has(id): return false
	if trunk_collision!=null and not trunk_collision.remove_instances(PackedInt64Array([id])): return false
	renderer.remove_root(id)
	return true

func remove_roots_in_bounds(bounds: AABB) -> int:
	# Spatial lookup touches only intersecting render cells. Surviving roots keep
	# their current LOD/fade state and owner, avoiding cell-wide disappearance.
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x < 0.0 or bounds.size.y < 0.0 or bounds.size.z < 0.0:
		return 0
	var removed: int = 0
	# Walk resident cells, not the area of arbitrary caller-provided bounds.
	for cell in renderer.cells.values():
		var origin: Vector3 = cell["origin"]
		if origin.x > bounds.end.x or origin.z > bounds.end.z or origin.x + Renderer.CELL < bounds.position.x or origin.z + Renderer.CELL < bounds.position.z:
			continue
		for id in cell["rows"].keys():
			if bounds.has_point((renderer.roots[id]["t"] as Transform3D).origin):
				if trunk_collision!=null and not trunk_collision.remove_instances(PackedInt64Array([id])): _collision_sync_ok=false
				renderer.remove_root(id)
				removed += 1
	return removed

func clear() -> void:
	for key in renderer.owners.keys():
		remove_chunk(key)
	# Flush even without a camera so unloaded GPU batches do not remain visible.
	renderer._clear_events()
	renderer._flush()
	renderer.max_scale = 1.0

func statistics() -> Dictionary:
	var result: Dictionary = renderer.stats.duplicate()
	result["resident_cells"] = renderer.cells.size()
	result["owners"] = renderer.owners.size()
	result["event_heap"] = renderer._heap_id.size()
	return result

func _process(delta: float) -> void:
	if not ready_to_render or not is_instance_valid(camera):
		return
	_clock += delta
	if trunk_collision!=null: trunk_collision.set_collision_focus(camera.global_position)
	var height: float = camera.get_viewport().get_visible_rect().size.y
	var projection: float = height / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	renderer.tick(camera.global_position, projection, _clock)
	assets.uniforms(camera.global_position, sun_direction, _clock, wind_strength, draw_distance, wind_strength > 0.0)

func _exit_tree() -> void:
	set_process(false)

extends "res://addons/volumetric_terrain/terrain_stream.gd"
## Public terrain facade. All coordinates are world coordinates; keep this node at identity.
## One facade per process until scene save/cache ownership supports multiple worlds.
## Windows TerrainCore instances now have independent native cancellation.
signal surface_batch_ready(token: int, points: PackedVector3Array, normals: PackedVector3Array, epoch_id: int, revision: int)
signal region_changed(bounds: AABB, revision: int)
signal region_invalidated(bounds: AABB)
signal lake_slice_ready(token: int, status: int, epoch_id: int, revision: int)
signal snapshot_restored(sections: Dictionary, epoch_id: int)
const TerrainAssets = preload("res://addons/volumetric_terrain/runtime_assets.gd")
static var _active_world: WeakRef
var _started: bool = false
var snapshot_restore_ok: bool = true
var density_revision: int = 0

func _read_stats(data: PackedByteArray) -> void:
	super._read_stats(data)
	if Codec.reply_ok(data) and data.size() >= 16:
		density_revision = data.decode_u32(12)
@export var save_slot: String = "world"

func start(terrain_material: Material = null, temporary_world: bool = false) -> Error:
	if stopping:
		return ERR_UNCONFIGURED
	if _started or (_active_world != null and _active_world.get_ref() != null):
		return ERR_ALREADY_IN_USE
	if transform != Transform3D.IDENTITY or (is_inside_tree() and global_transform != Transform3D.IDENTITY):
		push_error("TerrainWorld requires an identity transform")
		return ERR_INVALID_PARAMETER
	var selected: Material = terrain_material
	if selected == null:
		selected = TerrainAssets.make_terrain_material()
	if selected == null:
		return ERR_CANT_OPEN
	if save_slot.is_empty() or not save_slot.is_valid_identifier():
		return ERR_INVALID_PARAMETER
	var directory_error: Error = DirAccess.make_dir_recursive_absolute("user://worlds")
	if directory_error != OK:
		return directory_error
	backend.save_path = "user://worlds/" + save_slot + ".trw"
	backend.cache_path = "user://terrain_cache"
	_active_world = weakref(self)
	_started = true
	var error: Error = super.start(selected, temporary_world)
	if error != OK:
		shutdown()
	return error

func shutdown() -> void:
	super.shutdown()
	if _active_world != null and _active_world.get_ref() == self:
		_active_world = null
	_started = false

func natural_column_available(point: Vector3) -> bool:
	if point.x < 2.0 or point.z < 2.0 or point.x >= 1998.0 or point.z >= 1998.0:
		return false
	return not modified_columns.has(Vector2i(floori(point.x / 16.0), floori(point.z / 16.0)))

func request_surface_batch(points: PackedVector3Array, token: int) -> bool:
	# Admission control reserves the terrain worker for collision and interactive work.
	if not world_ready or pending_edit or foreground_brush or stopping or points.is_empty() or points.size() > 64 or backend.queued() > 8:
		return false
	for point in points:
		if not point.is_finite():
			return false
	return backend.submit({"kind": "surface_batch", "points": points.duplicate(), "token": token, "epoch": epoch, "revision": published_revision})

func _receive(result: Dictionary) -> void:
	if result.get("kind", "") in ["startup", "reload"] and not str(result.get("message", "")).begins_with("ERROR:"):
		if result.get("kind") == "startup" or int(result.get("epoch", -1)) == epoch:
			snapshot_restore_ok = true
			snapshot_restored.emit(result.get("components", {}), epoch)
			if not snapshot_restore_ok:
				backend.disable_snapshot_writes()
				result["message"] = "ERROR: addon restoration failed; canonical save protected"
	if result.get("kind", "") == "lake_slice":
		lake_slice_ready.emit(result["token"], result["status"], result["epoch"], result["revision"])
		return
	if result.get("kind", "") == "surface_batch":
		surface_batch_ready.emit(result["token"], result["points"], result["normals"], result["epoch"], result["revision"])
		return
	super._receive(result)

func _commit_batch() -> void:
	super._commit_batch()
	var low: Vector3 = geometry_lo.min(edit_lo)
	var high: Vector3 = geometry_hi.max(edit_hi)
	region_changed.emit(AABB(low, high - low), published_revision)

func edit(data: PackedByteArray, lo: Vector3, hi: Vector3, captured_us: int = 0, commands: Array[PackedByteArray] = [], member_captures: Array[Dictionary] = []) -> bool:
	# Validate the complete transaction before the base stream decodes or mutates it.
	if not lo.is_finite() or not hi.is_finite() or commands.size() > 4:
		return false
	var selected: Array[PackedByteArray] = []
	selected.assign(commands)
	if selected.is_empty():
		selected.append(data)
	var safe_lo := Vector3.INF
	var safe_hi := -Vector3.INF
	for packet in selected:
		if packet.size() < 4:
			return false
		var kind: int = packet.decode_u32(0)
		if kind == 2 and packet.size() == 44:
			var a := Vector3(packet.decode_float(4), packet.decode_float(8), packet.decode_float(12))
			var b := Vector3(packet.decode_float(16), packet.decode_float(20), packet.decode_float(24))
			var radius: float = packet.decode_float(28)
			if not a.is_finite() or not b.is_finite() or not is_finite(radius) or radius < 0.5 or radius > 64.0:
				return false
			if maxf(a.abs()[a.abs().max_axis_index()], b.abs()[b.abs().max_axis_index()]) > 10000.0:
				return false
			if packet.decode_u32(32) > 1 or packet.decode_u32(36) > 1 or packet.decode_u32(40) > 3:
				return false
			var halo: Vector3 = Vector3.ONE * (radius + 5.0)
			safe_lo = safe_lo.min(a.min(b) - halo)
			safe_hi = safe_hi.max(a.max(b) + halo)
		elif kind==28 and packet.size() in [36,40,44]:
			var a:=Vector3(packet.decode_float(4),packet.decode_float(8),packet.decode_float(12))
			var b:=Vector3(packet.decode_float(16),packet.decode_float(20),packet.decode_float(24))
			var width: float=packet.decode_float(28);var depth: float=packet.decode_float(32)
			var clearance: float=packet.decode_float(36) if packet.size()>=40 else 0.0
			if packet.size()==44 and (packet.decode_u32(40)<1 or packet.decode_u32(40)>4): return false
			if not is_finite(clearance) or clearance<0 or clearance>16 or maxf(a.y,b.y)+clearance>250: return false
			var distance:=Vector2(b.x-a.x,b.z-a.z).length()
			if not a.is_finite() or not b.is_finite() or not is_finite(width) or not is_finite(depth) or width<0.5 or width>16 or depth<1 or depth>8 or distance<1 or distance>128 or absf(b.y-a.y)>distance*0.25: return false
			for point: Vector3 in [a,b]:
				if point.x<width+5 or point.x>1995-width or point.z<width+5 or point.z>1995-width or point.y<depth+4 or point.y>250: return false
			safe_lo=safe_lo.min(a.min(b)-Vector3(width+5,depth+5,width+5))
			safe_hi=safe_hi.max(a.max(b)+Vector3(width+5,clearance+5,width+5))
		elif kind == 3 and packet.size() == 20:
			var cell := Vector3i(packet.decode_s32(4), packet.decode_s32(8), packet.decode_s32(12))
			if cell.x < 0 or cell.x >= 2000 or cell.z < 0 or cell.z >= 2000 or cell.y < 2 or cell.y >= 255 or packet.decode_u32(16) > 3:
				return false
			safe_lo = safe_lo.min(Vector3(cell) - Vector3.ONE * 2.0)
			safe_hi = safe_hi.max(Vector3(cell) + Vector3.ONE * 3.0)
		else:
			return false
	var accepted: bool = super.edit(data, safe_lo, safe_hi, captured_us, selected, member_captures)
	if accepted:
		region_invalidated.emit(AABB(safe_lo, safe_hi - safe_lo))
	return accepted

func request_lake_slice(builder: RefCounted, token: int) -> bool:
	# Optional native addon protocol: terrain has no dependency on its renderer.
	if builder == null or builder.get_class() != "NativeLakeVolume":
		return false
	if not world_ready or pending_edit or foreground_brush or stopping:
		return false
	return backend.submit({"kind": "lake_slice", "builder": builder, "token": token, "epoch": epoch, "revision": published_revision, "density_revision": density_revision})

func sculpt_sphere(center: Vector3, radius: float, add: bool = false, material_id: int = 1) -> bool:
	return edit(Codec.brush(center, center, radius, 0, add, material_id), center, center)

func set_block(cell: Vector3i, material_id: int) -> bool:
	return edit(Codec.command(3, [cell.x, cell.y, cell.z, material_id]), Vector3(cell), Vector3(cell))

func construct_road_bed(a: Vector3,b: Vector3,half_width: float=3.0,depth: float=2.0,clearance: float=0.0) -> bool:
	return edit(Codec.road_bed(a,b,half_width,depth,clearance),a.min(b),a.max(b))

func construct_graded_bed(a: Vector3,b: Vector3,half_width: float,depth: float,clearance: float,material_id: int=3) -> bool:
	return edit(Codec.graded_bed(a,b,half_width,depth,clearance,material_id),a.min(b),a.max(b))

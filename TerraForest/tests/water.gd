extends SceneTree
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "pass": ok})
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)

func field(size: Vector3i, open_edge: bool = false, divide: bool = false) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	for z in range(size.z + 1):
		for y in range(size.y + 1):
			for x in range(size.x + 1):
				var solid: bool = x <= 0 or x >= size.x or z <= 0 or (z >= size.z and not open_edge) or y <= 0 or (divide and x == size.x / 2)
				data.append(-1.0 if solid else 1.0)
	return data

func volume(origin := Vector3.ZERO, cells := Vector3i(8, 6, 8), level: float = 3.5, seed := Vector3(2.5, 2.5, 2.5)) -> RefCounted:
	var v: RefCounted = ClassDB.instantiate("NativeLakeVolume")
	check(v.configure(origin, cells, 1.0, level, seed), "bounded lake builder configured")
	return v

func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	check(ClassDB.class_exists("NativeLakeVolume"), "independent water GDExtension registered")
	var v: RefCounted = ClassDB.instantiate("NativeLakeVolume")
	check(not v.configure(Vector3.ZERO, Vector3i(128,64,128), 1, 3, Vector3(2,2,2)), "hard voxel cap rejects oversized allocation")
	check(not v.configure(Vector3.INF, Vector3i(8,6,8), 1, 3, Vector3(2,2,2)), "nonfinite origin rejected")
	check(not v.configure(Vector3.ZERO, Vector3i(8,6,8), NAN, 3, Vector3(2,2,2)), "nonfinite spacing rejected")
	v = volume()
	var data: PackedFloat32Array = field(Vector3i(8,6,8))
	check(v.bake_density(PackedFloat32Array([1.0])) == -1, "incomplete density field rejected without committing")
	var invalid: PackedFloat32Array = data.duplicate()
	invalid[12] = NAN
	check(v.bake_density(invalid) == -1, "nonfinite density rejected before mutation")
	check(v.bake_density(data) == 1, "connected sealed basin bakes")
	check(v.contains(Vector3(2.5, 2.5, 2.5)) and is_equal_approx(v.depth_at(Vector3(2.5,2.5,2.5)),1.0), "3D occupancy and submerged depth agree")
	check(not v.contains(Vector3(2.5, 3.5, 2.5)) and not v.contains(Vector3(2.5,0.5,2.5)) and not v.contains(Vector3(-1,2,2)), "surface, solid floor and exterior are dry")
	check(not v.contains(Vector3.INF) and v.depth_at(Vector3(NAN,0,0)) == 0, "invalid query positions are dry")
	check(not v.configure(Vector3.ZERO,Vector3i(8,6,8),1,3,Vector3(2,2,2)) and v.bake_density(data) == -1, "published volume is immutable")
	check(v.statistics()["builder_bytes"] == 0 and v.statistics()["resident_bytes"] == 384, "bake scratch freed and occupancy remains bounded")
	var mesh: Array = v.surface_arrays()
	check(mesh[Mesh.ARRAY_VERTEX].size() == 24 and mesh[Mesh.ARRAY_INDEX].size() == 36, "surface rows merged without interior volume faces")
	var edge: RefCounted = volume()
	check(edge.bake_density(field(Vector3i(8,6,8),true)) == -3 and not edge.contains(Vector3(2.5,2.5,2.5)), "open boundary rejects entire lake without partial publication")
	var wall: RefCounted = volume()
	check(wall.bake_density(field(Vector3i(8,6,8),false,true)) == 1 and not wall.contains(Vector3(5.5,2.5,2.5)), "flood fill does not fill disconnected neighboring basin")
	var roof_field: PackedFloat32Array = data.duplicate()
	for z in range(2,7):
		for x in range(4,7):
			roof_field[x+9*(3+7*z)] = -1.0
	var cave: RefCounted = volume()
	check(cave.bake_density(roof_field)==1 and cave.contains(Vector3(4.5,1.5,4.5)) and not cave.contains(Vector3(4.5,2.5,4.5)), "connected water occupies below cave roof while solid ceiling stays dry")
	var blocked: RefCounted = volume(Vector3.ZERO,Vector3i(8,6,8),3.5,Vector3(0.5,0.5,0.5))
	check(blocked.bake_density(data)==-2 and not blocked.contains(Vector3(2.5,2.5,2.5)), "blocked seed rejects publication")
	var shifted: RefCounted = volume(Vector3(-20,-10,-30),Vector3i(8,6,8),-6.5,Vector3(-17.5,-7.5,-27.5))
	check(shifted.bake_density(data) == 1 and shifted.contains(Vector3(-17.5,-7.5,-27.5)), "negative world coordinates preserve occupancy indexing")
	var large: RefCounted = volume(Vector3.ZERO,Vector3i(64,64,64),48.5,Vector3(32,24,32))
	var large_field: PackedFloat32Array = field(Vector3i(64,64,64))
	var begin: int = Time.get_ticks_usec()
	check(large.bake_density(large_field) == 1, "maximum configured cell budget bakes")
	var bake_ms: float = (Time.get_ticks_usec()-begin)/1000.0
	check(large.statistics()["resident_bytes"] == 262144 and large.statistics()["builder_bytes"] == 0, "262144-cell lake frees all temporary scratch")
	# Exercise real native terrain density including an excavated sphere.
	var core: RefCounted = ClassDB.instantiate("TerrainCore")
	var height: PackedByteArray = core.execute(Codec.point_command(Vector3(800,50,1310)))
	var center := Vector3(800,floorf(height.decode_float(12)),1310)
	var carve: PackedByteArray = core.execute(Codec.brush(center,center,12,0,false,1))
	check(Codec.reply_ok(carve), "actual terrain basin excavation accepted")
	var revision: int = core.execute(Codec.command(0)).decode_u32(12)
	var epoch: int = core.execute(Codec.command(13)).decode_u32(12)
	var sampled: RefCounted = volume(center-Vector3(16,16,16),Vector3i(32,20,32),center.y-3,center-Vector3(0,6,0))
	var slices: int = 0
	var result: int = 0
	begin = Time.get_ticks_usec()
	while result == 0 and slices < 2000:
		result = sampled.sample_terrain(core,512,revision,epoch)
		slices += 1
	check(result == 1 and sampled.contains(center-Vector3(0,6,0)), "bounded slices sample actual edited 3D terrain into water occupancy")
	var sampled_ms: float = (Time.get_ticks_usec()-begin)/1000.0
	var stale: RefCounted = volume(center-Vector3(16,16,16),Vector3i(32,20,32),center.y-3,center-Vector3(0,6,0))
	check(stale.sample_terrain(core,32,revision+1,epoch) == -4, "terrain revision mismatch cancels bake")
	var cancelled: RefCounted = volume(center-Vector3(16,16,16),Vector3i(32,20,32),center.y-3,center-Vector3(0,6,0))
	core.execute(Codec.command(12))
	check(cancelled.sample_terrain(core,32,revision,epoch) == -4, "terrain cancellation epoch rejects stale bake")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var output := FileAccess.open("res://reports/water.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"large_bake_ms":bake_ms,"terrain_sample_ms":sampled_ms,"terrain_slices":slices,"scope":"CPU correctness and bake costs; no flow simulation or multiplayer claim"},"  "))
	output.close()
	quit(0 if failures==0 else 1)

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

# Independent geometric coverage oracle: every grid-cell center is covered once
# iff its volume reaches the fill-level layer. Also check area, indices and UVs.
func exact_surface(v: RefCounted, label: String) -> void:
	var arrays: Array = v.surface_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bounds: AABB = v.bounds()
	var spacing: float = v.statistics()["spacing"]
	var level: float = v.statistics()["fill_level"]
	var valid: bool = vertices.size() % 4 == 0 and indices.size() == vertices.size() / 4 * 6 and normals.size() == vertices.size() and uv.size() == vertices.size()
	var area: float = 0.0
	for first in range(0, vertices.size(), 4):
		var a: Vector3 = vertices[first]
		var c: Vector3 = vertices[first + 2]
		valid = valid and c.x > a.x and c.z > a.z
		valid = valid and vertices[first+1] == Vector3(c.x,level,a.z) and vertices[first+3] == Vector3(a.x,level,c.z)
		area += (c.x-a.x)*(c.z-a.z)
		var expected := PackedInt32Array([0,1,2,0,2,3])
		for k in range(6):
			valid = valid and indices[first / 4 * 6 + k] == first + expected[k]
		for k in range(4):
			var p: Vector3 = vertices[first+k]
			valid = valid and is_equal_approx(p.y,level) and normals[first+k] == Vector3.UP and uv[first+k] == Vector2(p.x,p.z)
	var wet_cells: int = 0
	for z in range(roundi(bounds.size.z/spacing)):
		for x in range(roundi(bounds.size.x/spacing)):
			var p := Vector3(bounds.position.x+(x+0.5)*spacing,level-0.001,bounds.position.z+(z+0.5)*spacing)
			var expected: int = 1 if v.contains(p) else 0
			wet_cells += expected
			var covered: int = 0
			for first in range(0,vertices.size(),4):
				var a: Vector3 = vertices[first]
				var c: Vector3 = vertices[first+2]
				if p.x > a.x and p.x < c.x and p.z > a.z and p.z < c.z:
					covered += 1
			valid = valid and covered == expected
	valid = valid and is_equal_approx(area,wet_cells*spacing*spacing)
	valid = valid and arrays == v.surface_arrays()
	check(valid,label)

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
	check(mesh[Mesh.ARRAY_VERTEX].size() == 4 and mesh[Mesh.ARRAY_INDEX].size() == 6, "rectangular basin reduces six strips to one quad")
	exact_surface(v,"rectangle surface has exact nonoverlapping coverage, stable UVs and deterministic extraction")
	var edge: RefCounted = volume()
	check(edge.bake_density(field(Vector3i(8,6,8),true)) == -3 and not edge.contains(Vector3(2.5,2.5,2.5)), "open boundary rejects entire lake without partial publication")
	var wall: RefCounted = volume()
	check(wall.bake_density(field(Vector3i(8,6,8),false,true)) == 1 and not wall.contains(Vector3(5.5,2.5,2.5)), "flood fill does not fill disconnected neighboring basin")
	exact_surface(wall,"disconnected dry basin is absent from merged surface")
	var roof_field: PackedFloat32Array = data.duplicate()
	for z in range(2,7):
		for x in range(4,7):
			roof_field[x+9*(3+7*z)] = -1.0
	var cave: RefCounted = volume()
	check(cave.bake_density(roof_field)==1 and cave.contains(Vector3(4.5,1.5,4.5)) and not cave.contains(Vector3(4.5,2.5,4.5)), "connected water occupies below cave roof while solid ceiling stays dry")
	exact_surface(cave,"irregular cave roof remains absent from merged fill surface")
	var island_field: PackedFloat32Array = data.duplicate()
	for y in range(7):
		island_field[4+9*(y+7*4)] = -1.0
	var island: RefCounted = volume()
	check(island.bake_density(island_field)==1,"connected lake around central island bakes")
	exact_surface(island,"surface rectangles preserve central island hole without overlaps")
	var blocked: RefCounted = volume(Vector3.ZERO,Vector3i(8,6,8),3.5,Vector3(0.5,0.5,0.5))
	check(blocked.bake_density(data)==-2 and not blocked.contains(Vector3(2.5,2.5,2.5)), "blocked seed rejects publication")
	var shifted: RefCounted = volume(Vector3(-20,-10,-30),Vector3i(8,6,8),-6.5,Vector3(-17.5,-7.5,-27.5))
	check(shifted.bake_density(data) == 1 and shifted.contains(Vector3(-17.5,-7.5,-27.5)), "negative world coordinates preserve occupancy indexing")
	exact_surface(shifted,"negative coordinates preserve merged surface coverage")
	var scaled: RefCounted = ClassDB.instantiate("NativeLakeVolume")
	check(scaled.configure(Vector3(-20,-10,-30),Vector3i(8,6,8),2,-4,Vector3(-15,-5,-25)) and scaled.bake_density(data)==1,"scaled lattice with integer fill elevation bakes")
	exact_surface(scaled,"scaled lattice and exact layer boundary preserve surface coverage and UVs")
	var large: RefCounted = volume(Vector3.ZERO,Vector3i(64,64,64),48.5,Vector3(32,24,32))
	var large_field: PackedFloat32Array = field(Vector3i(64,64,64))
	var begin: int = Time.get_ticks_usec()
	check(large.bake_density(large_field) == 1, "maximum configured cell budget bakes")
	var bake_ms: float = (Time.get_ticks_usec()-begin)/1000.0
	check(large.statistics()["resident_bytes"] == 262144 and large.statistics()["builder_bytes"] == 0, "262144-cell lake frees all temporary scratch")
	check(large.surface_arrays()[Mesh.ARRAY_VERTEX].size()==4,"maximum-cell rectangular basin reduces 62 strips to one quad")
	exact_surface(large,"maximum-cell basin preserves exact surface coverage")
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
	var cache_id: PackedByteArray=sampled.cache_identity(core,"test-build-v1")
	var cached: PackedByteArray=sampled.capture_bake(cache_id)
	check(cache_id.size()==32 and not cached.is_empty(),"native local terrain dependency identity available")
	var reuse: RefCounted=ClassDB.instantiate("NativeLakeVolume")
	reuse.configure(center-Vector3(16,16,16),Vector3i(32,20,32),1,center.y-3,center-Vector3(0,6,0))
	check(reuse.restore_bake(cached,cache_id) and reuse.statistics().sampled_nodes==0,"configured fresh worker builder accepts matching cache")
	core.execute(Codec.brush(Vector3(100,30,100),Vector3(100,30,100),3,0,false,1))
	check(sampled.cache_identity(core,"test-build-v1")==cache_id,"remote edits retain local lake identity")
	core.execute(Codec.brush(center-Vector3(0,6,0),center-Vector3(0,6,0),2,0,true,1))
	var changed: PackedByteArray=sampled.cache_identity(core,"test-build-v1")
	var rejected: RefCounted=ClassDB.instantiate("NativeLakeVolume")
	check(changed.size()==32 and changed!=cache_id and not rejected.restore_bake(cached,changed),"local terrain edit invalidates old bake")
	check(sampled.cache_identity(core,"test-build-v2")!=changed,"implementation fingerprint invalidates cache")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var output := FileAccess.open("res://reports/water.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"large_bake_ms":bake_ms,"terrain_sample_ms":sampled_ms,"terrain_slices":slices,"scope":"CPU correctness and bake costs; no flow simulation or multiplayer claim"},"  "))
	output.close()
	quit(0 if failures==0 else 1)

extends SceneTree
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
var core: RefCounted
var rows: Array[Dictionary] = []
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func build(x: int, z: int, size: int, step: int, label: String) -> void:
	var begin := Time.get_ticks_usec()
	var reply: PackedByteArray = core.execute(Codec.command(1,[x,z,size,step]))
	var total := (Time.get_ticks_usec()-begin)/1000.0
	if not Codec.reply_ok(reply):
		failures += 1
		return
	var profile: PackedByteArray = core.execute(Codec.command(19))
	rows.append({"label":label,"x":x,"z":z,"size":size,"step":step,"total_ms":total,
		"extraction_ms":profile.decode_float(12),"simplification_ms":profile.decode_float(16),
		"shading_ms":profile.decode_float(24),"without_extraction_ms":total-profile.decode_float(12),
		"vertices":reply.decode_u32(40),"triangles":reply.decode_u32(44)/3,"bytes":reply.size()})

func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	core = ClassDB.instantiate("TerrainCore")
	core.execute(Codec.command(18,[1]))
	var p := Vector3(1296,0,1296)
	p.y = core.execute(Codec.point_command(p)).decode_float(12)
	var edit: PackedByteArray = core.execute(Codec.brush(p,p,2.5,0,false,1))
	if not Codec.reply_ok(edit) or edit.decode_u32(16)==0: failures += 1
	# Same edited field and edit location. Alternate size order to reduce order bias.
	for iteration in range(4):
		var sizes := [16,32,64,128,256]
		if iteration%2: sizes.reverse()
		for size in sizes:
			build(1296-size/2,1296-size/2,size,maxi(1,size/32),"nested_warmup" if iteration==0 else "nested")
	# A brush on a 16 m corner touches four reconstruction owners. This is a
	# component lower bound: cross-region lighting/publication is NOT represented.
	for iteration in range(3):
		for z in [1280,1296]:
			for x in [1280,1296]: build(x,z,16,1,"four_local_regions")
	# Test the obvious but dangerous alternative: render an entire distant patch
	# as fine independent regions. Record full rebuild and geometry amplification.
	build(1280,1280,256,8,"distant_monolith")
	for z in range(1280,1536,16):
		for x in range(1280,1536,16): build(x,z,16,1,"distant_fine_partition")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var report := {"failures":failures,"seed":1703,"edit":str(p),"samples":rows,
		"scope":"Decision probe only. Same field, one actual corner edit, no cache implementation. Local-region totals omit global lighting dependencies, seam/LOD correctness, collision publication and rendering. Partition geometry counts do not measure draw-call or GPU cost."}
	var file := FileAccess.open("res://reports/terrain_locality_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("LOCALITY_PROBE samples=",rows.size()," failures=",failures)
	core = null
	quit(0 if failures==0 else 1)

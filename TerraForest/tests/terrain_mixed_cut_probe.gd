extends SceneTree
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
var rows: Array[Dictionary] = []
var failures := 0
var core: RefCounted

func _initialize() -> void:
	run.call_deferred()

func build(site: String, phase: String, request: Array) -> void:
	var begin := Time.get_ticks_usec()
	var reply: PackedByteArray = core.execute(Codec.command(1,request))
	var elapsed := (Time.get_ticks_usec()-begin)/1000.0
	if not Codec.reply_ok(reply): failures += 1
	var name := "%s_%s_%d_%d_%d.bin" % [site,phase,request[0],request[1],request[2]]
	var file := FileAccess.open("res://reports/"+name,FileAccess.WRITE)
	file.store_buffer(reply)
	file.close()
	rows.append({"site":site,"phase":phase,"request":request,"file":name,"native_ms":elapsed,"bytes":reply.size()})

func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	DirAccess.make_dir_recursive_absolute("res://reports")
	core = ClassDB.instantiate("TerrainCore")
	for site in [["mountain",1280,1280,1296,1296],["cave",768,768,976,976]]:
		core.execute(Codec.command(6,[1703]))
		# Refine toward the edit along an aligned quadtree path, leaving siblings.
		# A 256 m extent is covered by 13 owners rather than 256 fine owners.
		var requests: Array = []
		var origin := Vector2i(site[1],site[2])
		for size in [128,64,32]:
			var selected := Vector2i(floori(float(site[3])/size)*size,floori(float(site[4])/size)*size)
			for offset in [Vector2i.ZERO,Vector2i(size,0),Vector2i(0,size),Vector2i(size,size)]:
				var child: Vector2i = origin+offset
				if child!=selected: requests.append([child.x,child.y,size,maxi(1,size/32)])
			origin = selected
		for dz in [0,16]:
			for dx in [0,16]: requests.append([origin.x+dx,origin.y+dz,16,1])
		for phase in ["before","after"]:
			if phase=="after":
				var point := Vector3(site[3],0,site[4])
				point.y = core.execute(Codec.point_command(point)).decode_float(12)
				var edit: PackedByteArray = core.execute(Codec.brush(point,point,2.5,0,false,1))
				if not Codec.reply_ok(edit) or edit.decode_u32(16)==0: failures += 1
			build(site[0],phase,[site[1],site[2],256,8])
			for request in requests: build(site[0],phase,request)
	var file := FileAccess.open("res://reports/terrain_mixed_cut_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"rows":rows}))
	file.close()
	quit(0 if failures==0 else 1)

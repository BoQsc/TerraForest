extends SceneTree
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var core: RefCounted = ClassDB.instantiate("TerrainCore")
	var rows: Array = []
	var failures := 0
	for site in [["mountain",1280,1280],["cave",960,960],["world_edge",0,0],["far_edge",1984,1984],["edited_corner",1280,1280]]:
		core.execute(Codec.command(6,[1703]))
		if site[0]=="edited_corner":
			var p := Vector3(1312,0,1312)
			p.y = core.execute(Codec.point_command(p)).decode_float(12)
			var reply: PackedByteArray = core.execute(Codec.brush(p,p,5,0,false,1))
			if not Codec.reply_ok(reply) or reply.decode_u32(16)==0: failures += 1
		var requests: Array = [[site[1],site[2],64,1]]
		for dz in [0,32]:
			for dx in [0,32]:
				for step in [1,2,4,8]: requests.append([site[1]+dx,site[2]+dz,32,step])
		for request in requests:
			var begin := Time.get_ticks_usec()
			var reply: PackedByteArray = core.execute(Codec.command(1,request))
			var elapsed := (Time.get_ticks_usec()-begin)/1000.0
			if not Codec.reply_ok(reply): failures += 1
			var name := "%s_%d_%d_%d_%d.bin" % [site[0],request[0],request[1],request[2],request[3]]
			var file := FileAccess.open("res://reports/"+name,FileAccess.WRITE)
			file.store_buffer(reply)
			file.close()
			rows.append({"site":site[0],"request":request,"file":name,"native_ms":elapsed})
	var file := FileAccess.open("res://reports/terrain_boundary_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"rows":rows}))
	file.close()
	core = null
	quit(0 if failures==0 else 1)
